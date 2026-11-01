mock_provider "aws" {}

variables {
  alias_name      = "example-org-manifest-signing"
  description     = "Signs the timetable manifest of example.org"
  signer_role_arn = "arn:aws:iam::123456789012:role/example-org-github-data"
}

run "an_asymmetric_p256_signing_key" {
  command = plan

  assert {
    condition     = aws_kms_key.this.key_usage == "SIGN_VERIFY" && aws_kms_key.this.customer_master_key_spec == "ECC_NIST_P256"
    error_message = "The key signs and verifies with ECDSA P-256, which the browser's WebCrypto can check."
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/example-org-manifest-signing"
    error_message = "The alias is the name given, under alias/."
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 30
    error_message = "A deleted signing key cannot come back: the longest window."
  }
}

run "the_alias_may_not_claim_an_aws_name" {
  command = plan

  variables {
    alias_name = "aws/s3"
  }

  expect_failures = [var.alias_name]
}

run "the_deletion_window_is_bounded" {
  command = plan

  variables {
    deletion_window_in_days = 3
  }

  expect_failures = [var.deletion_window_in_days]
}

run "the_account_root_keeps_the_key" {
  command = plan

  assert {
    condition = length([
      for st in jsondecode(aws_kms_key.this.policy).Statement : st
      if st.Effect == "Allow" && st.Principal.AWS == "arn:aws:iam::123456789012:root" && st.Action == "kms:*" && st.Resource == "*"
    ]) == 1
    error_message = "The account root is allowed kms:*: that is what lets the account's IAM policies grant access and keeps the key administrable."
  }

  assert {
    condition     = length([for st in jsondecode(aws_kms_key.this.policy).Statement : st if st.Effect == "Allow"]) == 1
    error_message = "The root is the only Allow in the key policy: everyone else is named by an IAM policy."
  }
}

run "only_the_data_role_may_sign" {
  command = plan

  assert {
    condition = length([
      for st in jsondecode(aws_kms_key.this.policy).Statement : st
      if st.Effect == "Deny" && st.Principal == "*" && st.Action == "kms:Sign" && st.Resource == "*"
      && st.Condition.ArnNotEquals["aws:PrincipalArn"] == "arn:aws:iam::123456789012:role/example-org-github-data"
    ]) == 1
    error_message = "kms:Sign is denied to every principal whose ARN is not the data role of the site."
  }

  assert {
    condition     = length(jsondecode(aws_kms_key.this.policy).Statement) == 2
    error_message = "Two statements: the root Allow and the Deny of kms:Sign to everyone but the data role."
  }
}

run "the_public_key_and_verification_stay_open" {
  command = plan

  assert {
    condition = alltrue([
      for st in jsondecode(aws_kms_key.this.policy).Statement :
      st.Effect != "Deny" || (!contains(flatten([st.Action]), "kms:GetPublicKey") && !contains(flatten([st.Action]), "kms:Verify") && !contains(flatten([st.Action]), "kms:*"))
    ])
    error_message = "The operator reads the public key by hand (kms:GetPublicKey) and neither it nor kms:Verify can produce a signature: no Deny on them."
  }
}

run "a_gov_cloud_role_names_a_gov_cloud_root" {
  command = plan

  variables {
    signer_role_arn = "arn:aws-us-gov:iam::210987654321:role/example-org-github-data"
  }

  assert {
    condition     = [for st in jsondecode(aws_kms_key.this.policy).Statement : st.Principal.AWS if st.Effect == "Allow"][0] == "arn:aws-us-gov:iam::210987654321:root"
    error_message = "The root principal comes from the partition and the account of the role."
  }
}

run "the_signer_must_be_a_role_arn" {
  command = plan

  variables {
    signer_role_arn = "arn:aws:iam::123456789012:user/someone"
  }

  expect_failures = [var.signer_role_arn]
}

run "a_short_account_id_is_refused" {
  command = plan

  variables {
    signer_role_arn = "arn:aws:iam::1234:role/example-org-github-data"
  }

  expect_failures = [var.signer_role_arn]
}
