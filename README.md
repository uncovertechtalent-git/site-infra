# site-infra

Terraform for the static sites machinebehavior.io and tychat.io: a private S3 bucket per site behind CloudFront, certificates from ACM, DNS in Route 53, and access logs that never record an IP address. The sites moved here from GitHub Pages, which keeps no access logs, so there were no visit statistics at all.

The repository is public on purpose: every artifact of the work is here to audit. It shows an infrastructure-as-code pipeline in which GitHub stores no cloud credential. Each job exchanges its short-lived GitHub OIDC token for a role that can do that job and nothing else. What cannot be public (the account id, the state, the log data) stays in AWS and on the operator host, and the sites show counts only.

## How a change ships

1. **Pull request.** Two workflows run.
   - `ci.yml`, with no AWS access: `terraform fmt -check`, `terraform validate` on every stack, `terraform test` on every module with a mocked AWS provider, tflint with the AWS ruleset, shellcheck, a trivy configuration scan, and zizmor on the workflows.
   - `terraform.yml`, job "Plan": assumes the read-only plan role, plans every stack with `-lock=false`, and comments the counts on the pull request (`scripts/plan_summary.py`: actions per resource type, never a name, id or value). The full plan stays on the runner. Fork pull requests get no OIDC token, and no workflow uses `pull_request_target`.
2. **Review and merge.** The repository owner approves the pull request.
3. **Apply.** On the push to main, job "Apply" waits in the `production` environment until the owner approves it. Then it assumes the apply role and plans and applies the shared and site stacks.
4. **Bootstrap changes** (IAM, the state bucket) show in the pull request's plan. The operator applies them by hand (below).

### Roles

| Role | Trusted by | May |
|---|---|---|
| `site-infra-terraform-plan` | pull request jobs of this repository | read the state and the tfvars, read the managed resources and IAM metadata; write nothing |
| `site-infra-terraform-apply` | jobs in the `production` environment of this repository | write the managed buckets, CloudFront, certificates in us-east-1, records in the site zones, log delivery, and the shared and site state. No IAM action at all; no write to the bootstrap state, the tfvars or the state bucket's settings |
| `<site>-github-deploy` | the main branch of the site repository | list and write that site's bucket, invalidate that site's distribution |
| `site-infra-access-logs-<suffix>-reader` | the operator host's stats job | list and read the log bucket |

The state bucket's own policy backs the roles up, whatever IAM allows: only the apply role and the operator write or delete state objects, and only the operator writes the bootstrap state and the tfvars.

All IAM lives in the bootstrap stack. The apply role cannot create, change or attach a role or policy, so nothing that CI runs can widen its own access. `scripts/role-boundaries.sh` checks 16 of these limits with the IAM policy simulator after each bootstrap apply.

### Configuration that stays private

- Account id, zone ids and bucket names are in each stack's tfvars. The operator keeps them in `~/.config/site-infra/` and copies them into the state bucket (`scripts/tf.sh <stack> push-vars`), where the CI roles read them and the apply role cannot change them. CI masks their values and the account id in the log.
- The repository secrets `TF_STATE_BUCKET` and `AWS_PLAN_ROLE_ARN`, and the secret `AWS_APPLY_ROLE_ARN` of the `production` environment, hold the rest. None of them is a credential; they are secrets because the account id is in them and GitHub masks only secrets in a step's log header (a variable prints in clear before any script can mask it). The scripts mask them again.
- Every stack sets `allowed_account_ids`, so a run against the wrong account fails before it reads anything.

### Break-glass

The long-lived credentials of the operator host (an IAM user with administrator access) do two things only:

1. **Bootstrap**: the first run, and every later change to IAM or the state bucket. `scripts/tf.sh bootstrap plan`, read the summary, `scripts/tf.sh bootstrap apply`, then `scripts/role-boundaries.sh`.
2. **Repair**: when the workflow cannot run (GitHub down, a broken role, a stuck lock), `scripts/tf.sh <stack> plan` and `apply` for any stack, from a clean checkout of main. Every use gets a note in the pull request or issue that follows.

### Pins

| What | Pin | Bumped by |
|---|---|---|
| `actions/checkout` | full commit SHA | Dependabot, 7-day cooldown |
| zizmor | version and wheel hashes (`scripts/ci/zizmor/requirements.txt`) | Dependabot, 7-day cooldown |
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
  terraform-ci-roles/  OIDC plan role (pull requests) and apply role (production environment)
  cloudflare-access-app/  Cloudflare Access application, Allow policy by email, one-time PIN login
  log-reader-role/     read-only role of the stats job
live/
  bootstrap/           state bucket, OIDC provider, every IAM role (operator only)
  shared/              log bucket
  machinebehavior.io/  the site, with the cutover switches
  cloudflare-access/   Access in front of the tunnel hostnames (operator only)
scripts/
  tf.sh                plan and apply on the operator host (bootstrap, break-glass)
  role-boundaries.sh   IAM policy simulator checks of the roles
  plan_summary.py      counts-only plan summary
  deploy-site.sh       sync a built site to its bucket and invalidate
  parity.py            compare a host under test with the live site
  ci/terraform.sh      keyless plan and apply in GitHub Actions
  ci/install-tools.sh  pinned CI tools, sha256 checked
