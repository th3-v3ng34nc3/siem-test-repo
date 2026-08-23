# AWS Config → SIEM: end-to-end validation walkthrough

Real AWS Config → real S3 → real Lambda → tunnel → real k3s collector pod → local Loki.
This is the Level 2/3 validation described in `aws-config-siem-feature-support.html` (Section 6) and
`aws-config-onboarding-terraform-lambda.html` (Section 9), run against an **already-existing** AWS
Config setup instead of the from-scratch `full` Terraform variant.

**Result: passed, end to end, after fixing three real bugs found along the way (see Findings).**
No production tenant, Vault, or cluster was touched anywhere in this run.

## Environment used for this run

| Item | Value |
|---|---|
| Date | 2026-08-22 |
| AWS account | 956994857092 (`adityaraj@accuknox.com`) |
| AWS region | us-west-2 |
| Existing Config delivery bucket | `yubi-config-integration-test-bucket` |
| Existing Config key prefix | `AWSLogs/956994857092/Config/` |
| Config recorder | `default`, actively recording (IAM::User, IAM::Role, S3::Bucket) |
| Terraform variant used | `Integration_Guides/aws/aws-config/customer/` (bucket + recorder already existed) |
| k3s host | 192.168.34.128 (hostname `rajvanshi2`), user `aditya` |
| k3s version | v1.36.3+k3s1, Ubuntu 24.04.4 LTS, single control-plane node |
| Local machine | Windows 11, Docker Desktop, kubectl client, AWS CLI v2 — all pre-existing |
| Terraform binary | v1.15.9, downloaded to the session scratchpad (not installed system-wide) |
| Tunnel tool | `cloudflared` quick tunnel (no account/authtoken required) |
| Test tenant / integration id | `awsconfig-e2e` / `aws-config` → k3s namespace `tenant-awsconfig-e2e` (isolated from any real cluster) |
| Test Basic Auth creds | `awsconfige2e` / (random, generated for this run, not written into this doc) |

## Pre-flight checks performed (before touching anything real)

- `aws sts get-caller-identity` — confirmed account/user.
- `aws configservice describe-configuration-recorders` / `describe-delivery-channels` /
  `describe-configuration-recorder-status` (region us-west-2) — found the existing recorder + bucket,
  confirmed it's actively recording.
- `aws s3 ls s3://yubi-config-integration-test-bucket/ --recursive` — confirmed the bucket only contains
  `AWSLogs/956994857092/Config/...` objects, so no ambiguity about `config_key_prefix`.
- `aws s3api get-bucket-notification-configuration --bucket yubi-config-integration-test-bucket` —
  returned empty. **This mattered**: Terraform's `aws_s3_bucket_notification` resource replaces the
  bucket's entire notification config rather than adding to it, so if this bucket already had a
  CloudTrail Lambda trigger configured, applying this module would have silently deleted it. It didn't,
  so it was safe to apply as-is.
- Set up SSH key-based auth to the k3s host (dedicated keypair `~/.ssh/ak_siem_k3s_test`, generated for
  this test only, added to `~/.ssh/authorized_keys` on the VM) so commands could run non-interactively
  instead of relaying a password through chat each time.
- Verified kubeconfig at `/etc/rancher/k3s/k3s.yaml` was world-readable on the VM — no sudo needed.

---

## Step 1 — Stand up a local Loki + the real collector manifests on k3s

Deployed a minimal single-binary Loki (not part of the repo — test-only, matches the pattern the design
docs use for local validation) so there was somewhere real for the collector to write to:

```yaml
# loki-test-stack.yaml — namespace "loki", Deployment "loki" (grafana/loki:3.0.0,
# -config.file=/etc/loki/local-config.yaml, the image's built-in default config),
# Service "loki-gateway" port 80 -> 3100.
```

