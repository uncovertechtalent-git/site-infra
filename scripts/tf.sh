#!/usr/bin/env bash
# Plan and apply one stack on the operator host: the bootstrap stack always
# (it holds IAM and the state bucket), the others only as break-glass, when
# the CI workflow cannot. Settings that must not enter this public repository
# stay in ${SITE_INFRA_CONFIG:-~/.config/site-infra}: backend.hcl (state
# bucket) and <stack>.tfvars (account id, zone ids, bucket names).
#
#   scripts/tf.sh <stack> plan [args]  saved plan + counts-only summary for the pull request;
#                                      args go to terraform plan (-replace=..., -target=...)
#   scripts/tf.sh <stack> apply        applies the saved plan, nothing else
#   scripts/tf.sh <stack> output       stack outputs (stay on the host)
#   scripts/tf.sh <stack> push-vars    copy <stack>.tfvars to the state bucket, where CI reads it
#
# plan refuses a dirty working tree, so every plan maps to a commit.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <stack> plan [terraform plan args] | apply | output | push-vars" >&2
  exit 2
fi
stack="$1" action="$2"
shift 2
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/live/$stack"
conf="${SITE_INFRA_CONFIG:-$HOME/.config/site-infra}"
plans="${SITE_INFRA_PLANS:-$HOME/.cache/site-infra}"
[ -d "$dir" ] || { echo "no stack live/$stack" >&2; exit 2; }

tf() { terraform -chdir="$dir" "$@"; }
init() { tf init -input=false -lockfile=readonly -backend-config="$conf/backend.hcl" >/dev/null; }

case "$action" in
  plan)
    if [ -n "$(git -C "$root" status --porcelain)" ] && [ "${ALLOW_DIRTY:-}" != 1 ]; then
      echo "working tree has changes; commit first (ALLOW_DIRTY=1 to override)" >&2
      exit 1
    fi
    init
    mkdir -p "$plans"
    tf plan -input=false -var-file="$conf/$stack.tfvars" -out="$plans/$stack.tfplan" "$@"
    tf show -json "$plans/$stack.tfplan" \
      | python3 "$root/scripts/plan_summary.py" --stack "$stack" --commit "$(git -C "$root" rev-parse --short HEAD)" \
      > "$plans/$stack.summary.md"
    echo
    cat "$plans/$stack.summary.md"
    ;;
  apply)
    [ -f "$plans/$stack.tfplan" ] || { echo "no saved plan; run plan first" >&2; exit 1; }
    init
    tf apply -input=false "$plans/$stack.tfplan"
    rm -f "$plans/$stack.tfplan"
    ;;
  output)
    init
    tf output
    ;;
  push-vars)
    bucket="$(sed -n 's/^bucket *= *"\(.*\)"$/\1/p' "$conf/backend.hcl")"
    aws s3 cp --only-show-errors --sse AES256 "$conf/$stack.tfvars" "s3://$bucket/site-infra/tfvars/$stack.tfvars"
    echo "pushed $stack.tfvars"
    ;;
  *)
    echo "unknown action: $action" >&2
    exit 2
    ;;
esac
