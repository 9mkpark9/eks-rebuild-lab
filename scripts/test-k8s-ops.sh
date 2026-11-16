#!/usr/bin/env bash
# 보듬 동물병원 — 쿠버네티스 운영 동작 확인 (과제 ③ ④)
# smoke.sh 가 "기능이 되는가"를 본다면, 이 스크립트는 쿠버네티스에서만 볼 수 있는 운영 동작을 잰다.
#   1) 무중단 배포     요청을 계속 보내는 동안 web 과 서비스 3개를 차례로 다시 배포한다
#   2) 업데이트와 롤백  clinic 의 버전을 바꿔 배포하고(롤링 업데이트), 되돌린다(rollout undo)
#                      1)과 2) 동안 실패한 요청 수를 센다
#   3) 자동 복구       Pod 하나를 지우고, 그동안 응답이 끊기는지와 복제본 수가 돌아오는 시간을 잰다
#   4) 데이터 유지     예약을 하나 만들고 MySQL Pod 를 지운 뒤, 새 Pod 에서 그 예약이 남아 있는지 본다.
#                      DB 가 끊긴 시간도 잰다
#
#   scripts/test-k8s-ops.sh --base-url http://<주소> --namespace vet
#
# --skip-db   4)를 건너뛴다 (DB 가 클러스터 밖에 있어 mysql Pod 가 없을 때)
# --compare   끝난 뒤 비교용으로, reservation 을 "전부 내리고 다시 띄우는" 방식(Recreate)으로 한 번 배포해
#             실패한 요청 수를 센다. 무중단 설정이 없을 때 어떻게 되는지 보여 준다. 끝나면 원래 설정으로 되돌린다.
# 끝나면 실패 수를 종료 코드로 돌려준다.
set -u

NAMESPACE="vet"
BASE_URL="http://localhost"
PASSWORD="test-only"
SKIP_DB=0
COMPARE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --base-url)      BASE_URL="$2"; shift 2 ;;
        --namespace|-n)  NAMESPACE="$2"; shift 2 ;;
        --password)      PASSWORD="$2"; shift 2 ;;
        --skip-db)       SKIP_DB=1; shift ;;
        --compare)       COMPARE=1; shift ;;
        -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "모르는 옵션: $1" >&2; exit 2 ;;
    esac
done
BASE_URL="${BASE_URL%/}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
report() {      # report 0|1 이름 설명   (0 = 통과)
    if [ "$1" = 0 ]; then PASS=$((PASS + 1)); printf '[통과] %s — %s\n' "$2" "$3"
    else FAIL=$((FAIL + 1)); printf '[실패] %s — %s\n' "$2" "$3"; fi
}

k() { MSYS_NO_PATHCONV=1 kubectl -n "$NAMESPACE" "$@"; }
kst() { date -u -d "@$(( $(date +%s) + 9 * 3600 ))" "+$1"; }
now_ms() { echo $(( $(date +%s%N) / 1000000 )); }
secs() { awk -v ms="$1" 'BEGIN { printf "%.1f", ms / 1000 }'; }

http_status() { curl -s -m 3 -o /dev/null -w '%{http_code}' ${2:+-b "$2"} "$BASE_URL$1" 2>/dev/null || true; }
# 200 으로 답한 Pod 의 이름 (서비스는 X-Served-By, web 은 X-Web-Node). 200 이 아니면 빈 문자열
responder() {
    curl -s -m 3 -D "$WORK/h" -o /dev/null "$BASE_URL$1" 2>/dev/null || return 0
    head -1 "$WORK/h" | grep -q ' 200' || return 0
    grep -i "^$2:" "$WORK/h" | tail -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//'
}
status_version() { curl -s -m 3 "$BASE_URL/api/status/$1" 2>/dev/null | grep -oE '"version":"[^"]*"' | cut -d'"' -f4; }

