mock_provider "aws" {}

variables {
  role_name      = "example-logs-reader"
  log_bucket_arn = "arn:aws:s3:::example-logs"
  principal_arns = ["arn:aws:iam::123456789012:user/stats"]
}

run "reader_role_is_read_only" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.AWS == ["arn:aws:iam::123456789012:user/stats"]
    error_message = "Only the listed principals may assume the reader role."
  }

  assert {
    condition = toset(flatten([
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Action
    ])) == toset(["s3:ListBucket", "s3:GetObject"])
    error_message = "The reader role can list and read, nothing else."
  }

  assert {
    condition = toset(flatten([
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Resource
    ])) == toset(["arn:aws:s3:::example-logs", "arn:aws:s3:::example-logs/*"])
    error_message = "One bucket only."
  }
}

run "a_principal_is_required" {
  command = plan

  variables {
    principal_arns = []
  }

  expect_failures = [var.principal_arns]
}
