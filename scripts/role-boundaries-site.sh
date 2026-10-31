#!/usr/bin/env bash
# Check what the two publisher roles of a site with a shell and a data publisher may and may not do, with the
# IAM policy simulator (iam:SimulatePrincipalPolicy, operator credentials). Same idea as role-boundaries.sh, for
# the roles that module "data_role" and the deploy role with deny_write_prefixes create. Run it after the
# bootstrap apply that creates them. The script exits 1 on the first surprise.
#
# Usage: scripts/role-boundaries-site.sh <site key, e.g. chaintraveler.app> <bucket> <distribution id> [bootstrap.tfvars]
# The bucket and the distribution id are private (they come from the stack's tfvars and outputs); they are not printed.
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <site key> <bucket> <distribution id> [path to bootstrap.tfvars]" >&2
  exit 2
fi
site="$1" bucket="$2" distribution="$3"
vars="${4:-${SITE_INFRA_CONFIG:-$HOME/.config/site-infra}/bootstrap.tfvars}"
account="$(sed -n 's/^ *aws_account_id *= *"\(.*\)"/\1/p' "$vars" | head -n 1)"
[ -n "$account" ] || { echo "no aws_account_id in $vars" >&2; exit 2; }

shell_role="${site//./-}-github-deploy"
data_role="${site//./-}-github-data"
failed=0

expect() { # want role action resource label
  got=$(aws iam simulate-principal-policy --policy-source-arn "arn:aws:iam::$account:role/$2" \
    --action-names "$3" --resource-arns "$4" --query "EvaluationResults[0].EvalDecision" --output text)
  case "$got" in allowed) got=allow ;; *) got=deny ;; esac
  mark=ok
  [ "$got" = "$1" ] || { mark=SURPRISE; failed=1; }
  printf '%-8s %-34s %-6s %-30s %s\n' "$mark" "$2" "$got" "$3" "$5"
}

b="arn:aws:s3:::$bucket"
d="arn:aws:cloudfront::$account:distribution/$distribution"

expect allow "$shell_role" s3:PutObject               "$b/index.html"               "the shell role writes the shell"
expect allow "$shell_role" s3:DeleteObject            "$b/old-page.html"            "the shell role removes stale shell files"
expect deny  "$shell_role" s3:PutObject               "$b/data/latest.json"         "the shell role never writes the pointer"
expect deny  "$shell_role" s3:PutObject               "$b/data/2026-11-01/meta.json" "the shell role never writes a build"
expect deny  "$shell_role" s3:DeleteObject            "$b/data/2026-11-01/meta.json" "the shell role never deletes a build"
expect deny  "$shell_role" s3:GetObject               "$b/data/latest.json"         "the shell role reads nothing"
expect allow "$shell_role" cloudfront:CreateInvalidation "$d"                       "the shell role invalidates its distribution"
expect deny  "$shell_role" s3:PutBucketPolicy         "$b"                          "the shell role changes no bucket setting"

expect allow "$data_role"  s3:PutObject               "$b/data/latest.json"         "the data role writes the pointer"
expect allow "$data_role"  s3:PutObject               "$b/data/2026-11-01/timetable.bin.gz" "the data role publishes a build"
expect allow "$data_role"  s3:GetObject               "$b/data/2026-11-01/meta.json" "the data role reads a build back"
expect allow "$data_role"  s3:DeleteObject            "$b/data/2026-10-29/meta.json" "the data role prunes an old build"
expect deny  "$data_role"  s3:PutObject               "$b/index.html"               "the data role never writes the shell"
expect deny  "$data_role"  s3:PutObject               "$b/sw.js"                    "the data role never writes the service worker"
expect deny  "$data_role"  s3:DeleteObject            "$b/index.html"               "the data role never deletes the shell"
expect deny  "$data_role"  cloudfront:CreateInvalidation "$d"                       "the data role cannot invalidate"
expect deny  "$data_role"  s3:PutBucketPolicy         "$b"                          "the data role changes no bucket setting"
expect deny  "$data_role"  s3:PutObject               "arn:aws:s3:::other-bucket/data/latest.json" "the data role writes no other bucket"
exit "$failed"
