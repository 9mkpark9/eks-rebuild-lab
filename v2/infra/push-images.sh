#!/usr/bin/env bash
# ② 에서 만든 이미지 6개를 ECR(스택 vet2-ecr)에 올린다. 이미지는 이 PC 의 도커에 있어야 한다.
#   v2/infra/push-images.sh
set -euo pipefail
export AWS_PAGER=""
REGION="${AWS_REGION:-ap-northeast-2}"
REG="$(aws sts get-caller-identity --query Account --output text | tr -d '\r').dkr.ecr.$REGION.amazonaws.com"
aws --region "$REGION" ecr get-login-password | docker login --username AWS --password-stdin "$REG" > /dev/null
t0=$(date +%s)
for i in auth:1.0.0 clinic:1.0.0 clinic:1.0.1 reservation:1.0.0 web:1.0.0 db:1.0.0 db:1.1.0; do
    docker tag "vet2-$i" "$REG/vet2-$i"
    docker push -q "$REG/vet2-$i" > /dev/null
    echo "  올림: vet2-$i"
done
echo "  $(( $(date +%s) - t0 ))초"
