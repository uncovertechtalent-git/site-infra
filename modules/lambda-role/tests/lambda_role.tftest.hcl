mock_provider "aws" {}

variables {
  role_name     = "ask-example-lambda"
  function_name = "ask-example"
  log_group_arn = "arn:aws:logs:eu-central-1:123456789012:log-group:/aws/lambda/ask-example"
}

run "writes_its_own_log_group_only" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role_policy.this.policy).Statement == [{
      Sid      = "WriteOwnLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:eu-central-1:123456789012:log-group:/aws/lambda/ask-example:*"
    }]
    error_message = "The function role may write its own log group and nothing else."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement == [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
    error_message = "Only the Lambda service may assume the role."
  }
}

run "a_wildcard_log_group_is_refused" {
  command = plan

  variables {
    log_group_arn = "arn:aws:logs:eu-central-1:123456789012:log-group:*"
  }

  expect_failures = [var.log_group_arn]
}
