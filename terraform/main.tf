terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# 현재 계정 정보
data "aws_caller_identity" "current" {}

# ---------------------------
# Lambda 코드 zip
# ---------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda/function.zip"
}

data "archive_file" "ai_agent_invoker_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/ai_agent_invoker.py"
  output_path = "${path.module}/lambda/ai_agent_invoker.zip"
}

# ---------------------------
# IAM Role (security_response)
# ---------------------------
resource "aws_iam_role" "lambda_role_response" {
  name = "${var.project_name}-lambda-role-response"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

# ---------------------------
# IAM Role (AgentInvoker)
# ---------------------------
resource "aws_iam_role" "lambda_role_agent" {
  name = "${var.project_name}-lambda-role-agent"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

# ---------------------------
# Bedrock 권한 (AgentInvoker 전용)
# ---------------------------
resource "aws_iam_policy" "lambda_bedrock" {
  name = "${var.project_name}-lambda-bedrock"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = [
        "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-5-sonnet-*",
        "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_bedrock_attach" {
  role       = aws_iam_role.lambda_role_agent.name
  policy_arn = aws_iam_policy.lambda_bedrock.arn
}

# ---------------------------
# CloudWatch Logs 권한
# ---------------------------
resource "aws_iam_role_policy_attachment" "lambda_basic_execution_response" {
  role       = aws_iam_role.lambda_role_response.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_agent" {
  role       = aws_iam_role.lambda_role_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------
# Step Functions 실행 권한 (response만)
# ---------------------------
resource "aws_iam_policy" "lambda_start_sfn" {
  name = "${var.project_name}-lambda-start-sfn"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = var.state_machine_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_start_sfn_attach" {
  role       = aws_iam_role.lambda_role_response.name
  policy_arn = aws_iam_policy.lambda_start_sfn.arn
}

# ---------------------------
# S3 쓰기 권한 (response만)
# ---------------------------
resource "aws_iam_policy" "lambda_s3_write" {
  name = "${var.project_name}-lambda-s3-write"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject"]
      Resource = "arn:aws:s3:::${var.bucket_name}/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3_write_attach" {
  role       = aws_iam_role.lambda_role_response.name
  policy_arn = aws_iam_policy.lambda_s3_write.arn
}

# ---------------------------
# CloudWatch Log Group
# ---------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_security_resp_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "agent_invoker_logs" {
  name              = "/aws/lambda/${var.project_name}-${var.lambda_ai_agent_name}"
  retention_in_days = 14
}

# ---------------------------
# Lambda Function (Event 처리)
# ---------------------------
resource "aws_lambda_function" "security_response" {
  function_name = var.lambda_security_resp_name
  role          = aws_iam_role.lambda_role_response.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  handler = "lambda_function.lambda_handler"
  runtime = "python3.11"

  timeout     = 15
  memory_size = 256

  environment {
    variables = {
      ALLOWED_PRODUCTS  = join(",", var.allowed_products)
      QUARANTINE_ACTION = var.quarantine_action
      STATE_MACHINE_ARN = var.state_machine_arn
      BUCKET_NAME       = var.bucket_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution_response,
    aws_iam_role_policy_attachment.lambda_start_sfn_attach,
    aws_iam_role_policy_attachment.lambda_s3_write_attach,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# ---------------------------
# Lambda Function (Bedrock AI)
# ---------------------------
resource "aws_lambda_function" "ai_agent_invoker" {
  function_name = "${var.project_name}-${var.lambda_ai_agent_name}"

  role = aws_iam_role.lambda_role_agent.arn

  filename         = data.archive_file.ai_agent_invoker_zip.output_path
  source_code_hash = data.archive_file.ai_agent_invoker_zip.output_base64sha256

  handler = "ai_agent_invoker.lambda_handler"
  runtime = "python3.11"

  timeout     = 60
  memory_size = 256

  environment {
    variables = {
      MODEL_ID = var.bedrock_model_id
      AI_PROMPT     = var.ai_prompt_template
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution_agent,
    aws_iam_role_policy_attachment.lambda_bedrock_attach,
    aws_cloudwatch_log_group.agent_invoker_logs
  ]
}