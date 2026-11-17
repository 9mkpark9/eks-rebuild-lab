#!/usr/bin/env bash
# EKS 용 배포 파일(gitops/apps/vet/overlays/eks)을 적용한다.
#
# ECR 주소(<계정 번호>.dkr.ecr.<리전>.amazonaws.com)에는 AWS 계정 번호가 들어 있어 Git 에 적지 않았다.
# 배포 파일에는 ECR_REGISTRY 라는 자리 표시만 있고, 이 스크립트가 적용하는 순간에 실제 주소로 바꿔 넣는다.
# 계정 번호는 지금 로그인한 AWS 계정에서 읽는다 (aws sts get-caller-identity). 화면에는 가려서 출력한다.
#
#   scripts/eks-apply.sh             적용 (kubectl apply)
#   scripts/eks-apply.sh --render    무엇이 적용되는지 본다. 클러스터에는 손대지 않는다
#   scripts/eks-apply.sh --diff      클러스터에 있는 것과 다른 점을 본다 (kubectl diff)
#   scripts/eks-apply.sh --delete    적용한 것을 지운다. ALB 와 EBS 볼륨도 함께 지워진다
#
# 리전은 AWS_REGION 또는 aws configure 의 값을 쓴다. 주소를 직접 주려면 환경 변수 ECR_REGISTRY 에 넣는다.
set -euo pipefail

MODE="apply"
case "${1:-}" in
    "")        ;;
    --render)  MODE="render" ;;
    --diff)    MODE="diff" ;;
    --delete)  MODE="delete" ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "모르는 옵션: $1" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY="$ROOT/gitops/apps/vet/overlays/eks"

if [ -z "${ECR_REGISTRY:-}" ]; then
    region="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
    [ -n "$region" ] || { echo '리전을 알 수 없습니다. AWS_REGION 을 지정하세요.' >&2; exit 1; }
    account="$(aws sts get-caller-identity --query Account --output text | tr -d '\r')"
    [ -n "$account" ] || { echo 'AWS 계정을 읽지 못했습니다. aws configure 를 확인하세요.' >&2; exit 1; }
    ECR_REGISTRY="$account.dkr.ecr.$region.amazonaws.com"
fi

# 계정 번호(숫자 12자리)를 가린다
mask() { sed -E 's/[0-9]{12}(\.dkr\.ecr\.)/************\1/g'; }

render() {
    local out
    out="$(kubectl kustomize "$OVERLAY" | sed "s|ECR_REGISTRY/|$ECR_REGISTRY/|g")"
    if printf '%s' "$out" | grep -q 'ECR_REGISTRY'; then
        echo '자리 표시 ECR_REGISTRY 가 남아 있습니다. 배포 파일을 확인하세요.' >&2; exit 1
    fi
    printf '%s\n' "$out"
}

echo "이미지를 받을 곳: $(printf '%s' "$ECR_REGISTRY" | mask)" >&2

case "$MODE" in
    render) render | mask ;;
    diff)   render | kubectl diff -f - | mask || true ;;
    delete) render | kubectl delete -f - --ignore-not-found | mask ;;
    apply)  render | kubectl apply -f - | mask ;;
esac
