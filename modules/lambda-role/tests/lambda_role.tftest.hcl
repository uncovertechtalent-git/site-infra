mock_provider "aws" {}

variables {
  role_name      = "ask-example-lambda"
  function_name  = "ask-example"
  aws_account_id = "123456789012"
  log_group_arn  = "arn:aws:logs:eu-central-1:123456789012:log-group:/aws/lambda/ask-example"
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
    condition = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal == { Service = "lambda.amazonaws.com" } && jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition == { StringEquals = { "aws:SourceAccount" = "123456789012" } }
    error_message = "Only this account's Lambda service may assume the role."
  }
}

run "a_wildcard_log_group_is_refused" {
  command = plan

  variables {
    log_group_arn = "arn:aws:logs:eu-central-1:123456789012:log-group:*"
  }

  expect_failures = [var.log_group_arn]
}
