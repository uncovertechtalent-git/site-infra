#!/usr/bin/env bash
# Terraform in GitHub Actions, keyless. One step runs it from start to end,
# so the AWS session never leaves this process.
#
#   plan   pull requests: the read-only plan role, every stack, -lock=false
#   apply  main, in the production environment: the apply role, every stack
#          except bootstrap (IAM and the state bucket are the operator's)
#
# The job's OIDC token is exchanged for a one-hour session of the role in
# AWS_ROLE_ARN. Each stack's tfvars come from the state bucket, where the
# operator puts them (scripts/tf.sh <stack> push-vars); their private values,
# the account id and the role ARN are masked before anything runs.
# Plan and apply output goes to files in RUNNER_TEMP, never to the public
# log: the log and the job summary show counts per resource type
# (scripts/plan_summary.py), and on a failure the last lines of the error.
#
# Env: AWS_ROLE_ARN, TF_STATE_BUCKET, and the OIDC request variables that
# GitHub sets for jobs with id-token: write.
set -euo pipefail

mode="${1:?usage: terraform.sh plan|apply}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="${RUNNER_TEMP:?}/terraform"
summary="$work/summary.md"
mkdir -p "$work"
: > "$summary"

if [ -z "${AWS_ROLE_ARN:-}" ] || [ -z "${TF_STATE_BUCKET:-}" ]; then
  echo "::error::the role ARN or TF_STATE_BUCKET secret is not set for this job (README, \"Configuration that stays private\")"
  exit 1
fi
echo "::add-mask::$AWS_ROLE_ARN"
echo "::add-mask::$TF_STATE_BUCKET"

token=$(curl -fsS -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL:?}&audience=sts.amazonaws.com" | jq -r .value)
echo "::add-mask::$token"
creds=$(aws sts assume-role-with-web-identity --role-arn "$AWS_ROLE_ARN" \
  --role-session-name "site-infra-$mode-${GITHUB_RUN_ID:?}" --web-identity-token "$token" \
  --duration-seconds 3600 --query Credentials --output json)
AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<<"$creds")
AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$creds")
AWS_SESSION_TOKEN=$(jq -r .SessionToken <<<"$creds")
echo "::add-mask::$AWS_ACCESS_KEY_ID"
echo "::add-mask::$AWS_SECRET_ACCESS_KEY"
echo "::add-mask::$AWS_SESSION_TOKEN"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
unset creds token
echo "::add-mask::$(aws sts get-caller-identity --query Account --output text)"

# bootstrap first, shared second, then the sites.
stacks=(bootstrap shared)
for d in "$root"/live/*/; do
  s="$(basename "$d")"
  [ "$s" = bootstrap ] || [ "$s" = shared ] || stacks+=("$s")
done

fail() { # stack step log
  echo "::error::$1: terraform $2 failed; its error follows"
  # Only the error, never the plan above it.
  if grep -q '^Error:' "$3"; then sed -n '/^Error:/,$p' "$3" | head -n 40; else tail -n 10 "$3"; fi
  printf '\n**%s: terraform %s failed.** See the job log.\n' "$1" "$2" >> "$summary"
  cat "$summary" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  exit 1
}

commit="$(git -C "$root" rev-parse --short HEAD)"
for stack in "${stacks[@]}"; do
  if [ "$mode" = apply ] && [ "$stack" = bootstrap ]; then
    continue
  fi
  vars="$work/$stack.tfvars"
  aws s3 cp --only-show-errors "s3://$TF_STATE_BUCKET/site-infra/tfvars/$stack.tfvars" "$vars"
  # Private values carry a digit (account id, zone id, bucket suffix, ARN) or are
  # long upper-case ids; public ones (host names, repository names) stay readable.
  grep -oE '"[^"]{4,}"' "$vars" | tr -d '"' | grep -E '[0-9]|^[A-Z]{10,}$' | sort -u | sed 's/^/::add-mask::/' || true

  tf=(terraform -chdir="$root/live/$stack")
  "${tf[@]}" init -input=false -no-color -lockfile=readonly -backend-config="bucket=$TF_STATE_BUCKET" \
    > "$work/$stack.init.log" 2>&1 || fail "$stack" init "$work/$stack.init.log"

  lock=()
  [ "$mode" = plan ] && lock=(-lock=false)
  "${tf[@]}" plan -input=false -no-color "${lock[@]}" -var-file="$vars" -out="$work/$stack.tfplan" \
    > "$work/$stack.plan.log" 2>&1 || fail "$stack" plan "$work/$stack.plan.log"
  "${tf[@]}" show -json "$work/$stack.tfplan" \
    | python3 "$root/scripts/plan_summary.py" --stack "$stack" --commit "$commit" >> "$summary"
  printf '\n' >> "$summary"

  if [ "$mode" = apply ]; then
    "${tf[@]}" apply -input=false -no-color "$work/$stack.tfplan" \
      > "$work/$stack.apply.log" 2>&1 || fail "$stack" apply "$work/$stack.apply.log"
    printf 'Applied %s.\n\n' "$stack" >> "$summary"
  fi
done

if [ "$mode" = plan ]; then
  printf '%s\n' "The bootstrap stack holds IAM and the state bucket; the operator applies it (README, \"Break-glass\"). Merging applies the other stacks after approval in the production environment." >> "$summary"
fi
cat "$summary"
cat "$summary" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
