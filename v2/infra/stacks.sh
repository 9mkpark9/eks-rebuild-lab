#!/usr/bin/env bash
# vet2 의 AWS 자원을 CloudFormation 스택 5개로 만들고 지운다.
#
#   v2/infra/stacks.sh up <network|ecr|kubeadm|eks|rds|all>     만들기 (이미 있으면 바뀐 것만 고친다)
#   v2/infra/stacks.sh down <rds|eks|kubeadm|ecr|network|all>   지우기 (되돌릴 수 없다)
#   v2/infra/stacks.sh status                               스택 5개의 상태
#   v2/infra/stacks.sh validate                             템플릿 문법 검사 (AWS 에 아무것도 만들지 않는다)
#
# 순서: 만들 때 network → ecr → kubeadm, eks → rds.  지울 때 거꾸로.
# rds 는 노드 보안 그룹 두 개(network 의 vet2-NodeSg, eks 의 vet2-EksClusterSg)를 쓴다. rds 가 남아 있으면 eks 는 지워지지 않는다.
# kubeadm 과 eks 는 network 가 내보내는 값(vet2-SubnetA 등)을 쓴다. 그 둘이 남아 있으면 network 는 지워지지 않는다.
# MyCidr(웹·API 를 열어 줄 주소)는 이 PC 의 공인 IP 로 채운다. 바꾸려면 MY_CIDR 환경 변수로 준다.
set -euo pipefail
REGION="${AWS_REGION:-ap-northeast-2}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v cygpath > /dev/null && DIR="$(cygpath -m "$DIR")"   # Windows 의 aws 는 /c/... 경로를 모른다
# Windows 의 AWS CLI 는 파일을 시스템 문자 집합(CP949)으로 읽는다. 템플릿의 한글 주석 때문에 UTF-8 로 읽게 한다.
export AWS_CLI_FILE_ENCODING=UTF-8 AWS_PAGER=""
CF="aws --region $REGION cloudformation"
MY_CIDR="${MY_CIDR:-$(curl -s -m 8 https://checkip.amazonaws.com | tr -d '\r\n')/32}"

params() { case "$1" in network|eks) echo "MyCidr=$MY_CIDR" ;; esac; }

up() {
    local s="$1" p
    p="$(params "$s")"
    echo "■ vet2-$s 만들기 / 고치기"
    local t0=$(date +%s)
    $CF deploy --stack-name "vet2-$s" --template-file "$DIR/$s.yaml" \
        --capabilities CAPABILITY_NAMED_IAM --tags Project=vet2 --no-fail-on-empty-changeset \
        ${p:+--parameter-overrides "$p"}
    echo "  $(( $(date +%s) - t0 ))초"
}

down() {
    local s="$1"
    if [ "$s" = eks ] && $CF describe-stacks --stack-name vet2-eks > /dev/null 2>&1; then
        # ALB 와 MySQL 의 EBS 는 클러스터 안의 Ingress 와 PVC 가 만든 것이라 스택에 들어 있지 않다.
        # 클러스터를 먼저 지우면 그것을 지워 줄 주체가 사라져 남는다. 그래서 먼저 지운다 (⑤ 6.2).
        echo "■ EKS 안의 vet2, vet2-rds 네임스페이스를 먼저 지운다 (ALB 2개, EBS)"
        local kc; kc="$(mktemp)"
        aws --region "$REGION" eks update-kubeconfig --name vet2-eks --kubeconfig "$kc" > /dev/null
        command -v cygpath > /dev/null && kc="$(cygpath -m "$kc")"
        kubectl --kubeconfig "$kc" delete namespace vet2 vet2-rds --ignore-not-found --wait=true --timeout=10m || true
        rm -f "$kc"
    fi
    echo "■ vet2-$s 지우기"
    local t0=$(date +%s)
    $CF delete-stack --stack-name "vet2-$s"
    $CF wait stack-delete-complete --stack-name "vet2-$s"
    echo "  $(( $(date +%s) - t0 ))초"
}

case "${1:-}" in
    up)
        case "${2:-}" in
            all) for s in network ecr kubeadm eks rds; do up "$s"; done ;;
            network|ecr|kubeadm|eks|rds) up "$2" ;;
            *) echo "up <network|ecr|kubeadm|eks|rds|all>" >&2; exit 2 ;;
        esac ;;
    down)
        case "${2:-}" in
            all) for s in rds eks kubeadm ecr network; do down "$s"; done ;;
            network|ecr|kubeadm|eks|rds) down "$2" ;;
            *) echo "down <rds|eks|kubeadm|ecr|network|all>" >&2; exit 2 ;;
        esac ;;
    status)
        for s in network ecr kubeadm eks rds; do
            printf '%-14s %s\n' "vet2-$s" "$($CF describe-stacks --stack-name "vet2-$s" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo 없음)"
        done ;;
    validate)
        for s in network ecr kubeadm eks rds; do
            printf '%-12s ' "$s.yaml"
            $CF validate-template --template-body "file://$DIR/$s.yaml" --query 'Description' --output text
        done ;;
    *) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
