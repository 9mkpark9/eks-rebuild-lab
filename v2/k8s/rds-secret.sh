#!/usr/bin/env bash
# RDS 관리자 계정을 Secret vet-rds-admin 으로 넣는다. Job db-init 만 쓴다 (앱은 서비스 계정을 쓴다).
# 비밀번호는 RDS 가 만들어 Secrets Manager 에 둔 것을 읽어 바로 kubectl 로 넘긴다. 화면과 파일에 남지 않는다.
#   v2/k8s/rds-secret.sh [-n vet2-rds]
set -euo pipefail
NS="${2:-vet2-rds}"
REGION="${AWS_REGION:-ap-northeast-2}"
export AWS_PAGER=""
ARN=$(aws --region "$REGION" cloudformation describe-stacks --stack-name vet2-rds \
    --query "Stacks[0].Outputs[?OutputKey=='AdminSecretArn'].OutputValue" --output text | tr -d '\r')
# 값은 {"username":"admin","password":"..."} 모양의 JSON 이다
JSON=$(aws --region "$REGION" secretsmanager get-secret-value --secret-id "$ARN" --query SecretString --output text)
kubectl get ns "$NS" > /dev/null 2>&1 || kubectl create ns "$NS" > /dev/null
kubectl -n "$NS" create secret generic vet-rds-admin \
    --from-literal=username="$(printf '%s' "$JSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).username))')" \
    --from-literal=password="$(printf '%s' "$JSON" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).password))')" \
    --dry-run=client -o yaml | kubectl apply -f - > /dev/null
echo "Secret vet-rds-admin 을 $NS 에 넣었습니다."
