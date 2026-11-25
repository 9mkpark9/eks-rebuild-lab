#!/usr/bin/env bash
# Pod 를 모두 바꿔도 데이터가 남는지 본다.
#   1) 시험 계정으로 예약을 하나 만든다
#   2) 앱 Pod(web, auth, clinic, reservation)를 모두 지운다. --with-db 면 DB Pod(mysql-0)도 지운다
#   3) 모두 다시 준비되면 그 예약이 그대로 있는지 확인하고, 예약을 취소해 원래대로 돌린다
#
#   v2/tests/pod-replace-check.sh --base-url http://<주소> -n vet2 [--with-db]
set -u
NS=vet2; BASE=""; WITH_DB=0
while [ $# -gt 0 ]; do
    case "$1" in
        --base-url) BASE="${2%/}"; shift 2 ;;
        -n) NS="$2"; shift 2 ;;
        --with-db) WITH_DB=1; shift ;;
        *) echo "모르는 옵션: $1" >&2; exit 2 ;;
    esac
done
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; mkdir -p "$ROOT/v2/_run/ops"
J="$ROOT/v2/_run/ops/pod-replace-cookie.txt"; command -v cygpath > /dev/null && J="$(cygpath -m "$J")"   # Windows 의 curl 은 /tmp 경로를 모른다
trap 'rm -f "$J"' EXIT
login() { curl -s -o /dev/null -c "$J" -H 'Content-Type: application/json' -d '{"loginId":"owner290","password":"test-only"}' "$BASE/api/auth/login"; }

login
PET=$(curl -s -b "$J" "$BASE/api/pets" | grep -o '"petId":[0-9]*' | head -1 | cut -d: -f2)
RID=""
for n in 2 3 4 5 6 7 8; do
    D=$(date -d "+$n day" +%F); [ "$(date -d "+$n day" +%u)" = 7 ] && continue
    SLOT=$(curl -s "$BASE/api/slots?date=$D&type=CHECKUP" | grep -o '"slotId":[0-9]*' | head -1 | cut -d: -f2)
    [ -n "$SLOT" ] || continue
    RID=$(curl -s -b "$J" -H 'Content-Type: application/json' -d "{\"petId\":$PET,\"slotId\":$SLOT}" "$BASE/api/reservations" | grep -o '"reservationId":[0-9]*' | cut -d: -f2)
    [ -n "$RID" ] && break
done
echo "1) 만든 예약: ${RID:-만들지 못함} ($D)"
[ -n "$RID" ] || exit 1

echo "2) 지우기 전 Pod"
kubectl -n "$NS" get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,STARTED:.status.startTime --no-headers | grep -v 'db-init\|db-client'
SEL='app in (web,auth,clinic,reservation)'
[ $WITH_DB = 1 ] && SEL='app in (web,auth,clinic,reservation,mysql)'
t0=$(date +%s)
kubectl -n "$NS" delete pod -l "$SEL" --wait=false
for d in web auth clinic reservation; do kubectl -n "$NS" rollout status deploy/$d --timeout=300s > /dev/null; done
[ $WITH_DB = 1 ] && kubectl -n "$NS" rollout status sts/mysql --timeout=300s > /dev/null
# Pod 가 준비된 뒤에도 Service 에 붙기까지 잠깐 걸린다. 예약 조회가 200 이 될 때까지 기다린다
login
for _ in $(seq 1 60); do [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -b "$J" "$BASE/api/reservations/me")" = 200 ] && break; sleep 2; login; done
echo "3) 모두 다시 준비되기까지 $(( $(date +%s) - t0 ))초. 새 Pod:"
kubectl -n "$NS" get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,STARTED:.status.startTime --no-headers | grep -v 'db-init\|db-client'
ST=$(curl -s -b "$J" "$BASE/api/reservations/me" | grep -o "\"reservationId\":$RID,[^}]*" | grep -o '"status":"[A-Z]*"')
if [ -n "$ST" ]; then
    echo "[통과] Pod 를 모두 바꾼 뒤에도 예약 $RID 가 남아 있다 ($ST)"
    curl -s -o /dev/null -b "$J" -X DELETE "$BASE/api/reservations/$RID"; echo "   (시험 예약 $RID 취소)"
else
    echo "[실패] Pod 를 모두 바꾼 뒤 예약 $RID 가 없다"; exit 1
fi