pods() { k get pods -l "app=$1" -o 'jsonpath={.items[*].metadata.name}' 2>/dev/null; }
restarts() { k get pods -l "app=$1" -o 'jsonpath={.items[*].status.containerStatuses[0].restartCount}' 2>/dev/null | tr ' ' '+'; }
revision() { k get deployment "$1" -o 'jsonpath={.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null; }
# Pod 가 새것인지는 이름이 아니라 만든 시각으로 본다 (StatefulSet 의 Pod 는 다시 떠도 이름이 같다)
born() { k get pods -l "app=$1" -o 'jsonpath={.items[*].metadata.creationTimestamp}' 2>/dev/null; }
wait_gone() { local name; for name in $1; do k wait --for=delete "pod/$name" --timeout=120s >/dev/null 2>&1; done; }

# 조건이 참이 될 때까지 걸린 시간(ms)을 ELAPSED 에 넣는다. 시간 안에 안 되면 실패를 돌려준다.
ELAPSED=0
measure_until() {       # measure_until 초 명령...
    local limit="$1" start; shift
    start=$(now_ms)
    while :; do
        if "$@"; then ELAPSED=$(( $(now_ms) - start )); return 0; fi
        if [ $(( $(now_ms) - start )) -ge $(( limit * 1000 )) ]; then ELAPSED=$(( $(now_ms) - start )); return 1; fi
        sleep 0.3
    done
}

# 요청을 계속 보내는 Pod. 이미지는 지금 떠 있는 web 의 것을 그대로 쓴다.
loadgen_start() {
    local image
    image=$(k get deployment web -o 'jsonpath={.spec.template.spec.containers[0].image}')
    k delete pod loadgen --ignore-not-found --wait=true >/dev/null 2>&1
    sed "s|image: vet-web\$|image: $image|" "$ROOT/scripts/k8s/loadgen.yaml" | k apply -f - >/dev/null
    k wait --for=condition=Ready pod/loadgen --timeout=120s >/dev/null 2>&1
}
LG_TOTAL=0; LG_FAIL=-1
loadgen_stop() {
    local line
    k exec loadgen -- touch /tmp/stop >/dev/null 2>&1
    k wait '--for=jsonpath={.status.phase}=Succeeded' pod/loadgen --timeout=60s >/dev/null 2>&1
    k logs loadgen > "$WORK/loadgen.log" 2>/dev/null
    line=$(grep -E '^RESULT total=[0-9]+ fail=[0-9]+' "$WORK/loadgen.log" | tail -1)
    LG_TOTAL=0; LG_FAIL=-1
    if [ -n "$line" ]; then
        LG_TOTAL=$(printf '%s' "$line" | sed -E 's/.*total=([0-9]+).*/\1/')
        LG_FAIL=$(printf '%s' "$line" | sed -E 's/.*fail=([0-9]+).*/\1/')
    fi
    k delete pod loadgen --ignore-not-found --wait=false >/dev/null 2>&1
}
show_failures() { grep ' FAIL ' "$WORK/loadgen.log" | head -8 | sed 's/^/       /'; }

# 서비스의 버전을 n번 물어 전부 기대한 값인지 본다 (복제본이 여럿이라 여러 번 묻는다). 본 값들을 SEEN 에 넣는다.
SEEN=""
all_versions_are() {    # all_versions_are 서비스 기대값 횟수
    local i v ok=0
    SEEN=""
    for i in $(seq 1 "$3"); do
        v=$(status_version "$1")
        case " $SEEN " in *" $v "*) ;; *) SEEN="$SEEN${SEEN:+ }$v" ;; esac
        [ "$v" = "$2" ] || ok=1
    done
    return $ok
}

echo "대상: $BASE_URL   네임스페이스: $NAMESPACE   실행 시각: $(kst '%F %T') KST"
echo
echo '== Pod 배치 =='
k get pods -o 'custom-columns=POD:.metadata.name,상태:.status.phase,노드:.spec.nodeName' --no-headers 2>&1 | grep -v '^loadgen' | sed 's/^/  /'

# ── 1. 무중단 배포 ────────────────────────────────────────────────────
echo
echo '== 1. 무중단 배포: 요청을 보내는 동안 차례로 다시 배포 =='
loadgen_start
sleep 5         # 배포 전의 평소 구간
deploys=0
for app in clinic auth reservation web; do
    before=$(pods "$app")
    start=$(now_ms)
    k rollout restart "deployment/$app" >/dev/null 2>&1
    k rollout status "deployment/$app" --timeout=240s >/dev/null 2>&1; ok=$?
    # 옛 Pod 가 완전히 사라질 때까지 기다린다 (preStop 과 종료 처리 구간도 요청을 받아 본다)
    wait_gone "$before"
    report $ok "$app 다시 배포" "$(secs $(( $(now_ms) - start )))초, Pod $before → $(pods "$app")"
    deploys=$((deploys + 1))
