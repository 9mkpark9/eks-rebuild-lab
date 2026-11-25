#!/usr/bin/env bash
# overlay 를 렌더해 ECR_REGISTRY 자리에 실제 ECR 주소를, MY_CIDR 자리에 이 PC 의 공인 IP 를,
# RDS_HOST 자리에 RDS 주소를 넣고 적용한다.
# 계정 번호와 IP 는 Git 에 적지 않는다.
#   v2/k8s/apply.sh <overlay 이름> [--render]
#   --render  적용하지 않고 무엇이 적용되는지 보여 준다 (계정 번호와 IP 는 가린다)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OV="$ROOT/v2/k8s/overlays/$1"
command -v cygpath > /dev/null && OV="$(cygpath -m "$OV")"   # Windows 의 kubectl 은 /c/... 경로를 모른다
REG="${ECR_REGISTRY:-$(aws sts get-caller-identity --query Account --output text | tr -d '\r').dkr.ecr.${AWS_REGION:-ap-northeast-2}.amazonaws.com}"
# ALB 를 이 PC 의 IP 에만 연다 (eks overlay 의 ingress.yaml)
MY_CIDR="${MY_CIDR:-$(curl -s -m 8 https://checkip.amazonaws.com | tr -d '\r\n')/32}"
out=$(kubectl kustomize "$OV" | sed -e "s#ECR_REGISTRY#$REG#g" -e "s#MY_CIDR#$MY_CIDR#g")
# DB 를 RDS 로 쓰는 overlay(kubeadm, eks): RDS_HOST 자리에 스택 vet2-rds 의 주소를 넣는다
if printf '%s' "$out" | grep -q RDS_HOST; then
    RDS_HOST="${RDS_HOST:-$(aws --region "${AWS_REGION:-ap-northeast-2}" cloudformation describe-stacks --stack-name vet2-rds \
        --query "Stacks[0].Outputs[?OutputKey=='Endpoint'].OutputValue" --output text | tr -d '\r')}"
    out=$(printf '%s\n' "$out" | sed -e "s#RDS_HOST#$RDS_HOST#g")
fi
if [ "${2:-}" = --render ]; then
    printf '%s\n' "$out" | sed -E -e 's/[0-9]{12}\.dkr/************.dkr/g' -e 's#(inbound-cidrs: ).*#\1(내 IP)/32#'
else
    printf '%s\n' "$out" | kubectl apply -f -
fi
