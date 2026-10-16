mock_provider "aws" {}

variables {
  role_name         = "example-org-github-deploy"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  github_repository = "example/example.org"
  bucket_arn        = "arn:aws:s3:::example-site"
  distribution_arn  = "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"
}

run "only_main_of_one_repository_assumes_the_role" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals == {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
      "token.actions.githubusercontent.com:sub" = "repo:example/example.org:ref:refs/heads/main"
    }
    error_message = "The trust policy pins audience, repository and ref exactly (StringEquals, no wildcard)."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "Web identity only."
  }
}

run "environment_replaces_the_ref" {
  command = plan

  variables {
    github_environment = "production"
  }

  assert {
    condition     = output.token_subject == "repo:example/example.org:environment:production"
    error_message = "With an environment the subject names the environment."
  }
}

run "permissions_are_publish_only" {
  command = plan

  assert {
    condition = toset(flatten([
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Action
    ])) == toset(["s3:ListBucket", "s3:PutObject", "s3:DeleteObject", "cloudfront:CreateInvalidation"])
    error_message = "Sync and invalidate, nothing else."
  }

  assert {
    condition = toset(flatten([
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Resource
    ])) == toset(["arn:aws:s3:::example-site", "arn:aws:s3:::example-site/*", "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"])
    error_message = "One bucket and one distribution, no wildcard resources."
  }
}

run "immutable_subject_with_ids" {
  command = plan

  variables {
    github_owner_id      = 1001
    github_repository_id = 2002
  }

  assert {
    condition     = output.token_subject == "repo:example@1001/example.org@2002:ref:refs/heads/main"
    error_message = "With ids the role matches GitHub's immutable subject (repo:owner@id/name@id)."
  }
}

run "bad_repository_is_refused" {
  command = plan

  variables {
    github_repository = "example"
  }

  expect_failures = [var.github_repository]
}
