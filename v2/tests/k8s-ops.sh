#!/usr/bin/env bash
# 쿠버네티스 운영 동작 측정 (③④ 공통). 요청을 계속 보내는 동안 아래를 하고, 실패한 요청과 걸린 시간을 잰다.
#   1) 다시 배포     web 과 서비스 3개를 차례로 rollout restart
#   2) 업데이트·롤백  clinic 이미지를 다른 태그로 바꿨다가 rollout undo
#   3) 자동 복구     Pod 하나를 지운다
#   4) 데이터 유지   예약을 하나 만들고 DB 를 다시 시작한 뒤 그 예약이 남아 있는지 본다
#                    클러스터 안 MySQL(로컬)이면 그 Pod 를 지우고, 없으면 RDS 를 다시 시작한다 (aws rds reboot-db-instance)
#
#   v2/tests/k8s-ops.sh --base-url http://<주소> -n vet2 --new-clinic-image <이미지:태그> [--context <컨텍스트>] [--only "1 3"]
#
# 결과는 화면에 출력한다. 실패 수의 합을 종료 코드로 돌려준다.
set -u
NS=vet2; BASE=""; CTX=""; NEWIMG=""; ONLY="1 2 3 4"
while [ $# -gt 0 ]; do
    case "$1" in
        --base-url) BASE="${2%/}"; shift 2 ;;
        -n|--namespace) NS="$2"; shift 2 ;;
        --context) CTX="--context $2"; shift 2 ;;
        --new-clinic-image) NEWIMG="$2"; shift 2 ;;
        --only) ONLY="$2"; shift 2 ;;
        *) echo "모르는 옵션: $1" >&2; exit 2 ;;
    esac
done
[ -n "$BASE" ] || { echo "--base-url 이 필요합니다" >&2; exit 2; }
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Windows 의 node 와 curl 은 /c/... 나 /tmp 같은 경로를 모른다. 작업 파일은 저장소 안(Git 에 올라가지 않는 곳)에 두고 C:/... 형식으로 넘긴다
command -v cygpath > /dev/null && DIR="$(cygpath -m "$DIR")"
WORK="$DIR/../_run/ops"; mkdir -p "$WORK"
K="kubectl $CTX -n $NS"
FAILS=0
has() { [[ " $ONLY " == *" $1 "* ]]; }

# 트래픽을 띄우고 명령을 실행한 뒤, 몇 초 더 보내고 멈춘다
with_traffic() { # with_traffic <이름> <명령...>
    local label="$1"; shift
    rm -f "$WORK/stop"
    node "$DIR/traffic.mjs" --base-url "$BASE" --seconds 900 --label "$label" --stop-file "$WORK/stop" > "$WORK/traffic.$$" 2>&1 &
    local tp=$!
    sleep 3
    local s=$(date +%s)
    "$@"
    echo "  작업 시간: $(( $(date +%s) - s ))초"
    sleep 5
    touch "$WORK/stop"; wait $tp; local e=$?
    sed 's/^/  /' "$WORK/traffic.$$"; rm -f "$WORK/traffic.$$"
    [ $e = 0 ] || FAILS=$((FAILS + 1))
}