docs/
  adr/                 decision records
  cutover-machinebehavior.io.md
stats/
  cloudfront_to_loki.py  access logs -> Loki, without IP addresses or User-Agent strings
  site-traffic.*         systemd user timer that runs it every 5 minutes
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

Then `shared`, then each site, with `scripts/tf.sh`. A new site needs its bucket name and zone in the bootstrap tfvars first (the apply role writes only listed buckets and zones), and its distribution id after the first site apply (for its deploy role).

## Cutover from GitHub Pages

Each site stack has two switches. GitHub Pages keeps deploying the whole time, so the way back is one variable.

| Stage | `attach_canonical_hosts` | `dns_target` | Effect |
|---|---|---|---|
| 0 | `false` | `github_pages` | The test host (`next.`) serves the site from CloudFront. Apex and www unchanged. |
| 1 | `true` | `github_pages` | Apex and www attached to the distribution; on CloudFront www answers 301 to the apex. DNS unchanged, so this can be tested with `parity.py --connect-to <distribution domain>`. |
| 2 | `true` | `cloudfront` | Apex A/AAAA become aliases of the distribution. www follows. |

www is a CNAME to the apex in every stage, so only the apex records ever switch. It must not point into github.io (the GitHub Pages default): github.io publishes CAA records that allow three certificate authorities, Amazon not among them, and ACM refuses a certificate for www with `CAA_ERROR`. GitHub Pages serves www the same way through the apex addresses.

Step by step, with the checks: [docs/cutover-machinebehavior.io.md](docs/cutover-machinebehavior.io.md).

Rollback from stage 2: `dns_target = "github_pages"`. The apex records are the same Terraform resources in every stage (imported once from the GitHub Pages setup), so each switch is an in-place, atomic Route 53 change. Lower `dns_ttl` to 60 a day before stage 2.

## Access logs and privacy

CloudFront standard logging (v2) delivers gzipped JSON lines to the log bucket, one prefix per site. The recorded fields are listed in `modules/static-site/variables.tf` (`log_record_fields`). The viewer IP address, port, `X-Forwarded-For`, cookies and the query string are never recorded; a variable validation refuses them and a test checks the default. CloudFront reports the country itself (`c-country`), so no IP address is needed for the country count. Raw logs expire after 30 days.

`stats/cloudfront_to_loki.py` turns the logs into visit statistics. A systemd user timer on the operator host runs it every 5 minutes: it mirrors the log prefix with the read-only reader role, and pushes one Loki line per request to the stream `{job="site-traffic", site, agent}`. Each line keeps the path, status, page or asset, browser or bot (with the bot's name), country, referrer host and cache result. The User-Agent string and the full referrer URL stay in the raw logs only, so Loki never sees them. The Grafana dashboard "Site traffic" counts page views, top pages, countries, referrers, crawlers and status codes.

Install on the operator host:

```bash
cat >> ~/.aws/config <<'EOF'
[profile site-logs-reader]
role_arn = <log_reader_role_arn output of the bootstrap stack>
source_profile = default
EOF
printf 'LOG_BUCKET=<log bucket>\nAWS_PROFILE=site-logs-reader\nLOKI_URL=http://localhost:3100\n' > ~/.config/site-infra/site-traffic.env
mkdir -p ~/.config/systemd/user
ln -sf ~/code/site-infra/stats/site-traffic.service ~/code/site-infra/stats/site-traffic.timer ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now site-traffic.timer
```

## Cloudflare Access in front of the tunnel

A Cloudflare tunnel publishes services of the operator host under their own hostnames. Without Access, each of them is public the moment it starts. `live/cloudflare-access` puts one Access application in front of all of them: an Allow policy with one include rule per allowed email, and the one-time PIN login (Cloudflare mails a code to an allowed address; any other address gets no code). Hostnames, account id and emails are in the stack's local tfvars, so this repository does not list the services.

The stack is the operator's, like bootstrap. CI validates it and runs the module tests with a mocked provider, but holds no Cloudflare token, so it never plans or applies it. The operator runs `scripts/tf.sh cloudflare-access plan|apply` with the token in `CLOUDFLARE_API_TOKEN` for that one process. The token is an account API token for this one account with three permissions, each the narrowest group for the resources the stack manages: "Access: Apps and Policies Write" (application and policy), "Access: Identity Providers Write" (the one-time PIN), "Access: Organizations Write" (the team domain, only while `manage_organization` is true). No zone, DNS or tunnel permission: the stack touches none of them.

## Accepted findings

trivy findings that are accepted, each with its reason, are in `.trivyignore.yaml`: SSE-S3 instead of customer managed KMS keys, no S3 server access logging, no WAF in front of a static origin. A new finding fails CI until it is fixed or recorded there.

## Next: a self-hosted runner in the enterprise pattern

Planned, not built. Enterprises often run Terraform on their own runners, inside their network. The next step reproduces that pattern without weakening the current one: ephemeral just-in-time runners in their own VPC and private subnet, in a runner group of the organisation limited to this repository, reachable only by push-to-main, `workflow_dispatch` and `production` jobs. The reasoning and the threat model are in [ADR-0002](docs/adr/0002-self-hosted-runner-enterprise-pattern.md).
