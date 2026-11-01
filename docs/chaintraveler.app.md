# Runbook: bring chaintraveler.app up

[chaintraveler.app](https://chaintraveler.app) is a free, offline web app (repository `uncovertechtalent-git/chain-traveler`). Unlike machinebehavior.io it has no GitHub Pages past to cut over from, so the stack goes straight to CloudFront. Two things make it different from the other site:

- **Two publishers write to one bucket**, each with its own role (`live/bootstrap`): the app shell (everything except `data/`) from the `production` environment of the app repository, after approval; the timetable (`data/`) from the `main` branch, daily, without approval, because a scheduled job cannot wait for a reviewer. The shell role carries an explicit deny on `data/*`; the data role can touch `data/*` only and cannot invalidate.
- **One switch, `domain_ready`**, keeps the first apply clean whatever state the domain registration is in (step 8).

What the stack builds is in `live/chaintraveler.app/main.tf`; the cache and header rules are the `cache_rules` and `content_security_policy` there.

## The order, and why

Operator steps come before the merge. The CI plan and apply jobs read each stack's tfvars from the state bucket and fail when a stack has none, and `live/chaintraveler.app` sorts before `live/machinebehavior.io`, so an early merge would stop machinebehavior.io's applies until the tfvars exist.

| # | Who | What |
|---|---|---|
| 1 | owner | The app repository exists, public, with the `production` environment (required reviewer, branch `main` only). |
| 2 | operator | `chaintraveler.app.tfvars` on the operator host. |
| 3 | operator | The site entry in `bootstrap.tfvars`; bootstrap plan, apply. |
| 4 | operator | `scripts/tf.sh chaintraveler.app push-vars`. |
| 5 | owner | Merge this pull request; approve the Apply job (or the operator applies by hand). |
| 6 | operator | The distribution id into `bootstrap.tfvars`; bootstrap plan, apply; `scripts/role-boundaries-site.sh`. |
| 7 | owner | Secrets and the `S3_DEPLOY` variable in the app repository; first deploy and first timetable run; check on the CloudFront name. |
| 8 | operator | `domain_ready = true`; plan, apply; checks on the real name. |

## 1. The repository

```bash
gh api repos/uncovertechtalent-git/chain-traveler --jq '.id'     # repository_id for step 3
```

The owner id is the organisation's: `257729892` (`live/bootstrap/variables.tf`). The role trust uses GitHub's immutable subject (`repo:owner@id/name@id`), so a renamed or re-created repository cannot assume the roles.

## 2. `~/.config/site-infra/chaintraveler.app.tfvars`

```hcl
aws_account_id   = "<12 digits>"
zone_id          = "<hosted zone id of chaintraveler.app>"     # aws route53 list-hosted-zones-by-name --dns-name chaintraveler.app
site_bucket_name = "<globally unique bucket name>"
log_bucket_name  = "<the access log bucket of the shared stack>"
```

`domain_ready` stays at its default `false`.

## 3. Bootstrap: the bucket, the zone and the two roles

Add the site to the `sites` map in `bootstrap.tfvars`. No `distribution_id` yet:

```hcl
  "chaintraveler.app" = {
    repository          = "uncovertechtalent-git/chain-traveler"
    owner_id            = 257729892
    repository_id       = <from step 1>
    bucket_name         = "<same as site_bucket_name>"
    zone_id             = "<same as zone_id>"
    deploy_environment  = "production"
    deny_write_prefixes = ["data/"]
    data_prefix         = "data/"
  }
```

```bash
scripts/tf.sh bootstrap plan      # expect 2 to add, 2 to change, 0 to destroy: one new role chaintraveler-app-github-data with its policy; the policies of the plan role (gains the bucket, it reads it) and of the apply role (gains the bucket and the zone) updated in place
scripts/tf.sh bootstrap apply
scripts/tf.sh bootstrap push-vars # CI plans bootstrap with the copy in the state bucket; without this its plan wants to destroy what was just applied
scripts/tf.sh bootstrap output    # data_role_arns: the value of AWS_DATA_ROLE_ARN in step 7
```

The apply role writes only the buckets and zones listed in `sites`, so this step has to come before the site stack is applied.

## 4. Push the stack's variables

```bash
scripts/tf.sh chaintraveler.app push-vars
```

From here the pull request's Plan job shows every stack, including the unchanged machinebehavior.io: its plan must show **no changes** apart from the state move of `aws_acm_certificate_validation.this` to `this[0]` (a `moved` block; the validation resource is only a wait and owns nothing in AWS).

## 5. Merge and apply

Expected plan for the new stack, 19 to create and nothing else: the S3 bucket with its ownership controls, public access block, versioning, encryption, lifecycle rule and bucket policy (7), the CloudFront origin access control, the viewer-request function, three response headers policies (default, `latest`, `builds`), the ACM certificate in us-east-1 and its two validation records (apex, www), the distribution, and the log delivery source, destination and delivery (3). **No** `aws_acm_certificate_validation`, **no** alias record, **no** `aliases` on the distribution: `domain_ready` is false.

Approve the Apply job in the `production` environment. The distribution takes about five minutes.

```bash
scripts/tf.sh chaintraveler.app output     # distribution_id, distribution_domain_name
```

## 6. The shell deploy role

Add `distribution_id = "<output>"` to the site entry in `bootstrap.tfvars`.

```bash
scripts/tf.sh bootstrap plan      # expect: one new role chaintraveler-app-github-deploy with its policy
scripts/tf.sh bootstrap apply
scripts/tf.sh bootstrap push-vars # again: the distribution id is part of the file CI plans with
scripts/tf.sh bootstrap output    # deploy_role_arns: the value of AWS_DEPLOY_ROLE_ARN in step 7
scripts/role-boundaries-site.sh chaintraveler.app <bucket> <distribution id>    # every line must say ok
```

## 7. The app repository

| Where | Name | Value |
|---|---|---|
| Environment `production`, secret | `AWS_DEPLOY_ROLE_ARN` | `deploy_role_arns` |
| Repository secret | `AWS_DATA_ROLE_ARN` | `data_role_arns` |
| Repository secret | `SITE_BUCKET` | `site_bucket_name` |
| Repository secret | `CLOUDFRONT_DISTRIBUTION_ID` | `distribution_id` |
| Repository variable | `S3_DEPLOY` | `on` |

None is a credential; they are secrets so that the log masks the account id.

Run the **Timetable** workflow by hand (it publishes `data/<date>/` and `data/latest.json`), then **Deploy** (approve in `production`). On the CloudFront name:

```bash
D=<distribution_domain_name>
curl -sI https://$D/ | grep -iE '^(HTTP|content-type|cache-control|content-security-policy|strict-transport)'
curl -sI https://$D/data/latest.json | grep -iE '^(HTTP|cache-control|x-cache)'            # no-cache, Miss from cloudfront
curl -s  https://$D/data/latest.json | python3 -m json.tool
curl -sI https://$D/data/<date>/timetable.bin.gz | grep -iE '^(HTTP|content-length|cache-control)'   # immutable, one year
```

Open `https://$D/` in a browser: the app loads the timetable once, then works offline.

## 8. The domain

Before the flip, two checks. The registration is done and the registry delegates to the zone:

```bash
aws route53domains get-operation-detail --region us-east-1 --operation-id <id> --query Status --output text      # SUCCESSFUL
aws route53 list-resource-record-sets --hosted-zone-id <zone> --query "ResourceRecordSets[?Type=='NS'].ResourceRecords[].Value" --output text | tr '\t' '\n' | sort > /tmp/zone-ns
dig +short NS chaintraveler.app @8.8.8.8 | sort | diff - /tmp/zone-ns && echo "delegation is live"
```

If the registration is still `IN_PROGRESS`, or the diff shows a difference, stay at `domain_ready = false`: the app works on the CloudFront name and nothing else is affected. When both checks pass, set `domain_ready = true` in `chaintraveler.app.tfvars`, plan and apply with `scripts/tf.sh`, and only after the apply run `scripts/tf.sh chaintraveler.app push-vars`. Pushing first would let a CI Apply that is waiting, or starts in between, apply the flip without a reviewed plan: CI reads the stack's variables from the state bucket when the job runs. The same goes for the rollback below.

Expected plan: 1 to change, 4 to create: the distribution updated in place (aliases `chaintraveler.app` and `www.chaintraveler.app`, the validated ACM certificate instead of the CloudFront one), `aws_acm_certificate_validation.this[0]` created, and three records (apex A and AAAA aliases, www CNAME). The validation resource waits for ACM, usually a few minutes; if the delegation is not live it fails after its timeout and leaves everything it created, and the next apply continues.

```bash
curl -sI https://chaintraveler.app/ | grep -iE '^(HTTP|strict-transport|content-security-policy)'
curl -sI https://www.chaintraveler.app/ | grep -iE '^(HTTP|location)'                       # 301 https://chaintraveler.app/
curl -s  https://chaintraveler.app/data/latest.json | python3 -m json.tool
echo | openssl s_client -connect chaintraveler.app:443 -servername chaintraveler.app 2>/dev/null | openssl x509 -noout -issuer -dates
```

A resolver that looked the name up before the records existed may keep the miss for the zone's negative TTL. If `dig +short A chaintraveler.app @8.8.8.8` answers and yours does not, the stack is fine: test with `curl --resolve chaintraveler.app:443:<address from dig> https://chaintraveler.app/` until the cache expires.

## 9. The manifest signing key (optional, after step 8)

The timetable pointer `data/latest.json` can carry a signature so that the app accepts a timetable only from the one
publisher that can use a private key that never leaves KMS (chain-traveler README, "Signed manifest"). What the key is
and what it protects:

- an asymmetric ECDSA P-256 KMS key, alias `chaintraveler-app-manifest-signing`, made in the **bootstrap** stack (so the
  operator applies it, like every IAM change);
- only the data role may sign, verify and read the public key (`kms:Sign`, `kms:Verify`, `kms:GetPublicKey` on that one key);
  the shell role, the CI roles and this repository's apply role cannot sign; the plan role can read the key's settings and nothing more;
- it protects against a leaked data role's S3 rights, a bucket-policy mistake and a CDN-level compromise. It does not
  protect against a compromised `main` branch of the app repository, whose workflow the data role trusts.

In the order that keeps every step harmless on its own:

1. In the operator's `bootstrap.tfvars` set `sign_manifest = true` on the chaintraveler.app site entry. Plan, show it,
   apply, push-vars (after the apply, as in step 3). The plan adds one key, one alias, one statement on the data role.
   Run `scripts/role-boundaries-site.sh chaintraveler.app <bucket> <distribution id> "" <key arn>` (the key ARN is the output
   `manifest_signing_key_arns`): every line `ok`. Those lines prove the data role's IAM scope; the key policy's deny of
   `kms:Sign` to every other principal is not read by the policy simulator, and is held by the module's `terraform test`.
2. Set the repository secret `SIGNING_KEY_ARN` of the app repository to the key ARN and run the Timetable workflow by hand:
   the pointer now has `kid` and `sig`. An app that holds no public key ignores both fields, so nothing changes on a device
   yet. Check: `curl -s https://chaintraveler.app/data/latest.json | python3 -m json.tool` shows both fields.
3. Read the public key and its id, then put both into the app (`app/keys.js`) and release the shell:
   ```sh
   pub=$(aws kms get-public-key --key-id alias/chaintraveler-app-manifest-signing --query PublicKey --output text)
   python3 build/manifest.py kid-of "$pub"
   ```
   From this release on, the app refuses a manifest that is not signed by a listed key, and the published manifest already
   is. The other order (the key in the app before the pointer is signed) opens a window in which a device that updates the
   shell finds an unsigned manifest, keeps its old timetable, and says `signature` in the data-age line.
4. Check: open the app online: "Updated just now." or "Up to date.", no `signature` in the data-age line.

To rotate, make a second key by hand under another alias, list both public keys in `app/keys.js`, release, switch
`SIGNING_KEY_ARN`, and remove the old key a release later. To switch signing off, remove `SIGNING_KEY_ARN` (the manifest
is unsigned again) and, before that reaches devices, remove the keys from `app/keys.js`: an app that holds a key refuses
an unsigned manifest.

## Rollback

| What | How |
|---|---|
| The domain attachment | `domain_ready = false` in the local tfvars, plan, apply, then push-vars: the aliases and the three records go, the app stays reachable on the CloudFront name. |
| A bad timetable | Run the **Timetable** workflow by hand with `rollback_to` set to a kept build (`YYYY-MM-DD`); the app follows the pointer at its next online launch. The last three builds are kept. |
| A bad shell | Revert the commit in the app repository and approve the deploy; the previous files are also kept as object versions for 30 days. |
| The infrastructure | Revert this pull request's commit; the bucket is not empty, so destroying it needs `force_destroy` by hand, on purpose. |

## What to watch

CloudFront delivers access logs to the shared log bucket under `cloudfront/chaintraveler.app` (no IP address, no query string, no cookie); the "Site traffic" dashboard picks the prefix up like the other site's. The one usage figure the product plan wants is downloads of `data/latest.json` per day.
