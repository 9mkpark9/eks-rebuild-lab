#!/usr/bin/env bash
# kubeadm 노드가 ECR 에서 이미지를 받을 수 있게, ECR 로그인 정보를 Secret(ecr-pull)으로 넣고
# 네임스페이스의 기본 ServiceAccount 에 붙인다. 배포 파일은 고치지 않아도 된다.
# 이 로그인 정보는 12시간 뒤 만료된다. 그 뒤 새 Pod 가 이미지를 받으려면 이 스크립트를 다시 실행해야 한다 (③ 문서의 한계).
#   v2/k8s/kubeadm/ecr-pull-secret.sh [-n vet2]
set -euo pipefail
NS="${2:-vet2}"
REGION="${AWS_REGION:-ap-northeast-2}"
REG="$(aws sts get-caller-identity --query Account --output text | tr -d '\r').dkr.ecr.$REGION.amazonaws.com"
kubectl -n "$NS" create secret docker-registry ecr-pull --docker-server="$REG" --docker-username=AWS \
    --docker-password="$(aws --region "$REGION" ecr get-login-password)" --dry-run=client -o yaml | kubectl apply -f - > /dev/null
kubectl -n "$NS" patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ecr-pull"}]}' > /dev/null
echo "Secret ecr-pull 을 넣고 $NS 의 기본 ServiceAccount 에 붙였습니다 (12시간 유효)."
