#!/bin/bash
# WEB 시작 템플릿 사용자 데이터 — 콘솔용 (docs/07 6-5). 내용은 cfn/web.yaml 의 WEB 사용자 데이터(부록 E.2)와 같다.
# 시작 템플릿 「고급 세부 정보 → 사용자 데이터」에 파일 전체를 붙여 넣는다.
# ▼ 아래 2줄만 내 값으로 바꾼다 (<...> 를 지우고 값만 남긴다)
ARTIFACT_BUCKET="vet01-artifacts-<계정ID 12자리>"
INTERNAL_ALB_DNS="<내부 ALB DNS 이름>"   # 예: internal-vet01-alb-int-1234567890.ap-northeast-2.elb.amazonaws.com
# ▲
set -euo pipefail
REGION="ap-northeast-2"
CLIENT="vet01"
APP_VERSION="1.0.0"
case "$ARTIFACT_BUCKET$INTERNAL_ALB_DNS" in *"<"*) echo "사용자 데이터의 <...> 값을 바꾸지 않았습니다" >&2; exit 1 ;; esac

dnf install -y nginx amazon-cloudwatch-agent
aws s3 cp "s3://$ARTIFACT_BUCKET/web/vet-web-$APP_VERSION.tar.gz" /tmp/web.tgz --region "$REGION"
rm -rf /usr/share/nginx/vet && mkdir -p /usr/share/nginx/vet
tar -xzf /tmp/web.tgz -C /usr/share/nginx/vet      # site/(소개 HTML) + app/(예약·직원 SPA)
aws s3 cp "s3://$ARTIFACT_BUCKET/web/nginx.conf" /etc/nginx/nginx.conf --region "$REGION"
sed -i "s/__INTERNAL_ALB_DNS__/$INTERNAL_ALB_DNS/" /etc/nginx/nginx.conf
nginx -t

cat > /etc/vet-cwagent.json <<CW
{
  "metrics": {
    "append_dimensions": { "AutoScalingGroupName": "\${aws:AutoScalingGroupName}" },
    "aggregation_dimensions": [["AutoScalingGroupName"]],
    "metrics_collected": { "mem": { "measurement": ["mem_used_percent"] } }
  },
  "logs": { "logs_collected": { "files": { "collect_list": [
    { "file_path": "/var/log/nginx/access.log", "log_group_name": "/$CLIENT/web-access", "log_stream_name": "{instance_id}" },
    { "file_path": "/var/log/nginx/error.log", "log_group_name": "/$CLIENT/web-error", "log_stream_name": "{instance_id}" }
  ] } } }
}
CW
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/etc/vet-cwagent.json -s || true
systemctl enable --now nginx
