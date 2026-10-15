# site-infra

Terraform for the static sites machinebehavior.io and tychat.io: a private S3 bucket per site behind CloudFront, certificates from ACM, DNS in Route 53, and access logs that never record an IP address. The sites moved here from GitHub Pages, which keeps no access logs, so there were no visit statistics at all.

The repository is public on purpose. It shows a complete infrastructure-as-code pipeline in which the CI system holds no cloud credentials.

## How a change ships

1. **Pull request.** CI (`.github/workflows/ci.yml`) runs `terraform fmt -check`, `terraform validate` on every stack, `terraform test` on every module with a mocked AWS provider, tflint with the AWS ruleset, a trivy configuration scan, and zizmor on the workflow itself. CI has no AWS credentials and cannot reach AWS.
2. **Plan.** The operator runs `scripts/tf.sh <stack> plan` on the one host that holds AWS credentials. The script refuses a dirty working tree, saves the plan, and writes a summary with counts only (`scripts/plan_summary.py`: actions per resource type, no names, ids or values). The summary goes into the pull request description.
3. **Review and merge.** The repository owner approves.
4. **Apply.** `scripts/tf.sh <stack> apply` applies the saved plan and nothing else.

### Credentials

- Long-lived AWS credentials exist on the operator host only. GitHub stores no AWS secret.
- Content deploys from a site repository use GitHub OIDC: the workflow exchanges its short-lived token for a role (`modules/github-deploy-role`) that accepts one repository and one branch, and may only sync one bucket and invalidate one distribution.
- The stats job reads the access logs through a read-only role on the log bucket (`modules/log-bucket`, `reader_principal_arns`).
- Every stack sets `allowed_account_ids`, so a plan against the wrong account fails before it reads anything.
- Account id, zone ids and bucket names live in local tfvars on the operator host (`~/.config/site-infra/<stack>.tfvars`), never in this repository.

### Pins

| What | Pin | Bumped by |
|---|---|---|
| `actions/checkout` | full commit SHA | Dependabot, 7-day cooldown |
| zizmor | version and wheel hashes (`.github/zizmor/requirements.txt`) | Dependabot, 7-day cooldown |
| AWS provider | exact version in each stack, hashes in `.terraform.lock.hcl` | Dependabot, 7-day cooldown |
| terraform, tflint, trivy | version and sha256 in `scripts/ci/install-tools.sh` | by hand, 14 days after a release |
| tflint AWS ruleset | version in `.tflint.hcl`, signature checked by `tflint --init` | by hand |

trivy runs with `--skip-check-update`, so its checks change only when its pin changes.

## Layout

```
modules/
  state-bucket/        state bucket: versioned, encrypted, private, TLS only
  log-bucket/          access log bucket, log delivery policy, read-only reader role
  static-site/         site bucket, OAC, CloudFront, ACM certificate, viewer-request
                       function, security headers, standard logging v2, Route 53 records
  github-deploy-role/  OIDC role for one repository's deploy job
live/
  bootstrap/           the state bucket (first run on local state, then migrated)
  shared/              log bucket and the GitHub OIDC provider
  machinebehavior.io/  the site, with the cutover switches
scripts/
  tf.sh                plan and apply on the operator host
  plan_summary.py      counts-only plan summary
  deploy-site.sh       sync a built site to its bucket and invalidate
  parity.py            compare a host under test with the live site
  ci/install-tools.sh  pinned CI tools, sha256 checked
```

State: one key per stack in the state bucket, locked with the S3 lock file (`use_lockfile = true`), no DynamoDB table.

## Bootstrap

The state bucket holds its own state. On the first run only:

```bash
cd live/bootstrap
printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
terraform init && terraform apply -var-file=$HOME/.config/site-infra/bootstrap.tfvars
rm backend_override.tf
terraform init -migrate-state -backend-config=$HOME/.config/site-infra/backend.hcl
```

Then `shared`, then each site, with `scripts/tf.sh`.

## Cutover from GitHub Pages

Each site stack has two switches. GitHub Pages keeps deploying the whole time, so the way back is one variable.

| Stage | `attach_canonical_hosts` | `dns_target` | Effect |
|---|---|---|---|
| 0 | `false` | `github_pages` | The test host (`next.`) serves the site from CloudFront. Apex and www unchanged. |
| 1 | `true` | `github_pages` | Apex and www attached to the distribution; on CloudFront www answers 301 to the apex. DNS unchanged, so this can be tested with `parity.py --connect-to <distribution domain>`. |
| 2 | `true` | `cloudfront` | Apex A/AAAA become aliases of the distribution. www follows. |

www is a CNAME to the apex in every stage, so only the apex records ever switch. It must not point into github.io (the GitHub Pages default): github.io publishes CAA records that allow three certificate authorities, Amazon not among them, and ACM refuses a certificate for www with `CAA_ERROR`. GitHub Pages serves www the same way through the apex addresses.

Rollback from stage 2: `dns_target = "github_pages"`. The apex records are the same Terraform resources in every stage (imported once from the GitHub Pages setup), so each switch is an in-place, atomic Route 53 change. Lower `dns_ttl` to 60 a day before stage 2.

## Access logs and privacy

CloudFront standard logging (v2) delivers gzipped JSON lines to the log bucket, one prefix per site. The recorded fields are listed in `modules/static-site/variables.tf` (`log_record_fields`). The viewer IP address, port, `X-Forwarded-For`, cookies and the query string are never recorded; a variable validation refuses them and a test checks the default. CloudFront reports the country itself (`c-country`), so no IP address is needed for the country count. Raw logs expire after 30 days.

## Accepted findings

trivy findings that are accepted, each with its reason, are in `.trivyignore.yaml`: SSE-S3 instead of customer managed KMS keys, no S3 server access logging, no WAF in front of a static origin. A new finding fails CI until it is fixed or recorded there.
