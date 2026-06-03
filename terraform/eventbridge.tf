# 1. eventbridge rule 생성
resource "aws_cloudwatch_event_rule" "securityhub_rules" {
  for_each = var.event_sources

  name        = "${var.project_name}-${each.key}-rule"
  description = "${each.key} findings 이벤트 처리"

  event_pattern = jsonencode({
    source = [each.value.source]
    "detail-type" = [each.value.detail_type]
    detail = {
      findings = {
        ProductName = [each.value.product_name]
      }
    }
  })
}

# 2. Target(lambda) 연결
resource "aws_cloudwatch_event_target" "lambda_target" {
  for_each = var.event_sources

  rule      = aws_cloudwatch_event_rule.securityhub_rules[each.key].name
  target_id = "${each.key}-target"
  arn       = aws_lambda_function.security_response.arn
}

# 3. lambda 권한
resource "aws_lambda_permission" "allow_eventbridge" {
  for_each = var.event_sources

  statement_id  = "AllowExecutionFromEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_response.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.securityhub_rules[each.key].arn
}