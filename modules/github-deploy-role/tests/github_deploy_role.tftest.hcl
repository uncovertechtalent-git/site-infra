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

run "defaults_keep_the_whole_bucket_and_no_deny" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.this.policy).Statement) == 3
    error_message = "Without the new options the policy keeps its three statements."
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_iam_role_policy.this.policy).Statement[0]), "Condition")
    error_message = "Listing is not narrowed to a prefix by default."
  }
}

run "shell_role_is_denied_the_data_prefix" {
  command = plan

  variables {
    github_environment  = "production"
    deny_write_prefixes = ["data/"]
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement :
      s.Effect == "Deny" && toset(s.Action) == toset(["s3:PutObject", "s3:DeleteObject"]) && s.Resource == ["arn:aws:s3:::example-site/data/*"]
    ])
    error_message = "An explicit deny keeps the shell role out of data/, whatever else allows it."
  }

  assert {
    condition     = output.token_subject == "repo:example/example.org:environment:production"
    error_message = "The shell role is trusted by the production environment."
  }
}

run "data_role_is_limited_to_its_prefix_and_cannot_invalidate" {
  command = plan

  variables {
    write_prefix       = "data/"
    allow_read         = true
    allow_invalidation = false
    distribution_arn   = null
  }

  assert {
    condition = toset(flatten([
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Action
    ])) == toset(["s3:ListBucket", "s3:PutObject", "s3:DeleteObject", "s3:GetObject"])
    error_message = "Publish, read back, prune. No invalidation."
  }

  assert {
    condition = toset(flatten([
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Resource
    ])) == toset(["arn:aws:s3:::example-site", "arn:aws:s3:::example-site/data/*"])
    error_message = "Objects only under data/; the bucket itself only to list."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.this.policy).Statement[0].Condition.StringLike["s3:prefix"] == ["data/*"]
    error_message = "Listing is narrowed to data/."
  }

  assert {
    condition     = output.token_subject == "repo:example/example.org:ref:refs/heads/main"
    error_message = "The data role is trusted by the main branch."
  }
}

run "invalidation_needs_a_distribution" {
  command = plan

  variables {
    distribution_arn = null
  }

  expect_failures = [var.distribution_arn]
}

run "write_prefix_must_be_a_plain_prefix" {
  command = plan

  variables {
    write_prefix = "/data/*"
  }

  expect_failures = [var.write_prefix]
}

run "deny_prefix_must_be_a_plain_prefix" {
  command = plan

  variables {
    deny_write_prefixes = ["data"]
  }

  expect_failures = [var.deny_write_prefixes]
}

run "signing_adds_three_kms_actions_on_one_key_and_nothing_else" {
  command = plan

  variables {
    write_prefix = "data/"
    allow_read   = true
    sign_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition = toset([
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Action if s.Sid == "SignManifest"
    ][0]) == toset(["kms:Sign", "kms:Verify", "kms:GetPublicKey"])
    error_message = "Sign, verify and read the public key, nothing that changes or deletes the key."
  }

  assert {
    condition = [
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Resource if s.Sid == "SignManifest"
    ][0] == "arn:aws:kms:eu-central-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    error_message = "One key, no wildcard."
  }

  assert {
    condition = !anytrue([
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement : anytrue([for a in flatten([s.Action]) : startswith(a, "kms:") && !contains(["kms:Sign", "kms:Verify", "kms:GetPublicKey"], a)])
    ])
    error_message = "No other KMS action."
  }
}

run "no_signing_key_no_kms_access" {
  command = plan

  assert {
    condition = !anytrue([
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement : anytrue([for a in flatten([s.Action]) : startswith(a, "kms:")])
    ])
    error_message = "A role without a signing key has no KMS permission."
  }
}
