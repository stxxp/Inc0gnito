import os
import json
import boto3
import datetime
import uuid
from botocore.exceptions import ClientError

# Step Functions 클라이언트 생성
stepfunctions = boto3.client("stepfunctions")


# Lambda: Security Hub finding을 받아 EC2 기반 위협만 필터링 후 Step Functions로 자동 대응을 트리거하는 함수
def lambda_handler(event, context):
    request_id = context.aws_request_id
    execution_source = "securityhub-eventbridge"

    print("FULL EVENT:", json.dumps(event))

    # 1) EventBridge로부터 전달된 Security Hub finding 존재 여부 확인
    findings = event.get("detail", {}).get("findings", [])
    if not findings:
        logs = {
            "status": "ignored",
            "reason": "No findings",
            "request_id": request_id,
            "execution_source": execution_source,
            "debug": {
                "finding_id": None,
                "finding_type": [],
                "severity": None,
                "product_name": None,
                "instance_id": None,
                "resource_arn": None
            }
        }
        print(json.dumps(logs))
        return {"results": [logs]}

    results = []

    s3 = boto3.client("s3")
    BUCKET = os.environ["BUCKET_NAME"]
    # 2) 여러 finding 순회해 개별적 처리
    for finding in findings:
        timestamp = datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%S%f")
        
        finding_id = finding.get("Id", "UNKNOWN")
        product_name = finding.get("ProductName", "UNKNOWN")
        severity = finding.get("Severity", {}).get("Label", "UNKNOWN")
        finding_types = finding.get("Types", [])

        # 2-0) raw finding logging
        s3.put_object(
            Bucket=BUCKET,
            Key=f"raw-findings/{timestamp}_{finding_id}.json",
            Body=json.dumps(finding)
        )

        # 2-1) EC2 리소스가 포함된 finding만 자동 대응 대상으로 필터링
        resource = next(
            (r for r in finding.get("Resources", []) if r.get("Type") == "AwsEc2Instance"),
            None
        )

        if not resource:
            logs = {
                "status": "ignored",
                "reason": "No EC2 resource",
                "request_id": request_id,
                "execution_source": execution_source,
                "debug": {
                    "finding_id": finding_id,
                    "finding_type": finding_types,
                    "severity": severity,
                    "product_name": product_name,
                    "instance_id": None,
                    "resource_arn": None
                }
            }
            print(json.dumps(logs))
            results.append(logs)
            continue

        # 2-2) EC2 ARN에서 instance_id 추출 및 유효성 검증
        resource_arn = resource.get("Id", "")
        if not resource_arn:
            logs = {
                "status": "ignored",
                "reason": "No resource Id",
                "request_id": request_id,
                "execution_source": execution_source,
                "debug": {
                    "finding_id": finding_id,
                    "finding_type": finding_types,
                    "severity": severity,
                    "product_name": product_name,
                    "instance_id": None,
                    "resource_arn": resource_arn if resource_arn else "EMPTY"
                }
            }
            print(json.dumps(logs))
            results.append(logs)
            continue

        instance_id = resource_arn.split("/")[-1]

        if not instance_id.startswith("i-"):
            logs = {
                "status": "ignored",
                "reason": "Invalid instance id",
                "request_id": request_id,
                "execution_source": execution_source,
                "debug": {
                    "finding_id": finding_id,
                    "finding_type": finding_types,
                    "severity": severity,
                    "product_name": product_name,
                    "instance_id": instance_id,
                    "resource_arn": resource_arn
                }
            }
            print(json.dumps(logs))
            results.append(logs)
            continue

        # 2-3) 허용된 보안 서비스에서 온 finding만 처리
        allowed_products = [p.strip() for p in os.environ.get("ALLOWED_PRODUCTS", "").split(",") if p.strip()]

        if product_name not in allowed_products:
            logs = {
                "status": "ignored",
                "reason": "Unsupported product",
                "request_id": request_id,
                "execution_source": execution_source,
                "debug": {
                    "finding_id": finding_id,
                    "finding_type": finding_types,
                    "severity": severity,
                    "product_name": product_name,
                    "instance_id": instance_id,
                    "resource_arn": resource_arn
                }
            }
            print(json.dumps(logs))
            results.append(logs)
            continue

        # finding type을 prefix 기준으로 필터링해 허용 여부 판단하는 함수
        def is_allowed(finding_type):
            allowed_prefixes = [
                "Backdoor:EC2",
                "Trojan:EC2",
                "CryptoCurrency:EC2",
                "UnauthorizedAccess:EC2",
                "Recon:EC2",
                "Impact:EC2",
                "Persistence:EC2",
                "TTPs/",
                "Software and Configuration Checks/",
                "SensitiveData:S3",
                "Policy:"
            ]
            return any(finding_type.startswith(p) for p in allowed_prefixes)

        # 2-4) finding type이 허용된 prefix에 해당하는지 검사
        matched_type = next((t for t in finding_types if is_allowed(t)), None)

        if not matched_type:
            logs = {
                "status": "ignored",
                "reason": "Unsupported finding type",
                "request_id": request_id,
                "execution_source": execution_source,
                "debug": {
                    "finding_id": finding_id,
                    "finding_type": finding_types,
                    "severity": severity,
                    "product_name": product_name,
                    "instance_id": instance_id,
                    "resource_arn": resource_arn
                }
            }
            print(json.dumps(logs))
            results.append(logs)
            continue

        # 2-5) Step Functions로 전달할 자동 대응 입력 payload
        payload = {
            "finding_id": finding_id,
            "product_name": product_name,
            "finding_type": matched_type,
            "severity": severity,
            "instance_id": instance_id,
            "resource_arn": resource_arn,
            "run_ssm": False,
            "summary": "GuardDuty finding detected. Instance will be isolated.",
            "execution_source": execution_source
        }
        # normalized finding logging
        s3.put_object(
            Bucket=BUCKET,
            Key=f"normalized-events/{timestamp}_{finding_id}.json",
            Body=json.dumps(payload)
        )

        # 2-6) 중복 실행 방지를 위한 execution name 생성
        execution_name = f"{finding_id}-{instance_id}-{uuid.uuid4().hex[:8]}".replace(":", "-").replace("/", "-")[:80]

        try:
            # 2-6-1) Step Functions 실행 -> 실제 대응 워크플로우 시작
            response = stepfunctions.start_execution(
                stateMachineArn=os.environ["STATE_MACHINE_ARN"],
                name=execution_name,
                input=json.dumps(payload)
            )

            logs = {
                "status": "accepted",
                "reason": "Step Functions execution started",
                "request_id": request_id,
                "execution_source": execution_source,
                "execution_arn": response["executionArn"],
                "debug": {
                    "finding_id": finding_id,
                    "finding_type": finding_types,
                    "severity": severity,
                    "product_name": product_name,
                    "instance_id": instance_id,
                    "resource_arn": resource_arn
                }
            }
            print(json.dumps(logs))
            results.append(logs)

        except ClientError as e:
            error_code = e.response["Error"]["Code"]

            if error_code == "ExecutionAlreadyExists":
                logs = {
                    "status": "ignored",
                    "reason": "Duplicate execution",
                    "request_id": request_id,
                    "execution_source": execution_source,
                    "debug": {
                        "finding_id": finding_id,
                        "finding_type": finding_types,
                        "severity": severity,
                        "product_name": product_name,
                        "instance_id": instance_id,
                        "resource_arn": resource_arn
                    }
                }
                print(json.dumps(logs))
                results.append(logs)
            else:
                logs = {
                    "status": "error",
                    "reason": "Failed to start Step Functions execution",
                    "request_id": request_id,
                    "execution_source": execution_source,
                    "error_code": error_code,
                    "debug": {
                        "finding_id": finding_id,
                        "finding_type": finding_types,
                        "severity": severity,
                        "product_name": product_name,
                        "instance_id": instance_id,
                        "resource_arn": resource_arn
                    }
                }
                print(json.dumps(logs))
                raise

        except Exception as e:
            logs = {
                "status": "error",
                "reason": str(e),
                "request_id": request_id,
                "execution_source": execution_source,
                "debug": {
                    "finding_id": finding_id,
                    "finding_type": finding_types,
                    "severity": severity,
                    "product_name": product_name,
                    "instance_id": instance_id,
                    "resource_arn": resource_arn
                }
            }
            print(json.dumps(logs))
            raise

    return {"results": results}