#!/usr/bin/env bash
# 쿠버네티스에 필요한 Secret 을 만든다. Secret 은 Git 에 넣지 않으므로 클러스터마다 이 스크립트로 넣는다.
# 비밀번호는 무작위로 만들고 화면에 출력하지 않는다. 이미 있는 Secret 은 건드리지 않는다.
#
#   DB 가 클러스터 안의 MySQL Pod 일 때:
#     scripts/new-k8s-secrets.sh -n vet
#
#   DB 가 클러스터 밖(예: RDS)일 때:
#     관리자 비밀번호는 명령줄에 적지 않고 환경 변수 VET_DB_ADMIN_PASSWORD 로 준다.
#     read -rs VET_DB_ADMIN_PASSWORD && export VET_DB_ADMIN_PASSWORD
#     scripts/new-k8s-secrets.sh -n vet --external-db-host <RDS 주소> --external-db-admin-user <관리자 계정>
#
# 만드는 Secret
#   vet-db            root-password, auth-password, clinic-password, reservation-password
#   vet-redis         password
#   vet-db-external   host, admin-user, admin-password        (--external-db-host 를 줬을 때만)
set -u

NAMESPACE="vet"
EXT_HOST=""
EXT_USER=""

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--namespace)            NAMESPACE="$2"; shift 2 ;;
        --external-db-host)        EXT_HOST="$2"; shift 2 ;;
        --external-db-admin-user)  EXT_USER="$2"; shift 2 ;;
        -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "모르는 옵션: $1" >&2; exit 2 ;;
    esac
done

# 무작위 36자 (16진수)
new_secret() { head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
has_secret() { kubectl -n "$NAMESPACE" get secret "$1" >/dev/null 2>&1; }

# 네임스페이스가 없으면 만든다 (있으면 그대로)
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    kubectl create namespace "$NAMESPACE" >/dev/null || exit 1
    echo "네임스페이스 $NAMESPACE 를 만들었습니다."
fi

if has_secret vet-db; then
    echo 'vet-db 는 이미 있습니다. 바꾸지 않았습니다.'
else
    kubectl -n "$NAMESPACE" create secret generic vet-db \
        "--from-literal=root-password=$(new_secret)" \
        "--from-literal=auth-password=$(new_secret)" \
        "--from-literal=clinic-password=$(new_secret)" \
        "--from-literal=reservation-password=$(new_secret)" >/dev/null || exit 1
    echo 'vet-db 를 만들었습니다 (비밀번호 4개).'
fi

if has_secret vet-redis; then
    echo 'vet-redis 는 이미 있습니다. 바꾸지 않았습니다.'
else
    kubectl -n "$NAMESPACE" create secret generic vet-redis "--from-literal=password=$(new_secret)" >/dev/null || exit 1
    echo 'vet-redis 를 만들었습니다.'
fi

if [ -n "$EXT_HOST" ]; then
    [ -n "$EXT_USER" ] || { echo '--external-db-admin-user 가 필요합니다.' >&2; exit 1; }
    [ -n "${VET_DB_ADMIN_PASSWORD:-}" ] || { echo '환경 변수 VET_DB_ADMIN_PASSWORD 에 바깥 DB 의 관리자 비밀번호를 넣고 다시 실행하세요.' >&2; exit 1; }
    if has_secret vet-db-external; then
        echo 'vet-db-external 은 이미 있습니다. 바꾸지 않았습니다.'
    else
        kubectl -n "$NAMESPACE" create secret generic vet-db-external \
            "--from-literal=host=$EXT_HOST" \
            "--from-literal=admin-user=$EXT_USER" \
            "--from-literal=admin-password=$VET_DB_ADMIN_PASSWORD" >/dev/null || exit 1
        echo 'vet-db-external 을 만들었습니다.'
    fi
fi

# 이름과 키만 보여 준다. 값은 출력하지 않는다.
echo
for name in vet-db vet-redis vet-db-external; do
    if has_secret "$name"; then
        keys=$(kubectl -n "$NAMESPACE" get secret "$name" -o go-template='{{range $k, $v := .data}}{{$k}} {{end}}')
        echo "$name: $keys"
    fi
done
