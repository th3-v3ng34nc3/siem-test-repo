# AWS Config integration — context handoff

This file is a portable snapshot of everything Claude built and validated for the AWS Config SIEM integration, meant to travel with this repo to a different machine. It is **not** part of the feature itself — it's a working note for whoever (or whichever Claude session) picks this up next.

**On the new machine:** start the session by asking Claude to read this file first (e.g. "read AWS_CONFIG_MEMORY.md before we continue"). That's enough to resume with full context — you don't need to re-explain any of the history below.

---

Building AWS Config support into the SIEM (`ak-prod-siem` repo). AWS Config only delivers to S3, no CloudWatch Logs option, so this needed a new push-based Lambda forwarder (customer's AWS account) plus a new SIEM-side collector (this repo) — built by mirroring the existing, working CloudTrail integration file-for-file, not designing from scratch.

**Why:** validating whether AccuKnox's SIEM can ingest AWS Config data, following the exact same architectural pattern already proven for CloudTrail/CloudWatch/Azure/GCP in this repo.

**Status as of 2026-08-22: implemented, syntax/logic-validated, not yet runtime-tested.** All files below exist on disk but were **untracked in git** on the machine this was built on (`git status --short` showed them as `??`). The tracked baseline was otherwise fully clean; nothing tracked was modified (one earlier attempt to render a file into the live `mgmt/` tenant tree was auto-blocked by the permission classifier as a production-directory edit — correctly, since `mgmt/` is live deployed state, not scaffolding).

## What exists, and what it mirrors

**`Integration_Guides/aws/aws-config/customer/`** — Terraform + Lambda that runs in a customer's (or a test) AWS account, S3-event-triggered, pushes to the SIEM over HTTPS with Basic Auth. File-for-file mirror of `Integration_Guides/aws/cloudtrail-single-account/customer/` (which already exists and works in this repo). Files: `main.tf`, `provider.tf`, `variables.tf`, `lambda.py`, `terraform.tfvars.example`, `README.md`.
- Only real logic difference from CloudTrail's Lambda: reads `data['configurationItems']` instead of `data['Records']` (AWS Config's file format).
- Two additions beyond a pure copy, both deliberate and documented in the README: `config_key_prefix` variable (scopes the S3 trigger when the bucket is shared with CloudTrail) and explicit `lambda_memory_mb`/`lambda_timeout_seconds` (512MB/120s — CloudTrail's Lambda leaves these at AWS's defaults of 128MB/3s, which is too tight for a full-account AWS Config snapshot).

**`Integration_Guides/aws/aws-config/full/`** — same Lambda, but also provisions AWS Config itself from scratch (`aws_config_configuration_recorder`, `aws_config_delivery_channel`, the S3 bucket + bucket policy, an IAM role for Config). Mirrors `cloudtrail-single-account/full/`. **Recommended variant for the first real-AWS test** — a fresh test/sandbox AWS account won't have AWS Config enabled yet, and `full` sets that up in one `terraform apply` alongside the Lambda.

