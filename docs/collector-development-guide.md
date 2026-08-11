# Collector Development Guide

This guide explains how log collectors are built in this repo. It uses the
two reference implementations in `templates/`, `aws-cloudtrail-collector-tpl`
(push) and `gcp-collector-tpl` (pull), and shows how the transform stage
(Logstash) is an interchangeable component rather than a hard dependency,
using `generic-http-tpl` as proof.

Every collector is one Kubernetes `Deployment` (one pod), templated under
`templates/<name>-collector-tpl/`. It gets instantiated per tenant, per
integration, by scripts in `scripts/` (for example `scripts/add_cloudtrail.sh`
and `scripts/add_gcp.sh`) into
`mgmt/<env>/helm/loki-base/kustomize/tenants/<tenant_id>/collectors/<integration_id>/`.
The scripts use `sed` to replace placeholders (`<tenant_id>`,
`<intergation_id>`, note the misspelling; keep it that way when copying
templates, `<siem_env>`, `<tenant_endpoint>`, `<siem_domain>`) and push
credentials into Vault.

## 1. The core architecture: two stages in one pod

Every collector pod is built from up to two containers with one fixed
contract between them:

```
[source] ---> [stage 1: intake/transform]  --->  [stage 2: Alloy loki.source.api] ---> Loki
                 (Logstash, or nothing)              always on :8080, always the
                                                       same job in every template
```

Stage 2 never changes. Every collector template, push or pull, with or
without Logstash, carries an identical Grafana Alloy container whose only
config block is:

```alloy
loki.source.api "raw_logs" {
  http {
    listen_address = "0.0.0.0"
    listen_port    = 8080
  }
  labels = {
    job = "<some-job-label>",
  }
  forward_to = [loki.write.loki_out.receiver]
}

loki.write "loki_out" {
  endpoint {
    url = "http://loki-gateway.loki.svc.cluster.local/loki/api/v1/push"
    basic_auth {
      username = "{{ .username }}"
      password = "{{ .password }}"
    }
  }
}
```

(See `aws-external-secrets-cgf.yaml`, `gcp-alloy-secrets-cgf.yaml`, and
`http-external-secrets-cgf.yaml`: same block, different `job` label.)

Alloy's `loki.source.api` component exposes an endpoint at
`/loki/api/v1/raw` that accepts arbitrary JSON lines and forwards them to
Loki under the tenant's identity (the `loki_tenant` credentials from
`tenants/<tenant_id>/loki_tenant` in Vault). Whatever sits in front of Alloy
has exactly one job: get log data, in JSON, to
`http://localhost:8080/loki/api/v1/raw` inside the pod. That is the entire
contract. Stage 1 is free to be anything that can honor it, which is what
makes Logstash swappable (see section 4).

The `job` label set in Alloy's config is what downstream detection rules key
on. For example, `templates/loki-base/rules/common/aws.rules` matches
`{job="cloudtrail"}`, and `gcp.rules` matches `{job="gcplog"}`. If you rename
the job label when building a new collector, update the matching rules too.

## 2. Push vs. pull: what actually differs

The distinction is purely about who initiates the data transfer, and it
determines whether the collector needs a `Service` and `Ingress` (push) or
not (pull):

| | Push (CloudTrail) | Pull (GCP) |
|---|---|---|
| Who moves data | External sender POSTs to us | We actively fetch from a queue |
| `service.yaml` | Yes, exposes :9090 | Absent from template |
| `httproute.yaml` (Ingress) | Yes, public path, nginx basic auth | Absent from template |
| Stage-1 input | Logstash `http` input, port 9090 | Logstash `google_pubsub` input |
| Extra credentials | HTTP basic-auth user/pass | GCP service-account JSON key |
| Files: `templates/aws-cloudtrail-collector-tpl/` | full set (6 files) | not applicable |
| Files: `templates/gcp-collector-tpl/` | not applicable | 4 files, no networking |