The Service is deliberately named `loki-gateway` in namespace `loki`, port 80 — this exactly matches the
hardcoded endpoint already baked into the real, unmodified
`templates/aws-config-collector-tpl/aws-external-secrets-cgf.yaml`
(`http://loki-gateway.loki.svc.cluster.local/loki/api/v1/push`), so **zero edits** were needed to the
real `config.alloy` content beyond the same `{{ .username }}`/`{{ .password }}` substitution
ExternalSecret would normally do.

Then, exactly per the design doc's Level 2 recipe:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl create namespace tenant-awsconfig-e2e

# stand in for the two ExternalSecrets — same keys, hand-created, no Vault/ESO involved
kubectl create secret generic aws-alloy-aws-config \
  --namespace tenant-awsconfig-e2e --from-file=config.alloy=./config.alloy
kubectl create secret generic aws-logstash-aws-config \
  --namespace tenant-awsconfig-e2e --from-file=pipeline.conf=./pipeline.conf

# render the real template's placeholders, same substitution add_*.sh would do
sed -e 's/<intergation_id>/aws-config/g' -e 's/<tenant_id>/awsconfig-e2e/g' \
  templates/aws-config-collector-tpl/deployment.yaml | kubectl apply -f -
sed -e 's/<intergation_id>/aws-config/g' -e 's/<tenant_id>/awsconfig-e2e/g' \
  templates/aws-config-collector-tpl/service.yaml | kubectl apply -f -
```

Result: `deployment "aws-aws-config" successfully rolled out`, pod `2/2 Running`
(`aws-aws-config-cd5f7d848-2btcv`). First rollout took a few minutes — pulling `grafana/alloy:v1.12.2`
(~154 MB) and the custom Logstash image on a cold VM took ~2.5 minutes combined, not a config issue.

## Step 2 — Sanity-check the pipeline on the VM before exposing it publicly

```bash
kubectl -n tenant-awsconfig-e2e port-forward svc/aws-aws-config 9090:9090 &

curl -X POST http://localhost:9090/ -H "Content-Type: application/x-ndjson" --data-binary '{"foo":"bar"}'
# -> 401 (no Basic Auth header — correctly rejected)

curl -X POST http://localhost:9090/ -H "Content-Type: application/x-ndjson" \
  -u "awsconfige2e:<test-password>" \
  --data-binary '{"resourceType":"AWS::S3::Bucket","resourceId":"sanity-check-bucket","configurationItemStatus":"OK","awsRegion":"us-west-2"}'
# -> 200

kubectl -n loki port-forward svc/loki-gateway 3100:80 &
curl -sG http://localhost:3100/loki/api/v1/query_range --data-urlencode 'query={job="awsconfig"}'
# -> record present, resourceType/resourceId/awsRegion/configurationItemStatus intact,
#    @version/headers/host/http/url fields stripped, exactly as the pipeline.conf filter specifies.
```

**Level 2 confirmed**: the real, unmodified collector manifests deploy correctly, Logstash's Basic Auth
actually enforces (401 without it), and end-to-end field handling into Loki is correct.

## Step 3 — Tunnel the pod out publicly (cloudflared)

Confirmed with the user before running this — it opens a temporary public HTTPS URL, protected only by
the collector's own Basic Auth (same caveat the design doc calls out for `ngrok`).

```bash
kubectl -n tenant-awsconfig-e2e port-forward svc/aws-aws-config 9090:9090 &
~/bin/cloudflared tunnel --url http://localhost:9090 &
# -> https://differential-exceptions-specs-harry.trycloudflare.com
```

Verified reachable from outside the VM (curl from the local Windows machine, simulating the path a real
AWS Lambda would take) before proceeding — `HTTP 200`.

## Step 4 — Terraform apply (customer variant) against the real AWS account

`terraform.tfvars` (this test run's values):

```
username    = "awsconfige2e"
password    = "<generated>"
target_url  = "https://differential-exceptions-specs-harry.trycloudflare.com/"
bucket_name = "yubi-config-integration-test-bucket"
bucket_arn  = "arn:aws:s3:::yubi-config-integration-test-bucket"
config_key_prefix = "AWSLogs/956994857092/Config/"
accuknox_suffix = "accuknox-awsconfig-e2e-test"
lambda_memory_mb = 512
lambda_timeout_seconds = 120
```

**Before applying, `terraform plan` caught a real bug** (see Findings #1) — the provider defaulted to
`us-west-1` while the real bucket is in `us-west-2`; fixed `provider.tf` before proceeding.

```bash
terraform init
terraform plan -var-file="terraform.tfvars" -out=e2e.tfplan   # reviewed: 8 to add, 0 to destroy
terraform apply "e2e.tfplan"                                   # confirmed with user first
```

Result: `Apply complete! Resources: 8 added, 0 changed, 0 destroyed.`
`lambda_function_name = "accuknox-awsconfig-e2e-test-log-forwarder-okkri"`

## Step 5 — First real trigger attempt: caught bug #2

```bash
aws configservice deliver-config-snapshot --delivery-channel-name default --region us-west-2
```

The snapshot **did** land in S3 (`956994857092_Config_us-west-2_ConfigSnapshot_..._b511d9e1....json.gz`,
200 KB), confirming the S3 side works — but the Lambda crashed on every invocation:

```
[ERROR] ValueError: invalid literal for int() with base 10: ''
  File "/var/task/lambda.py", line 20, in get_env_config
    "chunk_size": int(os.environ.get("CHUNK_SIZE_LIMIT", 3 * 1024 * 1024)),
