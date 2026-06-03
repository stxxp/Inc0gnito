variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "lambda_security_resp_name" {
  type        = string
  description = "Lambda function name"
}

variable "allowed_products" {
  type        = list(string)
  description = "Allowed finding product name"
}

variable "bucket_name" {
  description = "S3 bucket for logs"
  type        = string
}

variable "quarantine_action" {
  type        = string
  description = "Auto response action name"
}

variable "state_machine_arn" {
  type        = string
  description = "Target Step Functions state machine ARN"
}

variable "event_rule_name" {
  type        = string
  description = "EventBridge rule name"
}

variable "event_sources" {
  type = map(object({
    source        = string
    detail_type   = string
    product_name  = string
  }))
}

variable "lambda_ai_agent_name" {
  type = string
}

variable "bedrock_model_id" {
  type        = string
  description = "Bedrock model ID"
}

variable "bedrock_region" {
  type        = string
  description = "Bedrock runtime region"
}

variable "ai_prompt_template" {
  type        = string
  description = "AI prompt analyze template"
}