### 2.1 Push-based: AWS CloudTrail

Files: [aws-cloudtrail-collector-tpl](../templates/aws-cloudtrail-collector-tpl)

Request path, end to end:

```
CloudTrail (S3/SNS/whatever ships it) --HTTPS-->
  nginx Ingress (basic auth: shared tenant htpasswd)
    rewrite -> /loki/api/v1/raw
    -> Service aws-<integration_id>:9090
      -> logstash container, http input :9090 (2nd basic-auth check,
         per-integration creds)
         -> filter{} block (see below)
         -> output http POST http://localhost:8080/loki/api/v1/raw
            -> Alloy container :8080 (loki.source.api)
               -> Loki (tenant loki_tenant creds)
```

Key files:
- `deployment.yaml`: two containers, `aws-alloy-<intergation_id>` (Alloy)
  and `logstash`, sharing a pod. Logstash mounts its pipeline config from a
  Secret and listens on 9090 (data) and 9091 (readiness).
- `aws-logstash-config-external-secrets.yaml`: the actual pipeline logic,
  rendered into a Vault-backed `pipeline.conf`:
  - `input { http { port => 9090, user/password => ... } }`, the
    per-integration credentials pulled from
    `tenants/<tenant_id>/aws/<intergation_id>/creds`.
  - a second `http { port => 9091, type => "readiness" }` input used only by
    the Kubernetes readiness probe. The `filter{}` block immediately
    `drop{}`s anything tagged `readiness` so health checks never become log
    lines.
  - `filter{}` parses the JSON body, drops `kube-probe` user agents, does
    GeoIP enrichment on `sourceIPAddress`, and strips Logstash's own
    bookkeeping fields (`@version`, `headers`, `host`, `http`, `url`) before
    forwarding. This is the "transform" work a collector-specific tool is
    responsible for.
  - `output { http { url => "http://localhost:8080/loki/api/v1/raw" } }`,
    the fixed contract with Alloy described in section 1.
- `aws-external-secrets-cgf.yaml`: Alloy's own config (the fixed block from
  section 1) with `job = "cloudtrail"`.
- `service.yaml` / `httproute.yaml`: expose port 9090 externally at
  `/<siem_env>/<tenant_id>/<tenant_endpoint>/<intergation_id>/push`,
  protected by nginx's shared basic-auth secret (`htpasswd`) in addition to
  Logstash's own per-integration basic auth. That is two independent auth
  checks stacked for push collectors.

`aws-cloudwatch-collector-tpl` and `azure-collector-tpl` follow this same
push shape (the same `filter{}` even branches on `[type] == "azure"` inside
the CloudTrail pipeline file, since that pipeline config was written to be
shared and copy-pasted across cloud types).

### 2.2 Pull-based: GCP (Pub/Sub)

Files: [gcp-collector-tpl](../templates/gcp-collector-tpl)

There is no inbound request at all. Nothing external ever talks to this pod:

```
GCP Cloud Logging --(sink)--> Pub/Sub topic/subscription
                                      ^
                                      | pulled by
                              logstash container (google_pubsub input)
                                -> filter{} -> http POST :8080/loki/api/v1/raw
                                      -> Alloy -> Loki
```

Key differences from the CloudTrail template:
- No `service.yaml` and no `httproute.yaml`. Confirm this by checking
  `gcp-collector-tpl/kustomization.yaml`: it only lists `deployment.yaml` and
  the three `ExternalSecret` files. There is nothing to route traffic to
  because nothing arrives.
- The `gcp-logstash-config-external-secrets.yaml` input block uses the
  `google_pubsub` Logstash plugin instead of `http`:
  ```
  input {
    google_pubsub {
      project_id      => "{{ .project }}"
      topic           => "{{ .topic }}"
      subscription    => "{{ .subscription }}"
      json_key_file   => "/gcp/key.json"
      max_messages    => 100
      create_subscription => false
      type            => "gcp"
    }
    http { port => 9091, type => "readiness" }   # readiness probe only, as above
  }
  ```
  `project`, `topic`, and `subscription` come from Vault
  (`tenants/<tenant_id>/gcp/<intergation_id>/info`).
