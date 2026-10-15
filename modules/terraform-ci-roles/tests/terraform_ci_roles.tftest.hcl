mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

variables {
  oidc_provider_arn    = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  github_repository    = "example/site-infra"
  state_bucket_name    = "example-tfstate"
  managed_bucket_names = ["example-logs", "example-site"]
  hosted_zone_ids      = ["Z0000000000000000000"]
}

run "plan_role_trusts_pull_requests_only" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringEquals == {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
      "token.actions.githubusercontent.com:sub" = "repo:example/site-infra:pull_request"
    }
    error_message = "The plan role accepts pull request tokens of this repository only."
  }
}

run "apply_role_trusts_the_environment_only" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.apply.assume_role_policy).Statement[0].Condition.StringEquals == {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
      "token.actions.githubusercontent.com:sub" = "repo:example/site-infra:environment:production"
    }
    error_message = "The apply role accepts tokens of jobs in the production environment only."
  }
}

run "plan_role_cannot_write" {
  command = plan

  assert {
    condition = length([
      for a in flatten([for s in jsondecode(aws_iam_role_policy.plan.policy).Statement : s.Action]) : a
      if length(regexall("^[a-z0-9]+:(Get|List|Describe)", a)) == 0
    ]) == 0
    error_message = "Every plan role action is a Get, List or Describe."
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_role_policy.plan.policy).Statement : s.Effect == "Allow"])
    error_message = "The plan role has nothing to deny: it only reads."
  }
}

run "apply_role_has_no_iam" {
  command = plan

  assert {
    condition = length([
      for a in flatten([for s in jsondecode(aws_iam_role_policy.apply.policy).Statement : s.Action if s.Effect == "Allow"]) : a
      if startswith(a, "iam:") || startswith(a, "sts:") || a == "*" || endswith(a, ":*")
    ]) == 0
    error_message = "The apply role gets no IAM or STS action and no service-wide wildcard."
  }
}

run "apply_role_cannot_touch_bootstrap_state_or_variables" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.apply.policy).Statement :
      s.Effect == "Deny"
      && toset(s.Action) == toset(["s3:PutObject", "s3:DeleteObject"])
      && toset(s.Resource) == toset(["arn:aws:s3:::example-tfstate/site-infra/bootstrap.tfstate*", "arn:aws:s3:::example-tfstate/site-infra/tfvars/*"])
    ])
    error_message = "Writes to the bootstrap state and the tfvars are denied."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.apply.policy).Statement :
      s.Effect == "Deny" && s.Resource == "arn:aws:s3:::example-tfstate" && contains(s.Action, "s3:PutBucket*")
    ])
    error_message = "Changes to the state bucket's own settings are denied."
  }
}

run "apply_role_writes_only_the_managed_buckets_and_zones" {
  command = plan

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.apply.policy).Statement : s.Resource if s.Sid == "ManagedBuckets"
    ]) == ["arn:aws:s3:::example-logs", "arn:aws:s3:::example-site"]
    error_message = "Bucket writes are limited to the listed buckets."
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.apply.policy).Statement : s.Resource if s.Sid == "RecordsInTheSiteZones"
    ]) == ["arn:aws:route53:::hostedzone/Z0000000000000000000"]
    error_message = "Record changes are limited to the listed zones."
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.apply.policy).Statement : s.Condition.StringEquals["aws:RequestedRegion"] if s.Sid == "CertificatesInUsEast1"
    ]) == "us-east-1"
    error_message = "Certificates only in us-east-1, the region CloudFront reads them from."
  }
}
