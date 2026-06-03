aws_region = "ap-northeast-2"

project_name = "antifragile-mvp"

lambda_security_resp_name = "antifragile-mvp-security-response"

allowed_products = ["GuardDuty", "Inspector", "Macie"]

bucket_name = "your-bucket-name"

quarantine_action = "sg-quarantine"

state_machine_arn = "arn:aws:states:REGION:ACCOUNT_ID:stateMachine:STATE_MACHINE_NAME"

event_rule_name = "antifragile-mvp-securityhub-findings"

event_sources = {
  guardduty = {
    source       = "aws.securityhub"
    detail_type  = "Security Hub Findings - Imported"
    product_name = "GuardDuty"
  }

  inspector = {
    source       = "aws.securityhub"
    detail_type  = "Security Hub Findings - Imported"
    product_name = "Inspector"
  }

  macie = {
    source       = "aws.securityhub"
    detail_type  = "Security Hub Findings - Imported"
    product_name = "Amazon Macie"
  }
}

lambda_ai_agent_name = "ai-agent-invoker"

bedrock_model_id = "anthropic.claude-3-5-sonnet-20240620-v1:0"

bedrock_region   = "ap-northeast-2"

ai_prompt_template = "너는 클라우드 보안 대응 시스템이다. 입력된 보안 이벤트를 분석하여 위협 요약(summary), 위험도 평가(risk_level), 영향도 점수(impact_score, 0~100), 대응 방안 3개 이상을 제시하라. 각 action은 실제 AWS에서 실행 가능한 형태로 작성하고, 각 action에 대해 최대 5개의 step을 생성하라. step은 리스트 형태로 작성하며 \"1.\", \"2.\" 등의 번호를 절대 포함하지 마라. 반드시 다음 JSON 형식만 출력하라((매우중요)그 외에 불필요한 문장이나 대답은 절대 출력하지 마라.): {{\"summary\": \"한 줄 요약\", \"risk_level\": \"LOW | MEDIUM | HIGH | CRITICAL\", \"impact_score\": 0, \"recommended_actions\": [{{\"action\": \"ISOLATE_INSTANCE | REVOKE_IAM_ROLE | SNAPSHOT_INSTANCE | BLOCK_IP | MONITOR\", \"reason\": \"한 줄 설명\", \"steps\": [\"step 내용\", \"step 내용\", \"step 내용\"]}}]}} 입력: {input_text}"
# 너는 클라우드 보안 대응 시스템이다.

# 입력된 보안 이벤트를 분석하여 다음을 수행하라:
# 1. 위협 요약(summary)
# 2. 위험도 평가(risk_level)
# 3. 영향도 점수(impact_score, 0~100)
# 4. 대응 방안 3개 이상 제시

# 각 action에 대해:
# - 실제 AWS에서 실행 가능한 형태로 작성하라
# - 해당 action에 대한 대응 절차를 최대 5단계(step)로 작성하라
# - step은 리스트 형태로 작성하며 "1.", "2." 등의 번호를 포함하지 마라

# 반드시 다음 JSON 형식만 출력하라:
# {
#   "summary": "한 줄 요약",
#   "risk_level": "LOW | MEDIUM | HIGH | CRITICAL",
#   "impact_score": 0,
#   "recommended_actions": [
#     {
#       "action": "ISOLATE_INSTANCE | REVOKE_IAM_ROLE | SNAPSHOT_INSTANCE | BLOCK_IP | MONITOR",
#       "reason": "한 줄 설명",
#       "steps": [
#         "step 내용",
#         "step 내용",
#         "step 내용"
#       ]
#     }
#   ]
# }

# (매우중요) 그 외에 불필요한 문장이나 대답은 절대 출력하지 마라.

# 입력:
# {input_text}
slack_bot_token      = "xoxb-your-token"
slack_signing_secret = "your-signing-secret"
slack_channel_id     = "C0123456789"
