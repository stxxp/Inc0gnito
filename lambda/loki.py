import json
import gzip
import boto3
import urllib3
from collections import defaultdict
from datetime import datetime

s3 = boto3.client("s3")

LOKI_PUSH_URL = "http://<EC2_PUBLIC_IP>:3100/loki/api/v1/push"

http = urllib3.PoolManager(
    timeout=urllib3.Timeout(connect=5.0, read=5.0)
)

def to_ns(ts):
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        return str(int(dt.timestamp() * 1_000_000_000))
    except:
        import time
        return str(int(time.time() * 1_000_000_000))

def lambda_handler(event, context):

    streams = defaultdict(list)

    for record in event["Records"]:

        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]

        print(f"Processing: s3://{bucket}/{key}")

        # 제외
        if key.startswith("mem-dump/") or key.startswith("outflow/"):
            continue

        obj = s3.get_object(Bucket=bucket, Key=key)

        body = obj["Body"].read()

        # gzip 처리
        if key.endswith(".gz"):
            body = gzip.decompress(body)

        content = body.decode("utf-8").splitlines()

        for line in content:

            if not line.strip():
                continue

            try:
                log = json.loads(line)
            except Exception as e:
                print("JSON parse error:", e)
                continue

            timestamp = to_ns(
                log.get("timestamp")
                or log.get("@timestamp")
                or datetime.utcnow().isoformat()
            )

            # 기본 라벨
            labels = {
                "job": "antifragile",
                "source": "s3",
            }

            # 경로 기준
            if key.startswith("normalized-events/"):
                labels["bucket_path"] = "normalized-events"

            elif key.startswith("action-results/"):
                labels["bucket_path"] = "action-results"

            else:
                labels["bucket_path"] = "other"

            # severity
            if "severity" in log:
                labels["severity"] = str(log["severity"])

            # 서비스
            if "service" in log:
                labels["service"] = str(log["service"])

            # 이벤트 타입
            if "event_type" in log:
                labels["event_type"] = str(log["event_type"])

            # action result
            if "result" in log:
                labels["result"] = str(log["result"])

            stream_key = tuple(sorted(labels.items()))

            streams[stream_key].append([
                timestamp,
                json.dumps(log)
            ])

    loki_streams = []

    for label_tuple, values in streams.items():

        stream_labels = dict(label_tuple)

        loki_streams.append({
            "stream": stream_labels,
            "values": values
        })

    if not loki_streams:
        return {
            "statusCode": 200,
            "body": "No logs"
        }

    payload = {
        "streams": loki_streams
    }

    try:

        response = http.request(
            "POST",
            LOKI_PUSH_URL,
            body=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )

        print("Loki status:", response.status)
        print(response.data.decode())

    except Exception as e:
        print("Loki push failed:", str(e))

    return {
        "statusCode": 200,
        "body": "Done"
    }