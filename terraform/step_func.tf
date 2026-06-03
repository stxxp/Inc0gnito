

terraform {
 required_providers {
  aws = {
   source = "hashicorp/aws"
   version = "~> 5.0"
  }
 }
}

provider "aws" {
 region = "ap-northeast-2"
 profile = "antifragile"
}

variable "target_bucket" {
 type  = string
 default = "testbucket-073109174888-ap-northeast-2-an"
}

variable "target_subnet" {
 type  = string
 default = "subnet-0f385c32d46a4f779"
}

variable "target_sgs" {
 type  = list(string)
 default = ["sg-01a5bb94d6998c4dd"]
}



# Step Functions 실행을 위한 IAM 역할 생성
resource "aws_iam_role" "sfn_role" {
 name = "stepfunc-role"

 assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [
   {
    Action = "sts:AssumeRole"
    Effect = "Allow"
    Principal = {
     Service = "states.amazonaws.com"
    }
   }
  ]
 })
}

# Step Functions에 필요한 권한 부여(Bedrock 추가됨)
resource "aws_iam_role_policy" "sfn_policy" {
 name = "stepfunc-policy"
 role = aws_iam_role.sfn_role.id

 policy = jsonencode({
  Version = "2012-10-17"
  Statement = [
   {
    Effect = "Allow"
    Action = [
     "ec2:DescribeIamInstanceProfileAssociations",
     "ec2:AssociateIamInstanceProfile",
     "ec2:ReplaceIamInstanceProfileAssociation",
     "ec2:CreateImage",
     "ec2:DescribeInstances",
     "ec2:DescribeImages",
     "ec2:DisassociateIamInstanceProfile",
     "ec2:RunInstances",
     "ec2:StopInstances"
    ]
    Resource = "*"
   },
   {
    Effect = "Allow"
    Action = [
     "ssm:DescribeInstanceInformation",
     "ssm:SendCommand",
     "ssm:GetCommandInvocation"
    ]
    Resource = "*"
   },
   {
    Effect = "Allow"
    Action = "iam:PassRole"
    Resource = aws_iam_role.ec2_temp_role.arn
   },
   {
    Effect = "Allow"
    Action = [
     "s3:PutObject"
    ]
    Resource = [
     "arn:aws:s3:::${var.target_bucket}/action-results/*"
    ]
   },
   {
    Effect = "Allow"
    Action = [
     "bedrock:InvokeModel"
    ]
    Resource = "*"
   }
  ]
 })
}

#=======================================================================================
#=======================================================================================

# EC2에 부여할 역할을 사용할 수 있도록 정책 생성
resource "aws_iam_role" "ec2_temp_role" {
 name = "ec24temprole"

 assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [
   {
    Action = "sts:AssumeRole"
    Effect = "Allow"
    Principal = {
     Service = "ec2.amazonaws.com"
    }
   }
  ]
 })
}