**`templates/aws-config-collector-tpl/`** — the SIEM-side receiving pod (Logstash on :9090 doing per-integration Basic Auth + field cleanup, Alloy on :8080 forwarding to Loki). File-for-file mirror of `templates/aws-cloudtrail-collector-tpl/` (`deployment.yaml`, `service.yaml`, `httproute.yaml`, `kustomization.yaml` are byte-identical copies — they were already fully generic). The two files that differ: `aws-external-secrets-cgf.yaml` (Alloy's `job` label is `"awsconfig"` not `"cloudtrail"`) and `aws-logstash-config-external-secrets.yaml` (Logstash pipeline trimmed to only a readiness branch + an `awsconfig` branch — no GeoIP, since Config's `configurationItems` describe resource state, not API calls with a caller IP; the unrelated azure/gcp branches present in CloudTrail's copy-pasted pipeline file were deliberately left out).
- Vault paths this needs (both already-existing conventions, nothing new): `tenants/<tenant_id>/loki_tenant` (Alloy) and `tenants/<tenant_id>/aws/<intergation_id>/creds` (Logstash — **this must equal whatever `username`/`password` the customer's Lambda sends**).

## Explicitly NOT included (trimmed on purpose — do not re-add without being asked)

- **No Grafana dashboard.** A `templates/loki-base/grafana/dashboards/aws-config-overview.json` + an entry in `grafana-values.yaml` was built and then reverted — no other integration has a dedicated dashboard, only the shared default `loki-overview`. `grafana-values.yaml` was restored to its exact original tracked content.
- **No local test scaffolding committed to the repo.** A `test/aws-config-local/` Docker Compose rig (Loki + Grafana + Alloy + the real Logstash image, wired via `network_mode: "service:alloy"` to mirror pod networking) was built and then deleted — no other integration ships committed test tooling either (only the CloudTrail prototype scripts `test/lambda.py`/`test/lambda-local.py` exist, and those aren't a reusable rig). **The exact content of that removed rig still exists in full in the two HTML docs below** (docker-compose.yaml, pipeline.conf with `testuser`/`testpass`, config.alloy, grafana-datasource.yaml) — if local testing tooling is wanted again, pull it from there rather than re-inventing it.
- **No `scripts/add_awsconfig.sh`** onboarding script, **no detection/alert rules** for Config data — both intentionally deferred as separate, later scope in the design docs.

## The two design docs (untracked HTML files, repo root)

- `aws-config-onboarding-terraform-lambda.html` — the Terraform+Lambda kit doc. Section 9 has two testing levels: Level 1 = offline mocked-S3 test (no AWS needed), Level 2 = the real validation path — apply the `full` variant into a real test AWS account, stand up the SIEM-side pod locally (Docker/k3s), tunnel it out with `ngrok`, point `target_url` at the tunnel, force a snapshot with `aws configservice deliver-config-snapshot` instead of waiting for the schedule, confirm via both the Lambda's CloudWatch logs and the local Loki query.
- `aws-config-siem-feature-support.html` — the SIEM-side doc. Section 6 has three levels: Level 1 = Docker Compose (the removed rig, full content still in this doc), Level 2 = the same manifests applied to a **k3s** cluster (the user specifically wants k3s, not kind — Traefik being k3s's default ingress is irrelevant since the plan deliberately skips testing `httproute.yaml` locally and reaches the Service directly), Level 3 = tunnel that k3s pod out via `kubectl port-forward` + `ngrok` so a real AWS Lambda can reach it.
- Both docs were also published as artifacts on claude.ai earlier in the session — the user asked for local-only copies instead and said they'd remove the artifact copies themselves.

**If moving to a new machine: copy these two `.html` files along with the code**, they contain the full step-by-step commands (including the Docker Compose file content that's no longer a tracked repo file).

## What's been validated, and how (be precise about this — don't overclaim)

Ran for real, in a sandbox with **no Docker, no k3s/kind, no `terraform` binary, no `aws` CLI** available:
- Both `lambda.py` files (customer and full — identical): offline test mocking the one `boto3` S3 call, faking a gzipped AWS Config snapshot, posting to a local `http.server`, calling `handler()` with a synthetic S3 event. **Passes** — correct parsing, chunking, Basic Auth header.
- All 6 Terraform files (`main.tf`/`provider.tf`/`variables.tf` × 2 variants): parsed with `python-hcl2` (no `terraform` binary was available). Every `var.X` used in each `main.tf` cross-checked 1:1 against its `variables.tf` — no undeclared or unused variables in either variant.
- All 6 `templates/aws-config-collector-tpl/*.yaml` files: parsed with PyYAML, and re-validated after `sed`-rendering with real-looking placeholder values (mirroring what `scripts/add_*.sh` does) — zero placeholders left unsubstituted.
- The Logstash `pipeline.conf` and Alloy `config.alloy` extracted from the rendered ExternalSecret YAML (with `{{ .username }}`/`{{ .password }}` swapped for test literals, since there's no local Vault) — structurally sound, braces balanced.

**Never actually run: Logstash, Alloy, or Loki as real processes, or a real k3s/kind cluster, or `terraform apply`/`terraform plan`, or the `aws` CLI.** All of that requires Docker and/or k3s and/or real AWS credentials, none of which existed in the sandbox this was built in. This is exactly why the move to a machine with Docker + k3s + real AWS access matters — it's the first chance to actually run any of this.

## How to resume on the new machine

1. Confirm all four locations came across with the repo: `Integration_Guides/aws/aws-config/{customer,full}/`, `templates/aws-config-collector-tpl/`, and (recommended) the two `.html` docs.
2. The next real step is **Level 2/3 validation** as documented: stand up the SIEM-side pod locally (Docker Compose per Doc 2 Section 6 Level 1, or directly to k3s per Level 2 — recreate the Docker Compose file content from the HTML doc since it's not a tracked file), tunnel it with `ngrok`, then `terraform apply` the `full` variant against a real test AWS account pointed at that tunnel, and confirm data lands in a local Loki.
3. Don't re-add the dashboard or local test scaffolding as *committed repo files* unless asked again — regenerate them ad hoc (scratch files) for the test run itself, matching the stated preference: "only what already exists for other integrations, no new files" for anything that goes in the actual repo tree.
4. If real Docker/k3s/AWS testing surfaces anything that needs fixing (e.g. a Logstash config issue only a real Logstash process would catch), fix it in the same four locations — they're the source of truth, not leftover scratch copies.
5. Once this file has been read and acted on, it's safe to delete — it's a handoff note, not a permanent part of the repo.
