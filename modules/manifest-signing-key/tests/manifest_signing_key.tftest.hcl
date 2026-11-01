mock_provider "aws" {}

variables {
  alias_name  = "example-org-manifest-signing"
  description = "Signs the timetable manifest of example.org"
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