# SSM 통신을 위한 정책 연결
resource "aws_iam_role_policy_attachment" "ssm_core_attach" {
 role   = aws_iam_role.ec2_temp_role.name
 policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# S3 버킷에 업로드하기 위한 정책 연결
resource "aws_iam_policy" "s3_write_policy" {
 name = "ec2_s3write-policy"

 policy = jsonencode({
  Version = "2012-10-17"
  Statement = [
   {
    Effect = "Allow"
    Action = [
     "s3:PutObject"
    ]
    Resource = "arn:aws:s3:::${var.target_bucket}/mem-dump/*"
   },
   {
    Effect = "Allow"
    Action = [
     "s3:GetBucketLocation",
     "s3:ListBucket"
    ]
    Resource = "arn:aws:s3:::${var.target_bucket}"
   }
  ]
 })
}

# S3 권한 정책을 역할에 연결
resource "aws_iam_role_policy_attachment" "s3_write_attach" {
 role   = aws_iam_role.ec2_temp_role.name
 policy_arn = aws_iam_policy.s3_write_policy.arn
}

# Step Function이 참조할 IAM 인스턴스 프로파일 생성
resource "aws_iam_instance_profile" "ec2_temp_profile" {
 name = "ec24tempprofile"
 role = aws_iam_role.ec2_temp_role.name
}


#=======================================================================================
#=======================================================================================

# Lambda를 실행할 권리 정책
resource "aws_iam_role_policy" "sfn_invoke_lambda_policy" {
 name = "sfn_invoke_lambda"
 role = aws_iam_role.sfn_role.id
 policy = jsonencode({
  Version = "2012-10-17",
  Statement = [{
   Effect = "Allow",
   Action = "lambda:InvokeFunction",
   Resource = [
    aws_lambda_function.sender_lambda.arn,
    data.aws_lambda_function.agent_invoker_lambda.arn
   ]
  }]
 })
}

# Receiver lambdad가 sfn을 재가동할 정책
resource "aws_iam_role_policy" "receiver_sfn_policy" {
 name = "receiver_sfn_policy"
 role = aws_iam_role.receiver_lambda_role.id
 policy = jsonencode({
  Version = "2012-10-17",
  Statement = [{
   Effect = "Allow",
   Action = ["states:SendTaskSuccess", "states:SendTaskFailure"],
   Resource = "*"
  }]
 })
}


variable "slack_bot_token" {
 description = "Slack Bot Token (xoxb-...)"
 type    = string
 sensitive = true
}

variable "slack_signing_secret" {
 description = "Slack App의 Signing Secret"
 type    = string
 sensitive = true
}

variable "slack_channel_id" {
 description = "알림을 보낼 Slack Channel ID (예: C01234567)"
 type        = string
}

resource "aws_iam_role" "sender_lambda_role" {
 name = "sender_lambda_role"
 assume_role_policy = jsonencode({
  Version = "2012-10-17",
  Statement = [{
   Action  = "sts:AssumeRole",
   Effect  = "Allow",
   Principal = { Service = "lambda.amazonaws.com" }
  }]
 })
}

resource "aws_iam_role_policy_attachment" "sender_basic_exec_attach" {
 role   = aws_iam_role.sender_lambda_role.name
 policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Python 코드 압축
data "archive_file" "sender_zip" {
 type    = "zip"
 source_file = "${path.module}/sender.py"
 output_path = "${path.module}/sender_lambda.zip"
}

# Lambda 리소스
resource "aws_lambda_function" "sender_lambda" {
 function_name  = "Sender"
 role      = aws_iam_role.sender_lambda_role.arn
 handler     = "sender.lambda_handler"
 runtime     = "python3.10"
 filename    = data.archive_file.sender_zip.output_path
 source_code_hash = data.archive_file.sender_zip.output_base64sha256

 layers = [aws_lambda_layer_version.slack_bolt_layer.arn]

 environment {
  variables = {
   SLACK_BOT_TOKEN = var.slack_bot_token
   SLACK_CHANNEL_ID = var.slack_channel_id
  }
 }
}
resource "aws_lambda_layer_version" "slack_bolt_layer" {
 filename      = "${path.module}/slack_layer.zip"
 layer_name     = "slack_bolt_layer"
 compatible_runtimes = ["python3.10"]
}

resource "aws_iam_role" "receiver_lambda_role" {
 name = "receiver_lambda_role"
 assume_role_policy = jsonencode({
  Version = "2012-10-17",
  Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
 })
}

resource "aws_iam_role_policy_attachment" "receiver_basic_exec_attach" {
 role   = aws_iam_role.receiver_lambda_role.name
 policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_permission" "allow_public_url_permission" {
 statement_id     = "FunctionURLAllowPublicAccess"
 action        = "lambda:InvokeFunctionUrl"
 function_name     = aws_lambda_function.receiver_lambda.function_name
 principal       = "*" # principal 수정 필요
 function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "allow_invoke_function_permission" {
 statement_id = "AllowInvokeFunctionAccess"
 action    = "lambda:InvokeFunction"
 function_name = aws_lambda_function.receiver_lambda.function_name
 principal  = "*"
}



# Python 코드 압축
data "archive_file" "receiver_zip" {
 type    = "zip"
 output_path = "${path.module}/receiver_lambda.zip"
 source_file = "${path.module}/receiver.py"
}

# Lambda 리소스
resource "aws_lambda_function" "receiver_lambda" {
 function_name  = "Receiver"
 role      = aws_iam_role.receiver_lambda_role.arn
 handler = "receiver.lambda_handler"
 runtime = "python3.10"
 filename    = data.archive_file.receiver_zip.output_path
 source_code_hash = data.archive_file.receiver_zip.output_base64sha256

 layers = [aws_lambda_layer_version.slack_bolt_layer.arn]

 environment {
  variables = {
   SLACK_BOT_TOKEN   = var.slack_bot_token
   SLACK_SIGNING_SECRET = var.slack_signing_secret
  }
 }
}

data "aws_lambda_function" "agent_invoker_lambda" {
 function_name  = "antifragile-mvp-ai-agent-invoker"
}


# Lambda Function URL (Slack Webhook 연동용)
resource "aws_lambda_function_url" "receiver_url" {
 function_name   = aws_lambda_function.receiver_lambda.function_name
 authorization_type = "NONE" # 외부(Slack) 접근 허용
}

output "SLACK_WEBHOOK_URL" {
 description = "이 URL을 복사하여 Slack App의 'Interactivity Request URL'에 붙여넣으세요!"
 value =aws_lambda_function_url.receiver_url.function_url
}

resource "aws_sfn_state_machine" "state_machine" {
  name     = "StateMachine4SlackNSSM"
  role_arn = aws_iam_role.sfn_role.arn

  definition = <<EOF
{
  "Comment": "Managed by Terraform - High Fidelity Incident Response Workflow",
  "QueryLanguage": "JSONata",
  "StartAt": "GlobalVar",
  "States": {
    "CriticalError": {
      "Next": "RecordLog2",
      "Output": {
        "ami_id": "{% '' %}",
        "dump_path": "{% '' %}",
        "duration": "{% ($toMillis($now()) - $toMillis($gStartTime)) / 1000 %}",
        "error_log": "{% $gErrorLog %}",
        "finding_id": "{% $gFindingId %}",
        "instance_id": "{% $gInstanceId %}",
        "os_type": "{% '' %}",
        "sf_status": "{% 'Fail' %}",
        "start_time": "{% $gStartTime %}"
      },
      "Type": "Pass"
    },
    "GlobalVar": {
      "Assign": {
        "OriginEvent": "{% $states.input %}",
        "gBucket": "{% 'testbucket-073109174888-ap-northeast-2-an' %}",
        "gErrorLog": [],
        "gFindingId": "{% $states.input.finding_id %}",
        "gInstanceId": "{% $states.input.instance_id %}",
        "gStartTime": "{% $now() %}"
      },
      "Next": "Parallel",
      "Type": "Pass"
    },
    "Parallel": {
      "Branches": [
        {
          "StartAt": "Var",
          "States": {
            "Var": {
              "Assign": {
                "Bucket": "{% 'testbucket-073109174888-ap-northeast-2-an' %}",
                "DumpPath": "{% 'Skipped' %}",
                "ErrorLog": [],
                "FindingId": "{% $states.input.finding_id %}",
                "InstanceId": "{% $states.input.instance_id %}",
                "NewImageId": "{% 'Skipped' %}",
                "PlatformType": "{% 'Skipped' %}",
                "ProfileName": "{% 'ec24tempprofile' %}",
                "Severity": "{% $states.input.severity %}",
                "SgId": "{% [\"sg-01a5bb94d6998c4dd\"] %}",
                "StartTime": "{% $now() %}",
                "SubnetId": "{% 'subnet-0f385c32d46a4f779' %}",
                "actions": "{% 'Skipped' %}"
              },
              "Next": "CheckSeverity",
              "Type": "Pass"
            },
            "CheckSeverity": {
              "Choices": [
                {
                  "Condition": "{% $Severity = 'HIGH' or $Severity = 'CRITICAL' %}",
                  "Next": "AnalyzeFindingWithBedrock"
                }
              ],
              "Default": "Pass",
              "Type": "Choice"
            },
            "AnalyzeFindingWithBedrock": {
              "Arguments": {
                "FunctionName": "{% 'arn:aws:lambda:ap-northeast-2:073109174888:function:antifragile-mvp-ai-agent-invoker' %}",
                "Payload": {
                  "agentAliasId": "{% 'TSTALIASID' %}",
                  "agentId": "{% 'LUDB36G1EJ' %}",
                  "inputText": "{% $string($OriginEvent) %}",
                  "sessionId": "{% $uuid() %}"
                }
              },
              "Assign": {
                "ai_analysis": "{% $states.result.Payload.ai_analysis %}",
                "mode": "{% 'analyze' %}"
              },
              "Next": "InitSlackDefaultValues",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Retry": [
                {
                  "BackoffRate": 2,
                  "ErrorEquals": [
                    "BedrockRuntime.ThrottlingException",
                    "ThrottlingException",
                    "Lambda.TooManyRequestsException"
                  ],
                  "IntervalSeconds": 300,
                  "MaxAttempts": 3
                }
              ],
              "Type": "Task"
            },
            "InitSlackDefaultValues": {
              "Assign": {
                "event": "{% $OriginEvent %}",
                "is_reminder": "{% false %}",
                "timeout_duration": "{% 60 %}"
              },
              "Next": "SendSlackApproval",
              "Type": "Pass"
            },
            "SendSlackApproval": {
              "Arguments": {
                "FunctionName": "{% 'arn:aws:lambda:ap-northeast-2:073109174888:function:Sender' %}",
                "Payload": {
                  "ai_analysis": "{% $ai_analysis %}",
                  "event": "{% $event %}",
                  "is_reminder": "{% $is_reminder %}",
                  "mode": "{% 'analyze' %}",
                  "token": "{% $states.context.Task.Token %}"
                }
              },
              "Catch": [
                {
                  "Assign": {
                    "error_info": "{% $states.errorOutput %}"
                  },
                  "ErrorEquals": [
                    "States.Timeout"
                  ],
                  "Next": "SetReminderFlag"
                }
              ],
              "Next": "CheckApprovalResult",
              "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
              "TimeoutSeconds": "{% $timeout_duration %}",
              "Type": "Task"
            },
            "SetReminderFlag": {
              "Assign": {
                "is_reminder": "{% true %}",
                "timeout_duration": "{% 3600 %}"
              },
              "Next": "SendSlackApproval",
              "Type": "Pass"
            },
            "CheckApprovalResult": {
              "Choices": [
                {
                  "Condition": "{% $states.input.action = 'submit' %}",
                  "Next": "DescribeInstanceProfile",
                  "Assign": {
                    "actions": "{% $states.input.selected_actions.action_type %}"
                  }
                }
              ],
              "Default": "IRRejected",
              "Type": "Choice"
            },
            "IRRejected": {
              "Next": "Pass",
              "Type": "Pass"
            },
            "DescribeInstanceProfile": {
              "Type": "Task",
              "Resource": "arn:aws:states:::aws-sdk:ec2:describeIamInstanceProfileAssociations",
              "Arguments": {
                "Filters": [
                  {
                    "Name": "instance-id",
                    "Values": "{% [$InstanceId] %}"
                  }
                ]
              },
              "Assign": {
                "Association": "{% $states.result.IamInstanceProfileAssociations %}"
              },
              "Next": "CheckProfile"
            },
            "CheckProfile": {
              "Type": "Choice",
              "Choices": [
                {
                  "Next": "ReplaceProfileAssociation",
                  "Condition": "{% $count($Association) > 0 %}"
                }
              ],
              "Default": "AssociateProfile"
            },
            "ReplaceProfileAssociation": {
              "Type": "Task",
              "Arguments": {
                "AssociationId": "{% $Association[0].AssociationId %}",
                "IamInstanceProfile": {
                  "Name": "{% $ProfileName %}"
                }
              },
              "Resource": "arn:aws:states:::aws-sdk:ec2:replaceIamInstanceProfileAssociation",
              "Next": "IsolateInstance"
            },
            "AssociateProfile": {
              "Type": "Task",
              "Arguments": {
                "IamInstanceProfile": {
                  "Name": "{% $ProfileName %}"
                },
                "InstanceId": "{% $InstanceId %}"
              },
              "Resource": "arn:aws:states:::aws-sdk:ec2:associateIamInstanceProfile",
              "Next": "IsolateInstance"
            },
            "IsolateInstance": {
              "Type": "Choice",
              "Choices": [
                {
                  "Next": "CreateImage",
                  "Condition": "{% 'ISOLATE_INSTANCE' in $actions %}"
                }
              ],
              "Default": "SnapshotInstance"
            },
            "CreateImage": {
              "Type": "Task",
              "Arguments": {
                "InstanceId": "{% $InstanceId %}",
                "Name": "{% $InstanceId & '_' & $now('[Y0001]-[M01]-[D01]_[H01][m01]', '+0900') %}"
              },
              "Resource": "arn:aws:states:::aws-sdk:ec2:createImage",
              "Next": "GetInstanceType",
              "Assign": {
                "NewImageId": "{% $states.result.ImageId %}"
              },
              "Catch": [
                {
                  "ErrorEquals": [
                    "States.ALL"
                  ],
                  "Next": "SnapshotInstance",
                  "Assign": {
                    "NewImageId": "FAIL",
                    "ErrorLog": "{% $append($ErrorLog, $states.errorOutput) %}"
                  }
                }
              ]
            },
            "GetInstanceType": {
              "Type": "Task",
              "Arguments": {
                "InstanceIds": [
                  "{% $InstanceId %}"
                ]
              },
              "Resource": "arn:aws:states:::aws-sdk:ec2:describeInstances",
              "Next": "WaitforAMI",
              "Assign": {
                "OriginalType": "{% $states.result.Reservations[0].Instances[0].InstanceType %}"
              }
            },
            "WaitforAMI": {
              "Type": "Wait",
              "Seconds": 120,
              "Next": "DescribeImages"
            },
            "DescribeImages": {
              "Type": "Task",
              "Resource": "arn:aws:states:::aws-sdk:ec2:describeImages",
              "Next": "CheckAMIState",
              "Arguments": {
                "ImageIds": [
                  "{% $NewImageId %}"
                ]
              },
              "Assign": {
                "AMIState": "{% $states.result.Images[0].State %}"
              }
            },
            "CheckAMIState": {
              "Type": "Choice",
              "Choices": [
                {
                  "Next": "SnapshotInstance",
                  "Condition": "{% $AMIState = 'available' %}"
                },
                {
                  "Next": "SnapshotInstance",
                  "Condition": "{% $AMIState = 'failed' %}",
                  "Assign": {
                    "NewImageId": "FAIL",
                    "ErrorLog": "{% $append($ErrorLog, {'Error': 'AMIState is failed.'}) %}"
                  }
                }
              ],
              "Default": "WaitforAMI"
            },
            "SnapshotInstance": {
              "Type": "Choice",
              "Choices": [
                {
                  "Next": "CheckOS",
                  "Condition": "{% 'SNAPSHOT_INSTANCE' in $actions %}"
                }
              ],
              "Default": "ExistAmi"
            },
            "CheckOS": {
              "Type": "Task",
              "Arguments": {
                "Filters": [
                  {
                    "Key": "InstanceIds",
                    "Values": [
                      "{% $InstanceId %}"
                    ]
                  }
                ]
              },
              "Resource": "arn:aws:states:::aws-sdk:ssm:describeInstanceInformation",
              "Next": "DumpByOS",
              "Assign": {
                "PlatformType": "{% $states.result.InstanceInformationList[0].PlatformType %}",
                "DumpPath": "{% 's3://' & $Bucket & '/mem-dump/memdump_' & $InstanceId & $now('[Y0001]-[M01]-[D01]_[H01][m01]', '+0900') & '.raw' %}"
              }
            },
            "DumpByOS": {
              "Type": "Choice",
              "Choices": [
                {
                  "Next": "RunWindowsDump",
                  "Condition": "{% $PlatformType = 'Windows' %}"
                }
              ],
              "Default": "RunLinuxDump"
            },
            "RunLinuxDump": {
              "Arguments": {
                "DocumentName": "AWS-RunShellScript",
                "InstanceIds": [
                  "{% $InstanceId %}"
                ],
                "Parameters": {
                  "commands": [
                    "set -e",
                    "yum install -y gcc make git elfutils-libelf-devel kernel-devel-$(uname -r)",
                    "rm -rf /tmp/LiME /tmp/memdump.raw",
                    "cd /tmp && git clone https://github.com/504ensicsLabs/LiME.git && cd LiME/src && make",
                    "insmod ./lime-$(uname -r).ko path=/tmp/memdump.raw format=raw",
                    "{% 'aws s3 cp /tmp/memdump.raw ' & $DumpPath %}",
                    "rmmod lime && rm -rf /tmp/LiME /tmp/memdump.raw"
                  ]
                }
              },
              "Assign": {
                "CommandId": "{% $states.result.Command.CommandId %}"
              },
              "Catch": [
                {
                  "Assign": {
                    "ErrorLog": "{% $append($ErrorLog, $states.errorOutput) %}"
                  },
                  "ErrorEquals": [
                    "States.ALL"
                  ],
                  "Next": "ExistAmi"
                }
              ],
              "Next": "WaitforDump",
              "Resource": "arn:aws:states:::aws-sdk:ssm:sendCommand",
              "TimeoutSeconds": 3600,
              "Type": "Task"
            },
            "RunWindowsDump": {
              "Arguments": {
                "DocumentName": "AWS-RunPowerShellScript",
                "InstanceIds": [
                  "{% $InstanceId %}"
                ],
                "Parameters": {
                  "commands": [
                    "New-Item -ItemType Directory -Force -Path C:/temp | Out-Null",
                    "Invoke-WebRequest -Uri https://github.com/Velocidex/c-aff4/releases/download/v3.3.rc3/winpmem_mini_x64.exe -OutFile C:/temp/winpmem.exe",
                    "C:/temp/winpmem.exe C:/temp/memdump.raw",
                    "{% 'aws s3 cp C:/temp/memdump.raw ' & $DumpPath %}",
                    "Remove-Item -Path C:/temp/memdump.raw, C:/temp/winpmem.exe -Force"
                  ]
                }
              },
              "Assign": {
                "CommandId": "{% $states.result.Command.CommandId %}"
              },
              "Catch": [
                {
                  "Assign": {
                    "ErrorLog": "{% $append($ErrorLog, $states.errorOutput) %}"
                  },
                  "ErrorEquals": [
                    "States.ALL"
                  ],
                  "Next": "ExistAmi"
                }
              ],
              "Next": "WaitforDump",
              "Resource": "arn:aws:states:::aws-sdk:ssm:sendCommand",
              "TimeoutSeconds": 3600,
              "Type": "Task"
            },
            "WaitforDump": {
              "Next": "GetDumpStatus",
              "Seconds": 10,
              "Type": "Wait"
            },
            "GetDumpStatus": {
              "Arguments": {
                "CommandId": "{% $CommandId %}",
                "InstanceId": "{% $InstanceId %}"
              },
              "Assign": {
                "DumpStatus": "{% $states.result.Status %}"
              },
              "Next": "CheckDumpStatus",
              "Resource": "arn:aws:states:::aws-sdk:ssm:getCommandInvocation",
              "Type": "Task"
            },
            "CheckDumpStatus": {
              "Choices": [
                {
                  "Condition": "{% $DumpStatus = 'Success' %}",
                  "Next": "ExistAmi"
                },
                {
                  "Condition": "{% $DumpStatus = 'Pending' or $DumpStatus = 'InProgress' or $DumpStatus = 'Delayed' %}",
                  "Next": "WaitforDump"
                }
              ],
              "Default": "ExistAmi",
              "Type": "Choice"
            },
            "ExistAmi": {
              "Type": "Choice",
              "Choices": [
                {
                  "Condition": "{% $NewImageId in [\"FAIL\", \"Skipped\"] %}",
                  "Next": "DescribeIamInstance"
                }
              ],
              "Default": "RunInstances"
            },
            "DescribeIamInstance": {
              "Type": "Task",
              "Arguments": {
                "Filters": [
                  {
                    "Name": "instance-id",
                    "Values": "{% [$InstanceId] %}"
                  }
                ]
              },
              "Resource": "arn:aws:states:::aws-sdk:ec2:describeIamInstanceProfileAssociations",
              "Next": "RevokeIAM",
              "Assign": {
                "NewAssociation": "{% $states.result.IamInstanceProfileAssociations %}"
              }
            },
            "RevokeIAM": {
              "Type": "Choice",
              "Choices": [
                {
                  "Next": "DisassociateIamInstanceProfile",
                  "Condition": "{% 'REVOKE_IAM_ROLE' in $actions %}"
                }
              ],
              "Default": "ReplaceIamInstanceProfile"
            },
            "DisassociateIamInstanceProfile": {
              "Type": "Task",
              "Arguments": {
                "AssociationId": "{% $NewAssociation[0].AssociationId %}"
              },
              "Resource": "arn:aws:states:::aws-sdk:ec2:disassociateIamInstanceProfile",
              "Next": "BlockIP"
            },
            "ReplaceIamInstanceProfile": {
              "Type": "Task",
              "Arguments": {
                "AssociationId": "{% $NewAssociation[0].AssociationId %}",
                "IamInstanceProfile": {
                  "Name": "{% $substringAfter($Association[0].IamInstanceProfile.Arn, '/') %}"
                }
              },
              "Resource": "arn:aws:states:::aws-sdk:ec2:replaceIamInstanceProfileAssociation",
              "Next": "BlockIP"
            },
            "BlockIP": {
              "Type": "Choice",
              "Choices": [
                {
                  "Next": "ModifyInstanceAttribute",
                  "Condition": "{% 'BLOCK_IP' in $actions %}"
                }
              ],
              "Default": "hasErrorLog"
            },
            "ModifyInstanceAttribute": {
              "Type": "Task",
              "Arguments": {
                "InstanceId": "{% $InstanceId %}",
                "Groups": "{% $SgId %}"
              },
              "Resource": "arn:aws:states:::aws-sdk:ec2:modifyInstanceAttribute",
              "Next": "hasErrorLog"
            },
            "RunInstances": {
              "Arguments": {
                "ImageId": "{% $NewImageId %}",
                "InstanceType": "{% $OriginalType %}",
                "MaxCount": 1,
                "MinCount": 1,
                "SecurityGroupIds": "{% $SgId %}",
                "SubnetId": "{% $SubnetId %}"
              },
              "Assign": {
                "NewInstanceId": "{% $states.result.Instances[0].InstanceId %}"
              },
              "Next": "RevokeIAMwithIsol",
              "Resource": "arn:aws:states:::aws-sdk:ec2:runInstances",
              "Type": "Task"
            },
            "RevokeIAMwithIsol": {
              "Type": "Choice",
              "Choices": [
                {
                  "Next": "StopOriginalInstances",
                  "Condition": "{% 'REVOKE_IAM_ROLE' in $actions %}"
                }
              ],
              "Default": "DescribeIamInstanceProfileAssociations"
            },
            "DescribeIamInstanceProfileAssociations": {
              "Type": "Task",
              "Arguments": {
                "Filters": [
                  {
                    "Name": "instance-id",
                    "Values": "{% [$NewInstanceId] %}"
                  }
                ]
              },
              "Resource": "arn:aws:states:::aws-sdk:ec2:describeIamInstanceProfileAssociations",
              "Next": "ReplaceIamInstanceProfileAssociation",
              "Assign": {
                "NewAssociation": "{% $states.result.IamInstanceProfileAssociations %}"
              }
            },
            "ReplaceIamInstanceProfileAssociation": {
              "Type": "Task",
              "Arguments": {
                "AssociationId": "{% $NewAssociation[0].AssociationId %}",
                "IamInstanceProfile": {
                  "Name": "{% $Association[0].IamInstanceProfile.Arn %}"
                }
              },
              "Resource": "arn:aws:states:::aws-sdk:ec2:replaceIamInstanceProfileAssociation",
              "Next": "StopOriginalInstances"
            },
            "StopOriginalInstances": {
              "Arguments": {
                "InstanceIds": [
                  "{% $InstanceId %}"
                ]
              },
              "Next": "hasErrorLog",
              "Resource": "arn:aws:states:::aws-sdk:ec2:stopInstances",
              "Type": "Task"
            },
            "hasErrorLog": {
              "Choices": [
                {
                  "Condition": "{% $count($ErrorLog) > 0 %}",
                  "Next": "PartialSuccess"
                }
              ],
              "Default": "Success",
              "Type": "Choice"
            },
            "PartialSuccess": {
              "Assign": {
                "ami_id": "{% $NewImageId %}",
                "dump_path": "{% $DumpPath %}",
                "duration": "{% ($toMillis($now()) - $toMillis($StartTime)) / 1000 %}",
                "error_log": "{% $ErrorLog %}",
                "finding_id": "{% $FindingId %}",
                "instance_id": "{% $InstanceId %}",
                "os_type": "{% $PlatformType %}",
                "sf_status": "{% 'PARTIAL_SUCCESS' %}",
                "start_time": "{% $StartTime %}",
                "action": "{% $actions %}"
              },
              "Next": "RecordLog",
              "Type": "Pass"
            },
            "Success": {
              "Next": "RecordLog",
              "Output": {
                "ami_id": "{% $NewImageId %}",
                "dump_path": "{% $DumpPath %}",
                "duration": "{% ($toMillis($now()) - $toMillis($StartTime)) / 1000 %}",
                "error_log": "{% $ErrorLog %}",
                "finding_id": "{% $FindingId %}",
                "instance_id": "{% $InstanceId %}",
                "os_type": "{% $PlatformType %}",
                "sf_status": "{% 'SUCCESS' %}",
                "start_time": "{% $StartTime %}",
                "action": "{% $actions %}"
              },
              "Type": "Pass"
            },
            "Pass": {
              "Next": "Success",
              "Type": "Pass"
            },
            "RecordLog": {
              "Arguments": {
                "Body": "{% $states.input %}",
                "Bucket": "{% $Bucket %}",
                "Key": "{% 'action-results/' & $FindingId & '_' & $now('[Y0001]-[M01]-[D01]_[H01]-[m01]-[s01]', '+0900') & '.log' %}"
              },
              "End": true,
              "Resource": "arn:aws:states:::aws-sdk:s3:putObject",
              "Type": "Task"
            }
          }
        }
      ],
      "Catch": [
        {
          "Assign": {
            "gErrorLog": "{% $append($gErrorLog, $states.errorOutput) %}"
          },
          "ErrorEquals": [
            "States.ALL"
          ],
          "Next": "CriticalError"
        }
      ],
      "End": true,
      "Type": "Parallel"
    },
    "RecordLog2": {
      "Arguments": {
        "Body": "{% $states.input %}",
        "Bucket": "{% $gBucket %}",
        "Key": "{% 'action-results/' & $gFindingId & '_' & $now('[Y0001]-[M01]-[D01]_[H01]-[m01]-[s01]', '+0900') & '.log' %}"
      },
      "End": true,
      "Resource": "arn:aws:states:::aws-sdk:s3:putObject",
      "Type": "Task"
    }
  }
}
EOF
}