#!/usr/bin/env bash
# 쿠버네티스에 Secret 두 개(vet-db, vet-redis)를 넣는다. 값은 v2/_run/secrets.env 에서 읽는다 (Git 에 없음).
# 배포 파일에 비밀번호를 적지 않기 위해 따로 넣는다. 이미 있으면 바꿔 쓴다.
#
#   v2/k8s/secrets.sh -n vet2 [--context docker-desktop]
set -euo pipefail
NS=vet2; CTX=""
while [ $# -gt 0 ]; do
    case "$1" in
        -n) NS="$2"; shift 2 ;;
        --context) CTX="--context $2"; shift 2 ;;
        *) echo "모르는 옵션: $1" >&2; exit 2 ;;
    esac
done
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/v2/_run/secrets.env"
K="kubectl $CTX -n $NS"
kubectl $CTX get ns "$NS" > /dev/null 2>&1 || kubectl $CTX create ns "$NS" > /dev/null
# 파일을 만들지 않고 내용을 바로 apply 로 넘긴다. 값은 화면과 파일에 남지 않는다.
$K create secret generic vet-db \
    --from-literal=root-password="$DB_ROOT_PASSWORD" \
    --from-literal=auth-password="$DB_AUTH_PASSWORD" \
    --from-literal=clinic-password="$DB_CLINIC_PASSWORD" \
    --from-literal=reservation-password="$DB_RESERVATION_PASSWORD" \
    --dry-run=client -o yaml | $K apply -f - > /dev/null
$K create secret generic vet-redis --from-literal=password="$REDIS_PASSWORD" \
    --dry-run=client -o yaml | $K apply -f - > /dev/null
echo "Secret vet-db, vet-redis 를 $NS 에 넣었습니다."