- `gcp-logstash-key-external-secrets.yaml`: a third `ExternalSecret` that
  does not exist in the push templates. It decodes a GCP service-account key
  (`tenants/<tenant_id>/gcp/<intergation_id>/key`, base64-decoded via
  `{{ .key | b64dec }}`) into `key.json`, mounted at `/gcp/` and referenced
  by `json_key_file` above. Pull collectors generally need to carry their
  own credentials for the source system, since nobody is authenticating to
  them.
- The `filter{}` block follows the same JSON-parse-plus-GeoIP pattern as
  CloudTrail, keyed on `[type] == "gcp"` (source field
  `[protoPayload][requestMetadata][callerIp]`).
- It still exposes 9091 internally for its own readiness probe. That is
  pod-internal (`readinessProbe.httpGet.port: 9091` in `deployment.yaml`),
  not cluster-exposed, since there is no Service.
- The `job` label in `gcp-alloy-secrets-cgf.yaml` is `gcplog`, matching
  `loki-base/rules/common/gcp.rules`.

Rule of thumb when building a new collector: if the source system can be
told to call you (webhook, SNS to HTTPS, agent push), build push (copy
`aws-cloudtrail-collector-tpl`: Service, Ingress, and an `http` Logstash
input). If you must go fetch from a queue, API, or SDK (Pub/Sub, SQS, an
audit-log REST API, a polling job), build pull (copy `gcp-collector-tpl`: no
networking, an input plugin instead of `http`, and whatever credential that
plugin needs mounted in).

## 3. Logstash is a replaceable transform stage, not a fixed dependency

Nothing in the architecture requires Logstash. Its only obligations are: (a)
get data in, however the source demands, (b) enrich and clean it, and (c)
`POST` JSON to `http://localhost:8080/loki/api/v1/raw`. Any tool that can do
those three things is a legal substitute: Fluent Bit, Vector, Filebeat, a
custom script, a cloud function, or, as shown below, nothing at all if the
source can already speak Alloy's protocol directly.

The image itself is unremarkable. `deployment.yaml` just pulls
`public.ecr.aws/k9v9d5v2/admin-tools/crd-collectors/logstash:v1.0.1` and runs
`-f /configs/pipeline.conf`. Swapping it for another tool means:
1. Replacing that container image and its args/ports in `deployment.yaml`.
2. Replacing `*-logstash-config-external-secrets.yaml` with whatever config
   format the new tool uses, keeping the same three responsibilities above.
3. Keeping the Alloy container and its `loki.source.api` block byte-for-byte.
   Do not touch stage 2.
4. Keeping the readiness-probe convention (a cheap, always-200 endpoint) so
   `deployment.yaml`'s `readinessProbe` still has something to hit.

### 3.1 Proof: `generic-http-tpl` has no Logstash at all

Files: [generic-http-tpl](../templates/generic-http-tpl)

For sources that already emit clean JSON over HTTP and need no
transformation, the transform stage is simply skipped. Alloy's
`loki.source.api` is the collector:

```
Any HTTP client --HTTPS--> nginx Ingress (basic auth: shared htpasswd)
                              rewrite -> /loki/api/v1/raw
                              -> Service http-<integration_id>:8080
                                -> Alloy container :8080 (loki.source.api)
                                   -> Loki
```

Compare `generic-http-tpl/deployment.yaml` to
`aws-cloudtrail-collector-tpl/deployment.yaml`: it has exactly one container
(`http-<intergation_id>`, the Alloy image), one volume, no Logstash, and no
port 9090/9091 split. `http-external-secrets-cgf.yaml` is the same fixed
Alloy block from section 1 with `job = "<intergation_id>"`. The
`service.yaml`/`httproute.yaml` pair routes straight to port 8080 instead of
9090.