done

# ── 2. 롤링 업데이트와 롤백 ───────────────────────────────────────────
echo
echo '== 2. 롤링 업데이트와 롤백: clinic 의 버전을 바꿨다가 되돌린다 =='
old_version=$(status_version clinic)
rev0=$(revision clinic)
before=$(pods clinic)
k set env deployment/clinic APP_VERSION=rollback-test >/dev/null 2>&1
k rollout status deployment/clinic --timeout=240s >/dev/null 2>&1; ok=$?
wait_gone "$before"
rev1=$(revision clinic)
all_versions_are clinic rollback-test 8 && [ "$ok" = 0 ]
report $? '업데이트: 새 버전으로 바뀐다' "버전 $old_version → $SEEN, 리비전 $rev0 → $rev1"

before=$(pods clinic)
k rollout undo deployment/clinic >/dev/null 2>&1
k rollout status deployment/clinic --timeout=240s >/dev/null 2>&1; ok=$?
wait_gone "$before"
rev2=$(revision clinic)
all_versions_are clinic "$old_version" 8 && [ "$ok" = 0 ]
report $? '롤백: 이전 버전으로 돌아온다' "버전 rollback-test → $SEEN, 리비전 $rev1 → $rev2 (kubectl rollout undo)"
deploys=$((deploys + 2))

sleep 5         # 배포 뒤의 평소 구간
loadgen_stop
[ "$LG_TOTAL" -gt 0 ] && [ "$LG_FAIL" = 0 ]
report $? "배포 ${deploys}번(다시 배포 4, 업데이트 1, 롤백 1) 동안 실패한 요청" "${LG_TOTAL}건 중 ${LG_FAIL}건 실패"
show_failures

# ── 3. 자동 복구 ──────────────────────────────────────────────────────
echo
echo '== 3. 자동 복구: Pod 하나를 지운다 =='
POLL_TOTAL=0; POLL_FAIL=0
recovered() {   # recovered 앱 지운Pod 경로
    POLL_TOTAL=$((POLL_TOTAL + 1))
    [ "$(http_status "$3")" = 200 ] || POLL_FAIL=$((POLL_FAIL + 1))
    local want ready names
    want=$(k get deployment "$1" -o 'jsonpath={.spec.replicas}' 2>/dev/null)
    ready=$(k get deployment "$1" -o 'jsonpath={.status.readyReplicas}' 2>/dev/null)
    names=$(pods "$1")
    [ "${ready:-0}" = "$want" ] && case " $names " in *" $2 "*) false ;; *) true ;; esac
}
for app in clinic web; do
    path="/api/status/$app"; [ "$app" = web ] && path=/health
    before=$(pods "$app")
    victim=${before%% *}
    POLL_TOTAL=0; POLL_FAIL=0
    k delete pod "$victim" --wait=false >/dev/null 2>&1
    measure_until 180 recovered "$app" "$victim" "$path"; ok=$?
    report $ok "$app Pod 하나를 지우면 다시 채워진다" "$(secs "$ELAPSED")초, Pod $before → $(pods "$app")"
    [ "$POLL_FAIL" = 0 ]
    report $? "$app 그동안 응답이 끊기지 않는다 (남은 Pod 가 받는다)" "$path 를 ${POLL_TOTAL}번 요청해 ${POLL_FAIL}번 실패"
done

# ── 4. 데이터 유지 ────────────────────────────────────────────────────
echo
echo '== 4. 데이터 유지: MySQL Pod 를 지운다 =='
if [ "$SKIP_DB" = 1 ]; then
    echo '건너뜀 (--skip-db)'
