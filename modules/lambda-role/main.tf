# Execution role of one Lambda function: write its own log group, nothing
# else. The function reads only public HTTPS files, so it needs no AWS
# permission beyond its logs. The trust names the Lambda service; only a
# principal of this account with iam:PassRole on this role (the CI apply role,
# for Lambda only, and the operator) can attach it to a function.

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "Runs the ${var.function_name} function: its own log group only."
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "this" {
  name = "own-log-group"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${var.log_group_arn}:*"
      },
    ]
  })
}