The tradeoff to know before copying this template: with Logstash gone, you
lose the per-integration credential check it was doing on its own `http`
input. `generic-http-tpl` only has the shared, tenant-wide nginx basic-auth
(`htpasswd`) at the Ingress. There is no equivalent of CloudTrail's
`tenants/<tenant_id>/aws/<intergation_id>/creds` per-integration user/pass,
because Alloy's `loki.source.api` `http` block has no per-request auth
option in this config. It also means no filtering or enrichment (no GeoIP,
no field stripping) happens before data lands in Loki; whatever the client
sends is what gets indexed, verbatim. Use the no-transform pattern only when
the source is trusted, already emits clean JSON, and per-integration auth
is not a requirement. Otherwise keep, or add back, a transform-stage
container.

## 4. Building a new collector: checklist

**Push, with transform (copy `aws-cloudtrail-collector-tpl`):**
1. `cp -r templates/aws-cloudtrail-collector-tpl templates/<new>-collector-tpl`
2. Edit the transform container's pipeline config: swap the `input {}` block
   for your source's push mechanism (keep `http` if it's a webhook, change
   the port/auth as needed), edit `filter{}` for your payload shape, and
   leave `output { http { url => "http://localhost:8080/loki/api/v1/raw" } }`
   untouched.
3. Leave `deployment.yaml`'s Alloy container and `*-alloy-secrets` config
   untouched except for the `job` label.
4. Add a matching `.rules` file under `templates/loki-base/rules/common/`
   keyed on your new `job` label if you want detections.
5. Wire a `scripts/add_<new>.sh` modeled on `add_cloudtrail.sh` (Vault
   secret creation, placeholder substitution, and a `kustomization.yaml`
   patch).

**Pull, with transform (copy `gcp-collector-tpl`):**
1. `cp -r templates/gcp-collector-tpl templates/<new>-collector-tpl`
2. Do not add `service.yaml` or `httproute.yaml`. Nothing should route to
   this pod.
3. Swap the `google_pubsub` input for whatever plugin fetches from your
   source (SQS, a REST poller, etc.), and swap
   `gcp-logstash-key-external-secrets.yaml` for whatever credential that
   plugin needs (API key, IAM role, etc.), mounted the same way.
4. Keep the `http { port => 9091, type => "readiness" }` plus `drop{}`
   pattern so the pod stays probeable without leaking health checks into
   Loki.
5. Wire a `scripts/add_<new>.sh` modeled on `add_gcp.sh`.

**No transform stage needed (copy `generic-http-tpl`):**
Only do this if the source already speaks clean JSON over HTTP and you are
fine relying solely on the shared Ingress-level basic auth for access
control, with no server-side filtering. Otherwise start from the push
checklist above and keep a transform container.

## 5. Reference: Vault secret paths used by these templates

| Path pattern | Used by | Contents |
|---|---|---|
| `tenants/<tenant_id>/loki_tenant` | all collectors (Alloy output leg) | Loki basic-auth `username`/`password` |
| `tenants/<tenant_id>/aws/<intergation_id>/creds` | CloudTrail/CloudWatch (Logstash http input) | per-integration `username`/`password` |
| `tenants/<tenant_id>/gcp/<intergation_id>/info` | GCP (Logstash `google_pubsub` input) | `project`, `topic`, `subscription` |
| `tenants/<tenant_id>/gcp/<intergation_id>/key` | GCP (Logstash `google_pubsub` input) | base64 service-account JSON `key` |

All of these are created via `create_tenant_secret` in `scripts/common.sh`,
which writes to `siem/<env>/tenants/<tenant_id>/<name>` (KV v2), and are
consumed via `ExternalSecret` through the Vault `ClusterSecretStore` at
deploy time.
