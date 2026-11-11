#!/bin/bash
# WAS 시작 템플릿 사용자 데이터 — 콘솔용 (docs/07 5-6). 내용은 cfn/was.yaml 의 WAS 사용자 데이터(부록 E.1)와 같다.
# 시작 템플릿 「고급 세부 정보 → 사용자 데이터」에 파일 전체를 붙여 넣는다. 비밀번호는 넣지 않는다.
# ▼ 아래 3줄만 내 값으로 바꾼다 (<...> 를 지우고 값만 남긴다)
ARTIFACT_BUCKET="vet01-artifacts-<계정ID 12자리>"
DB_HOST="<RDS 엔드포인트>"                  # 예: vet01-db.abcdefghijkl.ap-northeast-2.rds.amazonaws.com
REDIS_HOST="<ElastiCache 기본 엔드포인트>"   # 예: master.vet01-cache.abcdef.apn2.cache.amazonaws.com (:6379 는 빼고)
# ▲
set -euo pipefail
REGION="ap-northeast-2"
CLIENT="vet01"
APP_VERSION="1.0.0"
case "$ARTIFACT_BUCKET$DB_HOST$REDIS_HOST" in *"<"*) echo "사용자 데이터의 <...> 값을 바꾸지 않았습니다" >&2; exit 1 ;; esac

dnf install -y java-21-amazon-corretto-headless amazon-cloudwatch-agent jq
id vet >/dev/null 2>&1 || useradd --system --home-dir /opt/vet --shell /sbin/nologin vet
mkdir -p /opt/vet /var/log/vet
aws s3 cp "s3://$ARTIFACT_BUCKET/was/vet-api-$APP_VERSION.jar" /opt/vet/vet-api.jar --region "$REGION"

# 비밀이 아닌 설정
cat > /opt/vet/app.conf <<CONF
export REGION="$REGION"
export DB_SECRET_ID="$CLIENT/db/app"
export REDIS_SECRET_ID="$CLIENT/redis/auth"
export SPRING_DATASOURCE_URL="jdbc:mysql://$DB_HOST:3306/vet?connectionTimeZone=LOCAL&characterEncoding=UTF-8"
export SPRING_DATA_REDIS_HOST="$REDIS_HOST"
export SPRING_DATA_REDIS_PORT="6379"
CONF

# 시작할 때마다 Secrets Manager에서 읽어 프로세스 환경 변수로만 넘긴다 (디스크에 남기지 않음)
cat > /opt/vet/start.sh <<'START'
#!/bin/bash
set -euo pipefail
. /opt/vet/app.conf
db=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$DB_SECRET_ID" --query SecretString --output text)
redis=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$REDIS_SECRET_ID" --query SecretString --output text)
export SPRING_DATASOURCE_USERNAME="$(jq -r .username <<<"$db")"
export SPRING_DATASOURCE_PASSWORD="$(jq -r .password <<<"$db")"
export SPRING_DATA_REDIS_PASSWORD="$(jq -r .token <<<"$redis")"
exec java -Xms1g -Xmx2g -Duser.timezone=Asia/Seoul -jar /opt/vet/vet-api.jar --logging.file.name=/var/log/vet/app.log
START
chmod 750 /opt/vet/start.sh
chown -R vet:vet /opt/vet /var/log/vet

cat > /etc/systemd/system/vet-api.service <<'UNIT'
[Unit]
Description=Vet reservation API
After=network-online.target
Wants=network-online.target
[Service]
User=vet
ExecStart=/opt/vet/start.sh
Restart=on-failure
RestartSec=5
SuccessExitStatus=143
[Install]
WantedBy=multi-user.target
UNIT

# 메모리 지표와 앱 로그를 CloudWatch로
cat > /opt/vet/cwagent.json <<CW
{
  "metrics": {
    "append_dimensions": { "AutoScalingGroupName": "\${aws:AutoScalingGroupName}" },
    "aggregation_dimensions": [["AutoScalingGroupName"]],
    "metrics_collected": { "mem": { "measurement": ["mem_used_percent"] } }
  },
  "logs": { "logs_collected": { "files": { "collect_list": [
    { "file_path": "/var/log/vet/app.log", "log_group_name": "/$CLIENT/was", "log_stream_name": "{instance_id}" }
  ] } } }
}
CW
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/vet/cwagent.json -s || true
systemctl daemon-reload
systemctl enable --now vet-api
