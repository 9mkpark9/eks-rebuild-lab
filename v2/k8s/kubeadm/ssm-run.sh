#!/usr/bin/env bash
# EC2 에 SSH 없이 명령을 보내고(Session Manager), 끝날 때까지 기다려 출력을 보여 준다.
#
#   v2/k8s/kubeadm/ssm-run.sh <인스턴스 ID> '<명령>' [제한 시간(초), 기본 600]
#
# 성공하면 0, 실패하면 1 을 돌려준다. 출력이 길면 앞뒤만 보인다(AWS 가 24000자에서 자른다).
set -u
ID="$1"; CMD="$2"; LIMIT="${3:-600}"
export AWS_PAGER="" MSYS_NO_PATHCONV=1
A="aws --region ${AWS_REGION:-ap-northeast-2}"
# 명령을 JSON 문자열로 감싼다 (따옴표, 줄바꿈 처리)
PARAMS=$(node -e 'process.stdout.write(JSON.stringify({commands: [process.argv[1]], executionTimeout: [process.argv[2]]}))' "$CMD" "$LIMIT")
CID=$($A ssm send-command --instance-ids "$ID" --document-name AWS-RunShellScript --parameters "$PARAMS" --query Command.CommandId --output text) || exit 1
for _ in $(seq 1 $(( LIMIT / 3 + 10 ))); do
    sleep 3
    ST=$($A ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query Status --output text 2>/dev/null)
    case "$ST" in Success|Failed|TimedOut|Cancelled) break ;; esac
done
$A ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query StandardOutputContent --output text
ERR=$($A ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query StandardErrorContent --output text)
[ -n "$ERR" ] && [ "$ERR" != "None" ] && printf '[stderr]\n%s\n' "$ERR"
[ "$ST" = Success ]