else
    mark_out=$(bash "$ROOT/scripts/smoke.sh" --base-url "$BASE_URL" --password "$PASSWORD" --mark 2>&1)
    mark_id=$(printf '%s' "$mark_out" | grep -oE '번호 [0-9]+' | head -1 | grep -oE '[0-9]+')
    printf '%s\n' "$mark_out" | grep -E '^\[' | sed 's/^/  /'
    if [ -z "$mark_id" ]; then
        report 1 '표식 예약 만들기' '예약을 만들지 못해 이 단계를 중단합니다'
    else
        curl -s -m 5 -o /dev/null -c "$WORK/owner.jar" -H 'Content-Type: application/json' \
            -d "{\"loginId\":\"owner001\",\"password\":\"$PASSWORD\"}" "$BASE_URL/api/auth/login"
        restarts_before="$(restarts auth)/$(restarts clinic)/$(restarts reservation)"
        old_db="$(pods mysql) (만든 시각 $(born mysql))"
        volume=$(k get pvc mysql-data -o 'jsonpath={.spec.volumeName} ({.spec.storageClassName})' 2>/dev/null)

        k delete pod -l app=mysql --wait=false >/dev/null 2>&1
        # DB 가 없는 동안 서비스가 어떻게 답하는지 코드를 모아 둔다 (000 은 3초 안에 답이 없었다는 뜻이다)
        CODES=""
        is_down() { [ "$(http_status /api/notices)" != 200 ]; }
        is_back() {
            local c; c=$(http_status /api/notices)
            [ "$c" = 200 ] && return 0
            case " $CODES " in *" $c "*) ;; *) CODES="$CODES${CODES:+, }$c" ;; esac
            return 1
        }
        measure_until 90 is_down; down=$?
        measure_until 300 is_back; up=$?; up_at="$ELAPSED"
        k rollout status statefulset/mysql --timeout=180s >/dev/null 2>&1
        if [ "$down" = 0 ]; then gap="끊긴 시간 $(secs "$up_at")초 (그동안의 응답 코드: ${CODES:-없음})"
        else gap='끊긴 구간을 잡지 못했다 (90초 동안 계속 200)'; fi
        report $up 'MySQL Pod 를 지운 뒤 다시 응답' "$gap, Pod $old_db → $(pods mysql) (만든 시각 $(born mysql)), 볼륨 $volume"

        verify_out=$(bash "$ROOT/scripts/smoke.sh" --base-url "$BASE_URL" --password "$PASSWORD" --verify "$mark_id" --cleanup 2>&1); ok=$?
        report $ok '새 Pod 에서도 데이터가 남아 있다' "$(printf '%s' "$verify_out" | grep -E '^\[' | head -1 | sed -E 's/^\[[^]]*\] //')"
        restarts_after="$(restarts auth)/$(restarts clinic)/$(restarts reservation)"
        [ "$restarts_before" = "$restarts_after" ]
        report $? '서비스는 재시작 없이 다시 붙는다' "재시작 횟수 auth/clinic/reservation: $restarts_before → $restarts_after"
        [ "$(http_status /api/auth/me "$WORK/owner.jar")" = 200 ]
        report $? 'DB 가 다시 떠도 로그인은 유지된다 (세션은 Redis 에 있다)' '지우기 전의 쿠키로 /api/auth/me 200'
    fi
fi

echo
echo "결과: 통과 $PASS, 실패 $FAIL"

# ── 비교: 무중단 설정이 없을 때 ───────────────────────────────────────
if [ "$COMPARE" = 1 ]; then
    echo
    echo '== 비교: reservation 을 전부 내리고 다시 띄우는 방식(Recreate)으로 배포 =='
    restore_strategy() {
        k patch deployment reservation --type merge \
            -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}' >/dev/null 2>&1
    }
    trap 'restore_strategy; rm -rf "$WORK"' EXIT
    loadgen_start
    sleep 3
    before=$(pods reservation)
    k patch deployment reservation --type merge -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}' >/dev/null 2>&1
    start=$(now_ms)
    k rollout restart deployment/reservation >/dev/null 2>&1
    k rollout status deployment/reservation --timeout=240s >/dev/null 2>&1
    wait_gone "$before"
    took=$(secs $(( $(now_ms) - start )))
    sleep 3
    loadgen_stop
    restore_strategy
    echo "[비교] Recreate 로 배포 1번 — ${took}초, ${LG_TOTAL}건 중 ${LG_FAIL}건 실패 (위의 무중단 배포와 비교한다)"
    show_failures
    echo "       설정을 원래대로 되돌렸다: $(k get deployment reservation -o 'jsonpath={.spec.strategy.type} maxSurge={.spec.strategy.rollingUpdate.maxSurge} maxUnavailable={.spec.strategy.rollingUpdate.maxUnavailable}')"
fi

exit "$FAIL"
