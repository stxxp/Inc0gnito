import os
import json
import boto3
from botocore.exceptions import ClientError
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

sfn = boto3.client('stepfunctions')

app = App(
    token=os.environ.get("SLACK_BOT_TOKEN"),
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
    process_before_response=True
)

@app.action("action_selection")
def handle_checkbox_selection(ack):
    ack()

@app.action("submit_btn")
def handle_remediation_approval(ack, body, respond):
    ack()
    
    try:
        action_data = json.loads(body['actions'][0]['value'])
        task_token = action_data['token']
        decision = action_data['action']
        action_mapping = action_data.get('mapping', {})
        
        state_values = body.get('state', {}).get('values', {})
        remediation_block = state_values.get('remediation_block', {})
        action_selection = remediation_block.get('action_selection', {})
        selected_options = action_selection.get('selected_options', [])
        
        if not selected_options:
            # (원본 메시지는 유지)
            respond(text="⚠️ 선택된 대응 방안이 없습니다. 체크박스를 하나 이상 선택해주세요.", replace_original=False)
            return
        selected_actions = [option['value'] for option in selected_options]
        
        enriched_actions = []
        for option in selected_options:
            selected_id = option['value'] # ex) "action_0"
            if selected_id in action_mapping:
                enriched_actions.append(action_mapping[selected_id])
            else:
                # Fallback
                enriched_actions.append({"action_type": selected_id})
        
        # Step Functions 재개 함수 호출
        resume_step_functions(task_token, decision, enriched_actions, respond)
        
    except Exception as e:
        respond(text=f"❌ 버튼 데이터 파싱 오류가 발생했습니다: {str(e)}", replace_original=True)
        print(f"❌ 파싱 에러: {str(e)}")

@app.action("reject_btn")
def handle_reject(ack, body, respond):
    ack()
    
    try:
        action_data = json.loads(body['actions'][0]['value'])
        task_token = action_data['token']
        decision = action_data['action'] # "reject"
        
        # 반려는 선택 항목 없이 바로 Step Functions 재개
        resume_step_functions(task_token, decision, [], respond)
        
    except Exception as e:
        respond(text=f"❌ 반려 데이터 파싱 오류가 발생했습니다: {str(e)}", replace_original=True)
        print(f"❌ 파싱 에러: {str(e)}")

def resume_step_functions(task_token, decision, selected_actions, respond):
    try:
        sfn.send_task_success(
            taskToken=task_token,
            output=json.dumps({"action": decision, "selected_actions": selected_actions})
        )
        if decision == "reject":
            respond(text="❌ 관리자에 의해 해당 위협 대응이 반려(무시)되었습니다.", replace_original=True)
            print("✅ Step Functions 재개 성공: reject")
        else:
            action_names = [item.get("action_type", "Unknown") for item in selected_actions]
            actions_str = ", ".join(action_names)
                
            # 🟢 성공 시: 버튼 메시지를 텍스트로 덮어쓰기
            respond(text=f"✅ 정상적으로 대응이 승인되었습니다. \n*실행 항목:* {actions_str}", replace_original=True)
            print(f"✅ Step Functions 재개 성공: {decision}")
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'TaskDoesNotExist':
            respond(text="⚠️ 이미 처리되었거나 만료된 알림입니다.", replace_original=True)
            print("❌ 만료된 토큰 요청됨")
        elif error_code == 'TaskTimedOut':
            respond(text="⚠️ 타임아웃으로 만료된 알림입니다.", replace_original=True)
            print("❌ 타임아웃된 토큰 요청됨")
        else:
            respond(text=f"❌ AWS 연동 오류가 발생했습니다: {error_code}", replace_original=True)
            print(f"❌ AWS 에러: {e}")
            
    except Exception as e:
        respond(text=f"❌ 시스템 내부 오류가 발생했습니다: {str(e)}", replace_original=True)
        print(f"❌ 알 수 없는 에러: {str(e)}")


def lambda_handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)