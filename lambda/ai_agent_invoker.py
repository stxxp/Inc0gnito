import json
import boto3
import os

bedrock = boto3.client("bedrock-runtime")

def lambda_handler(event, context):
    input_text = event.get("inputText", "")  # 전체 이벤트 문자열

    prompt = os.environ["AI_PROMPT"]

    prompt = prompt.format(
        input_text=input_text
    )

    response = bedrock.converse(  # bedrock 호출
        modelId=os.environ["MODEL_ID"],
        messages=[
            {
                "role": "user",
                "content": [
                    {"text": prompt}
                ]
            }
        ],
        inferenceConfig={   
            "maxTokens": 700,    # 모델이 답할 최대 토큰 수
            "temperature": 0.3,  # 높을수록 창의적, 낮을수록 일관적 답변
            "topP": 0.9          # 단어 후보 샘플링 옵션: 출력 다양성에 영향
        }
    )

    # ai_text = {"risk_level":"HIGH","action":"ISOLATE","reason":"..."}
    ai_text = response["output"]["message"]["content"][0]["text"]

    ALLOWED_ACTIONS = [
        "ISOLATE_INSTANCE",
        "REVOKE_IAM_ROLE",
        "SNAPSHOT_INSTANCE",
        "BLOCK_IP",
        "MONITOR"
    ]

    try:
        ai_json = json.loads(ai_text)

        actions = ai_json.get("recommended_actions", [])
        if not isinstance(actions, list):
            actions = []

        safe_actions = []

        for item in actions:
            if not isinstance(item, dict):
                continue

            action = item.get("action")
            reason = item.get("reason", "")
            steps = item.get("steps", [])

            if action not in ALLOWED_ACTIONS:
                continue

            if not isinstance(steps, list):
                continue

            # 최대 5단계 제한
            steps = steps[:5]

            safe_actions.append({
                "action": action,
                "reason": reason,
                "steps": steps
            })

        ai_json = {
            "summary": ai_json.get("summary", ""),
            "risk_level": ai_json.get("risk_level", "UNKNOWN"),
            "impact_score": ai_json.get("impact_score", 0),
            "recommended_actions": safe_actions
        }

    except Exception:
        ai_json = {
            "summary": ai_text[:100],
            "risk_level": "UNKNOWN",
            "impact_score": 0,
            "recommended_actions": []
        }

    print("AI RESULT:", json.dumps(ai_json))
    return {
        "ai_analysis": ai_json
    }