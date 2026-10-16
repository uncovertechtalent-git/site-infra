# Runbook: cut machinebehavior.io over from GitHub Pages to CloudFront

Stage 0 is live: `next.machinebehavior.io` serves the site from CloudFront, and parity with GitHub Pages holds for every file of the build. This runbook takes the apex from stage 0 to stage 2 and back. Every step is a variable in `~/.config/site-infra/machinebehavior.io.tfvars` on the operator host, then `scripts/tf.sh machinebehavior.io plan`, a look at the summary, and `scripts/tf.sh machinebehavior.io apply`.

`<dist>` below is the distribution domain: `terraform -chdir=live/machinebehavior.io output -raw distribution_domain_name`.

## Before you start

1. The site repository deploys to S3 on every push to main (job "Deploy to S3 and CloudFront"), and its latest run is green. Without it, the bucket falls behind the site after the next merge.
2. Parity holds for the current build:
   ```bash
   scripts/parity.py --reference https://machinebehavior.io --candidate https://next.machinebehavior.io --connect-to <dist> --paths <file list of the build>
   ```
3. `www.machinebehavior.io` is a CNAME to `machinebehavior.io` (done 2026-10-15). The apex records are the only records that switch.
4. The rollback window is the life of GitHub's certificate for the apex: Let's Encrypt, valid until 2027-01-06. Once DNS points away, GitHub cannot renew it.

## Step 1, a day before: lower the TTL

`dns_ttl = 60`. Plan: 3 updates (`aws_route53_record`: apex A, apex AAAA, www CNAME). Apply. Wait at least 300 seconds (the old TTL) before step 3.

## Step 2: attach the apex and www to CloudFront (no DNS change)

`attach_canonical_hosts = true`. Plan: 2 updates (`aws_cloudfront_distribution` aliases, `aws_cloudfront_function` redirect list). Apply; the distribution takes about 5 minutes.

Check CloudFront as the apex before any visitor reaches it:

```bash
scripts/parity.py --reference https://machinebehavior.io --candidate https://machinebehavior.io --connect-to <dist> --paths <file list>
curl -sI --connect-to www.machinebehavior.io:443:<dist>:443 https://www.machinebehavior.io/man/   # 301 https://machinebehavior.io/man/
curl -sI --connect-to machinebehavior.io:443:<dist>:443 http://machinebehavior.io/                 # 301 to https
```

Go on only if parity reports 0 mismatches.

## Step 3: switch DNS

`dns_target = "cloudfront"`. Plan: 2 updates (apex A and AAAA become aliases of `<dist>`), nothing else. Apply. Route 53 applies both in one change batch.

Check:

```bash
dig +short A machinebehavior.io @ns-23.awsdns-02.com      # CloudFront addresses, not 185.199.x.153
dig +short AAAA machinebehavior.io @ns-23.awsdns-02.com
curl -sI https://machinebehavior.io/ | grep -iE '^(server|x-cache|strict-transport)'   # CloudFront, HSTS
curl -sI https://www.machinebehavior.io/ | grep -i '^location'                          # https://machinebehavior.io/
```

Then watch the Grafana dashboard "Site traffic" for an hour: requests for host `machinebehavior.io` appear, and the share of 4xx and 5xx stays at the stage 0 level.

## Rollback

`dns_target = "github_pages"`, plan (2 updates), apply. The apex A and AAAA records get the four GitHub Pages addresses back in one change, TTL 60, and www follows. GitHub Pages has kept deploying the whole time.

## After a week without rollback

- `dns_ttl = 300`.
- Stefan decides when GitHub Pages stops deploying. Then the docs that name GitHub Pages as the host (site architecture, the rollback runbook) change, and `CNAME` leaves the site repository.
- The test host can stay as a smoke-test target or go (`test_host = null`).

## tychat.io

The same steps with its own stack, after machinebehavior.io has run a week. Its www record is also a CNAME into github.io, so it gets the CAA fix first (www CNAME to `tychat.io`).
