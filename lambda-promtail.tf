resource "aws_iam_role" "lambda_role" {
  name_prefix        = "${local.prefix}-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid    = ""
    effect = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = data.aws_iam_policy.lambda_vpc_execution.arn
}

data "aws_iam_policy" "lambda_vpc_execution" {
  name = "AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_cloudwatch" {
  name   = "cloudwatch"
  role   = aws_iam_role.lambda_role.name
  policy = data.aws_iam_policy_document.lambda_cloudwatch.json
}

data "aws_iam_policy_document" "lambda_cloudwatch" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      format("%s:*", aws_cloudwatch_log_group.lambda_log_group.arn),
    ]
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${local.prefix}_lambda_promtail"
  retention_in_days = 1
}

resource "aws_lambda_function" "lambda_promtail" {
  function_name = "${local.prefix}-lambda-promtail"
  role          = aws_iam_role.lambda_role.arn
  image_uri    = "${aws_ecr_repository.ecr_lambda_promtail_image.repository_url}:dev"
  timeout      = 60
  memory_size  = 128
  package_type = "Image"

  vpc_config {
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id, aws_subnet.private_3.id]
    security_group_ids = [aws_security_group.lambda_promtail.id]
  }

  environment {
    variables = {
      # https://grafana.com/docs/loki/latest/send-data/lambda-promtail/
      WRITE_ADDRESS            = "http://${aws_lb.loki_lb.dns_name}/loki/api/v1/push"
      USERNAME                 = null
      PASSWORD                 = null
      BEARER_TOKEN             = null
      KEEP_STREAM              = null # this will add __aws_cloudwatch_log_stream
      BATCH_SIZE               = null # Determines when to flush the batch of logs (bytes).
      EXTRA_LABELS             = "aws_service,cloudwatch,foo,bar,baz,quz" # Comma separated list of extra labels, in the format 'name1,value1,name2,value2,...,nameN,valueN' to add to entries forwarded by lambda-promtail.
      DROP_LABELS              = null # Comma separated list of labels to be drop, in the format 'name1,name2,...,nameN' to be omitted to entries forwarded by lambda-promtail.
      OMIT_EXTRA_LABELS_PREFIX = "false" # "false" Whether or not to omit the prefix `__extra_` from extra labels defined in the variable `extra_labels`.
      TENANT_ID                = null
      SKIP_TLS_VERIFY          = null # Determines whether to verify the TLS certificate
      PRINT_LOG_LINE           = "true" # Determines whether we want the lambda to output the parsed log line before sending it on to promtail. Value needed to disable is the string 'false'
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_cloudwatch,
    aws_iam_role_policy_attachment.lambda_vpc_execution,
    # Ensure function is created after, and destroyed before, the log-group
    # This prevents the log-group from being re-created by an invocation of the lambda-function
    aws_cloudwatch_log_group.lambda_log_group,
  ]
}

resource "aws_lambda_function_event_invoke_config" "lambda_promtail" {
  function_name          = aws_lambda_function.lambda_promtail.function_name
  maximum_retry_attempts = 2
}

resource "aws_security_group" "lambda_promtail" {
  name        = "${local.prefix}-lambda-promtail-sg"
  description = "Security group for lambda promtail"
  vpc_id      = aws_vpc.vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lambda_permission" "lambda_promtail_allow_cloudwatch" {
  statement_id  = "lambda-promtail-allow-cloudwatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_promtail.function_name
  principal     = "logs.${data.aws_region.current.name}.amazonaws.com"
}

# you need more of these for every log group one
resource "aws_cloudwatch_log_subscription_filter" "lambdafunction_logfilter" {
  name           = "lambdafunction_logfilter"
  log_group_name = aws_cloudwatch_log_group.grafana_log_group.name
  destination_arn = aws_lambda_function.lambda_promtail.arn
  filter_pattern = ""
}

resource "aws_cloudwatch_log_subscription_filter" "lambdafunction_logfilter_2" {
  name           = "lambdafunction_logfilter_2"
  log_group_name = aws_cloudwatch_log_group.httpbin_log_group.name
  destination_arn = aws_lambda_function.lambda_promtail.arn
  filter_pattern = ""
}