restart_all() { for d in web auth clinic reservation; do $K rollout restart deploy/$d > /dev/null; $K rollout status deploy/$d --timeout=180s > /dev/null || echo "  $d: 180초 안에 끝나지 않음"; done; }
update_rollback() {
    local old; old=$($K get deploy clinic -o jsonpath='{.spec.template.spec.containers[0].image}')
    $K set image deploy/clinic clinic="$NEWIMG" > /dev/null; $K rollout status deploy/clinic --timeout=180s > /dev/null
    sleep 3; echo "  업데이트 뒤 clinic 버전: $(curl -s -m 5 "$BASE/api/status/clinic" | grep -o '"version":"[^"]*"')"
    $K rollout undo deploy/clinic > /dev/null; $K rollout status deploy/clinic --timeout=180s > /dev/null
    sleep 3; echo "  롤백 뒤 clinic 버전:   $(curl -s -m 5 "$BASE/api/status/clinic" | grep -o '"version":"[^"]*"') (이미지 $old)"
}
delete_pod() { # delete_pod <앱>
    local p; p=$($K get pod -l app=$1 -o jsonpath='{.items[0].metadata.name}')
    $K delete pod "$p" --wait=false > /dev/null
    local s=$(date +%s)
    for _ in $(seq 1 180); do
        local n; n=$($K get deploy $1 -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        local want; want=$($K get deploy $1 -o jsonpath='{.spec.replicas}')
        [ "${n:-0}" = "$want" ] && [ -z "$($K get pod "$p" --ignore-not-found -o name)" ] && break
        sleep 1
    done
    echo "  $1 Pod 를 지운 뒤 준비된 복제본이 원래 수로 돌아오기까지 $(( $(date +%s) - s ))초"
}

if has 1; then echo "■ 1. 다시 배포 (web, auth, clinic, reservation 차례로)"; with_traffic "다시 배포" restart_all; fi
if has 2; then
    if [ -n "$NEWIMG" ]; then echo "■ 2. 업데이트와 롤백 (clinic → $NEWIMG → 되돌림)"; with_traffic "업데이트·롤백" update_rollback
    else echo "■ 2. 건너뜀 (--new-clinic-image 없음)"; fi
fi
if has 3; then
    for a in web reservation; do echo "■ 3. 자동 복구 ($a Pod 하나 삭제)"; with_traffic "$a 삭제" delete_pod $a; done
fi
if has 4; then
    echo "■ 4. 데이터 유지 (예약을 만들고 DB 를 다시 시작한다)"
    J="$WORK/cookie.txt"
    curl -s -o /dev/null -c "$J" -H 'Content-Type: application/json' -d '{"loginId":"owner290","password":"test-only"}' "$BASE/api/auth/login"
    PET=$(curl -s -b "$J" "$BASE/api/pets" | grep -o '"petId":[0-9]*' | head -1 | cut -d: -f2)
    RID=""
    for n in 2 3 4 5 6 7 8; do
        D=$(date -d "+$n day" +%F); [ "$(date -d "+$n day" +%u)" = 7 ] && continue
        SLOT=$(curl -s "$BASE/api/slots?date=$D&type=CHECKUP" | grep -o '"slotId":[0-9]*' | head -1 | cut -d: -f2)
        [ -n "$SLOT" ] || continue
        RID=$(curl -s -b "$J" -H 'Content-Type: application/json' -d "{\"petId\":$PET,\"slotId\":$SLOT}" "$BASE/api/reservations" | grep -o '"reservationId":[0-9]*' | cut -d: -f2)
        [ -n "$RID" ] && break
    done
    echo "  만든 예약: ${RID:-만들지 못함} ($D)"
    R="aws --region ${AWS_REGION:-ap-northeast-2} rds"
    P=$($K get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$P" ]; then
        WHAT="MySQL Pod 삭제"; RESTART="$K delete pod $P > /dev/null"
    else
        # RDS: 재시작 명령은 바로 돌아오고, DB 가 실제로 내려가는 것은 그 뒤다.
        # 그래서 다시 available 이 될 때까지 기다린 다음에 응답을 본다 (곧바로 보면 내려가기 전의 200 을 보게 된다)
        WHAT="RDS 재시작"; RESTART="$R reboot-db-instance --db-instance-identifier vet2-db --query DBInstance.DBInstanceStatus --output text; sleep 5; $R wait db-instance-available --db-instance-identifier vet2-db; echo \"  명령부터 DB 가 다시 available 이 되기까지 \$(( \$(date +%s) - s ))초\""
    fi
    with_traffic "$WHAT" bash -c "s=\$(date +%s); $RESTART; until [ \"\$(curl -s -m 3 -o /dev/null -w '%{http_code}' $BASE/api/notices)\" = 200 ]; do sleep 1; [ \$(( \$(date +%s) - s )) -gt 900 ] && break; done; echo \"  명령부터 공지 조회가 다시 200 이 되기까지 \$(( \$(date +%s) - s ))초\""
    curl -s -o /dev/null -c "$J" -H 'Content-Type: application/json' -d '{"loginId":"owner290","password":"test-only"}' "$BASE/api/auth/login"
    # 예약 조회가 200 으로 답할 때까지 기다린 뒤 확인한다. DB 가 돌아오기 전에 보면 "없다"로 잘못 나온다
    for _ in $(seq 1 60); do [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -b "$J" "$BASE/api/reservations/me")" = 200 ] && break; sleep 2; done
    ST=$(curl -s -b "$J" "$BASE/api/reservations/me" | grep -o "\"reservationId\":$RID,[^}]*" | grep -o '"status":"[A-Z]*"')
    if [ -n "$RID" ] && [ -n "$ST" ]; then echo "  [통과] $WHAT 뒤에도 예약 $RID 가 남아 있다 ($ST)"; curl -s -o /dev/null -b "$J" -X DELETE "$BASE/api/reservations/$RID"
    else echo "  [실패] $WHAT 뒤 예약 ${RID:-?} 가 없다"; FAILS=$((FAILS + 1)); fi
fi
echo; echo "실패한 항목: $FAILS"
exit $FAILS