```

Root cause and fix: see Findings #2. Fixed `lambda.py` in both `customer/` and `full/` (byte-identical
files, same bug in both). Redeploying the fix required `-replace` on the Lambda resource, because of
Findings #3 (no `source_code_hash` means a plain `terraform apply` reports "No changes" even when the
code changed) — which in turn wiped the Lambda's S3 invoke permission (destroy+recreate drops the
resource-based policy), requiring a second `-replace` on `aws_lambda_permission.s3_trigger_permission`.
Both fixes were confirmed with the user before applying (each real-AWS mutation was).

## Step 6 — Second real trigger: full success

```bash
aws configservice deliver-config-snapshot --delivery-channel-name default --region us-west-2
```

(Note: `DeliverConfigSnapshot` throttled on rapid repeat calls — `ThrottlingException`, needed ~3-4
minutes between calls. Not an issue in normal operation, since real Config deliveries aren't manually
forced back-to-back like this.)

Lambda logs (`aws logs tail`), full run:

```
[INFO] Loaded 2758 configurationItems from AWSLogs/956994857092/Config/us-west-2/2026/8/22/ConfigSnapshot/...e72c67b7....json.gz
[INFO] Successfully posted 859627 bytes. Status: 200
[INFO] Successfully posted 665594 bytes. Status: 200
[INFO] Successfully posted 1532592 bytes. Status: 200
```

(Also logged, harmlessly: an `ERROR` trying to parse `AWSLogs/956994857092/Config/ConfigWritabilityCheckFile`
— AWS Config's own 0-byte bucket-writability probe file, not a real Config payload. See Findings #4.)

Confirmed in Loki (via `kubectl port-forward` to `loki-gateway`, queried from the VM):

```
query={job="awsconfig"}  ->  2760 total log lines
(2758 real configurationItems + 2 earlier sanity-check lines from Step 2)
```

Sample landed record — resource fields intact, `@version`/`headers`/`host`/`http`/`url` stripped, exactly
as `pipeline.conf`'s filter specifies:

```json
{"resourceName":"default:aurora-postgresql-13","@timestamp":"2026-08-22T17:17:50.656Z",
 "relationships":[],"type":"awsconfig","awsRegion":"us-west-2",
 "resourceType":"AWS::RDS::OptionGroup", ...}
