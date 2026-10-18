#!/usr/bin/env bash
# Check what the CI and deploy roles may and may not do, with the IAM policy
# simulator (iam:SimulatePrincipalPolicy, operator credentials). Each line is
# an expectation; the script exits 1 on the first surprise. Run it after
# every bootstrap apply. Account id, zone and bucket names come from the
# bootstrap tfvars and are not printed.
#
# Usage: scripts/role-boundaries.sh [path to bootstrap.tfvars]
set -euo pipefail

vars="${1:-${SITE_INFRA_CONFIG:-$HOME/.config/site-infra}/bootstrap.tfvars}"
get() { sed -n "s/^ *$1 *= *\"\\(.*\\)\"/\\1/p" "$vars" | head -n 1; }
account="$(get aws_account_id)"
state="$(get state_bucket_name)"
logs="$(get log_bucket_name)"
site="$(get bucket_name)"
zone="$(get zone_id)"

plan="site-infra-terraform-plan"
apply="site-infra-terraform-apply"
deploy="machinebehavior-io-github-deploy"
fn="ask-mbio"
fnrole="ask-mbio-lambda"
lambda="arn:aws:lambda:eu-central-1:$account:function"
loggroup="arn:aws:logs:eu-central-1:$account:log-group:/aws/lambda"
failed=0

expect() { # want role action resource label [service the role is passed to]
  ctx=()
  [ -n "${6:-}" ] && ctx=(--context-entries "ContextKeyName=iam:PassedToService,ContextKeyValues=$6,ContextKeyType=string")
  got=$(aws iam simulate-principal-policy --policy-source-arn "arn:aws:iam::$account:role/$2" \
    --action-names "$3" --resource-arns "$4" ${ctx[@]+"${ctx[@]}"} --query "EvaluationResults[0].EvalDecision" --output text)
  case "$got" in allowed) got=allow ;; *) got=deny ;; esac
  mark=ok
  [ "$got" = "$1" ] || { mark=SURPRISE; failed=1; }
  printf '%-8s %-34s %-6s %-34s %s\n' "$mark" "$2" "$got" "$3" "$5"
}

expect allow "$plan"   s3:GetObject                     "arn:aws:s3:::$state/site-infra/shared.tfstate"     "plan reads a state file"
expect deny  "$plan"   s3:PutObject                     "arn:aws:s3:::$state/site-infra/shared.tfstate"     "plan writes nothing"
expect deny  "$plan"   route53:ChangeResourceRecordSets "arn:aws:route53:::hostedzone/$zone"                "plan changes no record"
expect allow "$apply"  s3:PutObject                     "arn:aws:s3:::$state/site-infra/shared.tfstate"     "apply writes a site or shared state"
expect deny  "$apply"  s3:PutObject                     "arn:aws:s3:::$state/site-infra/bootstrap.tfstate"  "apply never writes the bootstrap state"
expect deny  "$apply"  s3:PutObject                     "arn:aws:s3:::$state/site-infra/tfvars/shared.tfvars" "apply never writes the tfvars"
expect deny  "$apply"  s3:PutBucketPolicy               "arn:aws:s3:::$state"                               "apply never changes the state bucket"
expect allow "$apply"  s3:PutBucketPolicy               "arn:aws:s3:::$site"                                "apply manages the site bucket"
expect allow "$apply"  s3:PutBucketPolicy               "arn:aws:s3:::$logs"                                "apply manages the log bucket"
expect deny  "$apply"  iam:CreateRole                   "arn:aws:iam::$account:role/any"                    "apply has no IAM"
expect deny  "$apply"  iam:PutRolePolicy                "arn:aws:iam::$account:role/$apply"                 "apply cannot widen itself"
expect allow "$apply"  route53:ChangeResourceRecordSets "arn:aws:route53:::hostedzone/$zone"                "apply changes records of the site zone"
expect deny  "$apply"  route53:ChangeResourceRecordSets "arn:aws:route53:::hostedzone/ZOTHERZONE00000"     "apply leaves other zones alone"
expect allow "$deploy" s3:PutObject                     "arn:aws:s3:::$site/index.html"                     "deploy writes the site"
expect deny  "$deploy" s3:PutObject                     "arn:aws:s3:::$logs/x"                              "deploy writes no other bucket"
expect deny  "$deploy" s3:PutBucketPolicy               "arn:aws:s3:::$site"                                "deploy changes no bucket setting"
expect allow "$apply"  lambda:UpdateFunctionCode        "$lambda:$fn"                                       "apply deploys the MCP function"
expect deny  "$apply"  lambda:UpdateFunctionCode        "$lambda:other"                                     "apply leaves other functions alone"
expect allow "$apply"  iam:PassRole                     "arn:aws:iam::$account:role/$fnrole"                "apply passes the function role to Lambda" lambda.amazonaws.com
expect deny  "$apply"  iam:PassRole                     "arn:aws:iam::$account:role/$fnrole"                "apply passes it to no other service" ec2.amazonaws.com
expect deny  "$apply"  iam:PassRole                     "arn:aws:iam::$account:role/$apply"                 "apply passes no other role" lambda.amazonaws.com
expect deny  "$apply"  iam:PutRolePolicy                "arn:aws:iam::$account:role/$fnrole"                "apply cannot widen the function role"
expect allow "$fnrole" logs:PutLogEvents                "$loggroup/$fn:log-stream:x"                        "the function writes its own logs"
expect deny  "$fnrole" logs:PutLogEvents                "$loggroup/other:log-stream:x"                      "the function writes no other log group"
expect deny  "$fnrole" s3:GetObject                     "arn:aws:s3:::$state/site-infra/shared.tfstate"     "the function reads no state"
expect deny  "$fnrole" s3:GetObject                     "arn:aws:s3:::$site/index.html"                     "the function reads the site over HTTPS, not the bucket"
exit "$failed"
