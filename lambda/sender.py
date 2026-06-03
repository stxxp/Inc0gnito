import json
import os
import re
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

# 환경 변수 로드
SLACK_BOT_TOKEN = os.environ.get('SLACK_BOT_TOKEN')
SLACK_CHANNEL_ID = os.environ.get('SLACK_CHANNEL_ID')


client = WebClient(token=SLACK_BOT_TOKEN)

def lambda_handler(event, context):
    try:
        
        alert_data = event.get('event', {})
        
        mode = event.get('mode', 'default')
        
        if mode == "analyze":
            task_token = event['token']
            is_reminder = event.get('is_reminder', False)
            ai_analysis = event.get('ai_analysis', '{}')

            try:

                if isinstance(ai_analysis, dict):
           
                    ai_data = ai_analysis
                elif isinstance(ai_analysis, str):
        
                    ai_data = json.loads(ai_analysis)
            except json.JSONDecodeError:
                # 3. 만약 JSON 형식이 깨진 문자열이라면 정규표현식으로 강제 추출
                print("⚠️ JSON 파싱 실패 - 정규표현식 추출 모드로 전환")
                summary_match = re.search(r'"summary"\s*:\s*"([^"]+)"', ai_analysis, re.I)
                ai_data['summary'] = summary_match.group(1) if summary_match else "요약 추출 실패"
                
                action_match = re.search(r'"recommended_actions"[\s:]+([\s\S]*?)(?=,"impact_score"|$)', ai_analysis, re.I)
                ai_data['recommended_actions'] = [] # 상세 파싱 로직 필요시 추가
                
                impact_match = re.search(r'"impact_score"\s*:\s*"?([0-9.]+)"?', ai_analysis, re.I)
                ai_data['impact_score'] = impact_match.group(1) if impact_match else "0"
            
            #Summary = ai_data.get("Summary", "내용 없음")
            
            risk_level = ai_data.get("risk_level", "내용 없음")
            recommended_actions = ai_data.get("recommended_actions", "내용 없음")
            summary = ai_data.get("summary", "내용 없음")
            impact_score = ai_data.get("impact_score", "내용 없음")

            finding_id = alert_data.get("finding_id", "N/A")
            product_name = alert_data.get("product_name", "N/A")
            finding_type = alert_data.get("finding_type", "N/A")
            severity = alert_data.get("severity", "N/A")
            instance_id = alert_data.get("instance_id", "N/A")
            resource_arn = alert_data.get("resource_arn", "N/A")
            run_ssm = str(alert_data.get("run_ssm", "N/A"))
            execution_source = alert_data.get("execution_source", "N/A")

            checkbox_options = []
            action_mapping = {}
            
            try:
                if isinstance(recommended_actions, dict):
                    recommended_actions = recommended_actions
                elif isinstance(recommended_actions, str):
                    recommended_actions = json.loads(recommended_actions)
            except json.JSONDecodeError:
            
                print("⚠️ JSON 파싱 실패 - 정규표현식 추출 모드로 전환")
                summary_match = re.search(r'"summary"\s*:\s*"([^"]+)"', recommended_actions, re.I)
                ai_data['summary'] = summary_match.group(1) if summary_match else "요약 추출 실패"
                
                action_match = re.search(r'"recommended_actions"[\s:]+([\s\S]*?)(?=,"impact_score"|$)', ai_analysis, re.I)
                ai_data['recommended_actions'] = []
                
                impact_match = re.search(r'"impact_score"\s*:\s*"?([0-9.]+)"?', ai_analysis, re.I)
                ai_data['impact_score'] = impact_match.group(1) if impact_match else "0"
                    
            for idx, action in enumerate(recommended_actions):
                action_id = f"action_{idx}"
                
                action_mapping[action_id] = {
                    "action_type": action.get("action", "내용 없음"),
                    "description": action.get("reason", "내용 없음"),
                    "status": "pending"
                }
                
                checkbox_options.append({
                    "text": {
                        "type": "plain_text",
                        "text": action.get("action", "내용 없음"),
                        "emoji": True
                    },
                    "description": { 
                        "type": "plain_text",
                        "text": action.get("reason", "내용 없음"),
                    },
                    "value": f"action_{idx}"
                })
            
            if not checkbox_options:
                checkbox_options.append({
                    "text": {"type": "plain_text", "text": "✅ 기본 승인 (Approve)"},
                    "value": "approve"
                })
                
                
            prefix = "🚨 *[리마인드]* " if is_reminder else "🚨 *[신규]* "


            color = "#FF0000"
            if severity.upper() in ["LOW", "INFORMATIONAL"]:
                color = "#00FF00"
            elif severity.upper() == "MEDIUM":
                color = "#FFFF00"

            blocks = [
                {
                    "type": "header",
                    "text": {
                        "type": "plain_text",
                        "text": f"{'리마인드: ' if is_reminder else ''}보안 위협 분석 보고서",
                        "emoji": True
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*{product_name}* 에서 새로운 위협이 탐지되었습니다.\n*상태:* 승인 대기 중"
                    }
                },
                {
                    "type": "divider"
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*Summary*: {summary}\n\n*Risk_level*: {risk_level}\n*⚠️ 영향도 점수*\n> * {impact_score} / 10*"
                    }
                },
                {
                    "type": "divider"
                }
            ]

            # 버튼과 컬러 바는 기존처럼 attachments를 활용 (blocks와 혼용 가능)
            attachments = [
                {
                    "fallback": "승인 프로세스 불가",
                    "color": color,
                    "blocks": [
                        {
                            "type": "section",
                            "fields": [
                                {"type": "mrkdwn", "text": f"*Severity*\n*{severity}*"},
                                {"type": "mrkdwn", "text": f"*Instance ID*\n`{instance_id}`"},
                                {"type": "mrkdwn", "text": f"*Finding Type*\n{finding_type}"},
                                {"type": "mrkdwn", "text": f"*Execution Source*\n{execution_source}"},
                                {"type": "mrkdwn", "text": f"*Finding ID*\n{finding_id}"},
                                {"type": "mrkdwn", "text": f"*Resource ARN*\n`{resource_arn}`"}
                            ]
                        },
                        {
                            "type": "section",
                            "text": {"type": "mrkdwn", "text": "🛠️ *대응 방안 선택 (다중 선택 가능)*"}
                        },
                        {
                            "type": "actions",
                            "block_id": "remediation_block",
                            "elements": [
                                {
                                    "type": "checkboxes",
                                    "action_id": "action_selection",
                                    "options": checkbox_options # 👈 동적으로 생성된 체크박스
                                }
                            ]
                        },
                        {
                            "type": "actions",
                            "elements": [
                                {
                                    "type": "button",
                                    "text": {"type": "plain_text", "text": "🚀 선택 항목 실행"},
                                    "style": "primary",
                                    "value": json.dumps({"token": task_token, "action": "submit","mapping":action_mapping}),
                                    "action_id": "submit_btn"
                                },
                                {
                                    "type": "button",
                                    "text": {"type": "plain_text", "text": "❌ 반려"},
                                    "style": "danger",
                                    "value": json.dumps({"token": task_token, "action": "reject"}),
                                    "action_id": "reject_btn"
                                }
                            ]
                        }
                    ]
                }
            ]

            client.chat_postMessage(
                channel=SLACK_CHANNEL_ID,
                text=f"{prefix} 보안 위협 탐지 알림",
                blocks=blocks,
                attachments=attachments
            )

            return {"statusCode": 200, "body": "Message sent"}

        elif mode == "process":
            ai_analysis = event.get('ai_analysis', '{}')
            
            finding_id = alert_data.get("finding_id", "N/A")
            severity = alert_data.get("severity", "N/A")
            instance_id = alert_data.get("instance_id", "N/A")
            
            process_blocks = [
                {
                    "type": "header",
                    "text": {
                        "type": "plain_text",
                        "text": "⚙️ 보안 대응 프로세스 시작",
                        "emoji": True
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"사용자 승인에 따라 *{instance_id}* 인스턴스에 대한 조사를 시작합니다."
                    }
                },
                {
                    "type": "context",
                    "elements": [
                        {"type": "mrkdwn", "text": f"*Finding ID:* {finding_id}"},
                        {"type": "mrkdwn", "text": f"*Severity:* {severity}"}
                    ]
                }
            ]

            process_attachments = [
                {
                    "color": "#3AA3E3",
                    "blocks": [
                        {
                            "type": "section",
                            "text": {
                                "type": "mrkdwn",
                                "text": "🏃 *진행 예정인 작업:*\n• 격리용 AMI 이미지 생성\n• 인스턴스 메모리 덤프 (LiME/WinPmem)\n• 인스턴스 중지 및 고립"
                            }
                        }
                    ]
                }
            ]

            # 슬랙 메시지 전송
            client.chat_postMessage(
                channel=SLACK_CHANNEL_ID,
                text="🚀 보안 대응 프로세스가 시작되었습니다.",
                blocks=process_blocks,
                attachments=process_attachments
            )
    
    except SlackApiError as e:
        print(f"❌ Slack 연동 에러: {e.response['error']}")
        raise e
    except Exception as e:
        print(f"❌ 내부 시스템 에러: {str(e)}")
        raise e