```

**This is the full chain proven real**: AWS Config's real file format, a real S3 event trigger, real IAM
permissions, a real HTTPS POST with Basic Auth crossing the open internet, and the receiving side's own
auth check and field-stripping — landing correctly in Loki.

## Step 7 — Teardown

Completed, confirmed with the user first.

```bash
# real AWS — all 8 resources destroyed cleanly
cd Integration_Guides/aws/aws-config/customer && terraform destroy -var-file="terraform.tfvars" -auto-approve
# -> Destroy complete! Resources: 8 destroyed.

# tunnel + port-forwards (on the VM)
pkill -f "[c]loudflared"
pkill -f "[k]ubectl.*port-forward"
# (note: a plain `pkill -f cloudflared`, without the [c] bracket trick, matches its own invoking
#  shell's command line too — since that line contains the literal word "cloudflared" — and kills the
#  SSH session along with the intended target. Harmless (the target still dies), just causes the SSH
#  command to report exit 255. Use `pkill -f "[c]loudflared"` to avoid the self-match.)

# k3s test resources (on the VM)
kubectl delete namespace tenant-awsconfig-e2e --wait=false
kubectl delete namespace loki --wait=false
# -> namespace "tenant-awsconfig-e2e" deleted / namespace "loki" deleted (both Terminating, background GC)
```

Local cleanup (this machine): removed `terraform.tfvars`, `e2e.tfplan`, `.terraform/`, `terraform.tfstate*`,
`lambda_payload.zip` from `Integration_Guides/aws/aws-config/customer/`, and the local test-credentials
scratch file. `git status --short` confirms no secrets left tracked or untracked.

**Final state**: no real AWS resources remain from this test, no public tunnel, no k3s test namespaces
(fully terminated shortly after deletion), no local files containing test credentials.

---

## Findings — real bugs/gaps found by this run (none of these were catchable by the earlier
offline/syntax-only validation described in `AWS_CONFIG_MEMORY.md`)

1. **`provider.tf` hardcoded `region = "us-west-1"`.** The README already warned "update `provider.tf` if
   your resources are in a different region," but this was easy to miss, and a wrong region isn't just an
   inconvenience here — S3 bucket notifications can only target a Lambda in the *same* region as the
   bucket, so a mismatched region silently breaks the trigger. **Fixed after this test** (not just
   worked around): `region` is now a required variable (no default, in both `customer/variables.tf` and
   `full/variables.tf`) wired into `provider.tf` as `region = var.region`, so it must be set explicitly
   rather than silently assumed. `terraform.tfvars.example` and `README.md` updated to match. Also
   confirmed present, identically, in the sibling CloudTrail and CloudWatch kits — **not fixed there**,
   out of scope for this pass (AWS-Config-only, per explicit instruction).

2. **Lambda crashes on every invocation with the documented default `tfvars`.** `lambda.py`'s
   `get_env_config()` did `int(os.environ.get("CHUNK_SIZE_LIMIT", 3 * 1024 * 1024))` — but
   `main.tf`'s `environment { variables = { CHUNK_SIZE_LIMIT = var.chunk_size ... } }` always sets the
   env var, even to `var.chunk_size`'s default of `""`. So `os.environ.get()` returns `""` (present, not
   absent) and `int("")` raises. Every deployment following the documented example `tfvars` (which
   explicitly recommends leaving `chunk_size`/`line_limit` as `""`) would hit this on 100% of
   invocations. **This is exclusive to the AWS Config kit** — the sibling CloudTrail kit never wires
   `chunk_size`/`line_limit` into Terraform at all, so it never sets those env vars and never hits this;
   the bug was introduced specifically when AWS Config's kit added these (correctly-motivated, per
   `AWS_CONFIG_MEMORY.md`) size variables. **Fixed** in this run: changed to
   `int(os.environ.get("CHUNK_SIZE_LIMIT") or 3 * 1024 * 1024)` (same pattern for `line_limit`), in both
   `customer/lambda.py` and `full/lambda.py`.

3. **`aws_lambda_function.config_forwarder` didn't set `source_code_hash`.** Without it, Terraform has
   no way to detect that `lambda.py`'s contents changed — a plain `terraform apply` reports "No changes"
   even after editing the Lambda source, so the fix in #2 would never have shipped to AWS without forcing
   it via `-replace`. **Fixed after this test**: added
   `source_code_hash = data.archive_file.lambda_zip.output_base64sha256` to the resource in both
   `customer/main.tf` and `full/main.tf` — the standard Terraform AWS provider pattern for this exact
   problem, so a normal `terraform apply` after editing `lambda.py` now updates the function in place
   (`UpdateFunctionCode`) instead of requiring `-replace` and instead of silently no-op'ing. Also
   confirmed present, identically, in the sibling CloudTrail kit — **not fixed there**, out of scope for
   this pass. Note: working around this via `-replace` (as this run had to, before the fix existed)
   destroys and recreates the function, which also wipes any resource-based policy — see #5.

4. **Minor: the Lambda errored (harmlessly) on `ConfigWritabilityCheckFile`.** AWS Config periodically
   writes a 0-byte `AWSLogs/<account>/Config/ConfigWritabilityCheckFile` to the bucket to verify write
   access; it matches the S3 trigger's prefix filter, so the Lambda fired on it too, tried to gzip-decode
   0 bytes, and logged `Error processing ...ConfigWritabilityCheckFile: Expecting value: line 1 column 1
   (char 0)`. Non-fatal (caught, logged, execution continued) but would recur on every real deployment and
   add log noise. **Fixed after this test**: both `lambda.py` files now explicitly skip any key ending in
   `ConfigWritabilityCheckFile` with an `[INFO]`-level "skipping" message instead of hitting the generic
   `except`/`[ERROR]` path.

5. **(Follow-on from #3, not independent)** Recreating the Lambda function via `-replace` removed its
   resource-based policy (the grant that lets `s3.amazonaws.com` invoke it) — confirmed via
   `aws lambda get-policy` returning `ResourceNotFoundException` after the replace, even though
   `aws_lambda_permission.s3_trigger_permission` still showed as present, unchanged, in Terraform state
   (Terraform doesn't proactively detect this drift). S3 was then silently unable to invoke the Lambda —
   no error surfaced anywhere obvious; the only symptom was "no new CloudWatch log stream ever appears."
   Required a second `terraform apply -replace=aws_lambda_permission.s3_trigger_permission` to fix.
   This wouldn't happen in normal use once #3 is fixed (in-place code updates don't touch the resource
   policy) — flagging it here because it's a sharp edge for anyone else who reaches for `-replace` as a
   workaround for #3 in the meantime.

## What's left

- **Teardown is complete** (Step 7) — nothing live remains from this test run, in AWS or on the k3s VM.
- **All 4 findings from the live test are now fixed at the source**, in both `customer/` and `full/`:
  - #2 (Lambda crash on empty `CHUNK_SIZE_LIMIT`/`LINE_LIMIT`) — fixed during the test itself.
  - #1 (hardcoded region) — `region` is now a required Terraform variable, wired into `provider.tf`;
    `terraform.tfvars.example` and `README.md` (customer variant) updated to match.
  - #3 (missing `source_code_hash`) — added to `aws_lambda_function.config_forwarder` in both variants'
    `main.tf`, so ordinary `terraform apply` now redeploys code changes without needing `-replace`.
  - #4 (`ConfigWritabilityCheckFile` log noise) — both `lambda.py` files now skip it explicitly.
  - Verified: `terraform validate` passes for both variants, and both `lambda.py` files pass
    `python3 -m py_compile` (run on the k3s VM, since no local Python was available on this machine).
- **All of this is only on disk, untracked in git** (same status as the rest of `Integration_Guides/`
  per the original repo state) — not committed.
- **Deliberately not fixed**, per explicit scope decision: the identical hardcoded-region and
  missing-`source_code_hash` patterns also exist in the sibling `cloudtrail-single-account` (both
  variants) and `cloudwatch`/`cloudwatch-customer` kits. Confirmed present via a quick grep, not touched —
  out of scope for this AWS-Config-only pass.
