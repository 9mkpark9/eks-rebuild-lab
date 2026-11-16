#!/usr/bin/env bash
# 보듬 동물병원 — 테스트 시나리오 (모든 단계에서 같은 스크립트를 쓴다)
#
# 실제 화면이 쓰는 API 를 순서대로 부르고 통과/실패를 출력한다.
# 조회 → 등록(예약 신청) → 조회 → 수정(승인, 취소) 순서로 데이터를 다룬다.
# 필요한 것은 bash 와 curl 뿐이다. 서비스 격리 확인에는 docker 또는 kubectl 도 쓴다.
#
#   ① 앱 (서비스 3개를 직접 실행, 웹 서버 없음)
#     scripts/smoke.sh --auth-url http://127.0.0.1:18081 --clinic-url http://127.0.0.1:18082 \
#                      --reservation-url http://127.0.0.1:18083
#   ② 컨테이너 (docker compose)
#     scripts/smoke.sh                                   # http://localhost:<.env 의 WEB_PORT>
#   ③ ④ 쿠버네티스 (kubeadm 클러스터, EKS)
#     scripts/smoke.sh --base-url http://<주소> --isolation k8s --namespace vet
#
# --isolation    5번(서비스 격리)에서 서비스를 멈추는 방법
#                  compose  docker compose stop/start   (웹 서버를 거칠 때의 기본값)
#                  k8s      kubectl scale --replicas=0 뒤 원래 수로 되돌림
#                  none     5번을 건너뛴다               (서비스에 직접 요청할 때의 기본값)
# --no-db-check  DB 경계 확인을 건너뛴다 (DB 가 클러스터 밖의 RDS 라 DB 컨테이너가 없을 때)
# --db-exec CMD  DB 경계 확인에서 vet-sql 을 실행할 명령. 예: --db-exec "docker exec vet-apptest-mysql"
# --db-target T  k8s 에서 vet-sql 을 실행할 대상. 기본은 app=mysql 라벨이 붙은 Pod 다
# --mark         지우지 않는 예약을 하나 만들고 번호를 출력한다 (DB Pod 를 교체하기 전에)
# --verify N     그 예약이 남아 있는지 확인한다 (DB Pod 를 교체한 뒤에). --cleanup 을 붙이면 확인 뒤 취소한다
#
# 끝나면 실패 수를 종료 코드로 돌려준다 (0 = 전부 통과).
# --mark 를 빼면 만든 예약은 스크립트가 취소하므로 여러 번 돌려도 된다.
set -u

# 한글을 글자 단위로 자르려면 UTF-8 로캘이어야 한다 (긴 응답을 줄여 출력할 때 쓴다)
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]*) ;;
    *) if locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$'; then export LC_ALL=C.UTF-8; fi ;;
esac

BASE_URL="${BASE_URL:-}"
AUTH_URL=""; CLINIC_URL=""; RESERVATION_URL=""
ISOLATION=""
NAMESPACE="vet"
PASSWORD="test-only"          # README 의 테스트 계정 공통 비밀번호
NO_DB_CHECK=0
DB_EXEC=""
DB_TARGET=""
WAIT=180
MODE="full"
VERIFY_ID=""
CLEANUP=0

usage() { sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --base-url)        BASE_URL="$2"; shift 2 ;;
        --auth-url)        AUTH_URL="$2"; shift 2 ;;
        --clinic-url)      CLINIC_URL="$2"; shift 2 ;;
        --reservation-url) RESERVATION_URL="$2"; shift 2 ;;
        --isolation)       ISOLATION="$2"; shift 2 ;;
        --namespace|-n)    NAMESPACE="$2"; shift 2 ;;
        --password)        PASSWORD="$2"; shift 2 ;;
        --no-db-check)     NO_DB_CHECK=1; shift ;;
        --db-exec)         DB_EXEC="$2"; shift 2 ;;
        --db-target)       DB_TARGET="$2"; shift 2 ;;
        --wait)            WAIT="$2"; shift 2 ;;
        --mark)            MODE="mark"; shift ;;
        --verify)          MODE="verify"; VERIFY_ID="$2"; shift 2 ;;
        --cleanup)         CLEANUP=1; shift ;;
        -h|--help)         usage; exit 0 ;;
        *) echo "모르는 옵션: $1" >&2; usage >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 서비스 주소를 하나라도 주면 웹 서버를 거치지 않고 서비스에 직접 요청한다 (①)
DIRECT=0
if [ -n "$AUTH_URL$CLINIC_URL$RESERVATION_URL" ]; then
    if [ -z "$AUTH_URL" ] || [ -z "$CLINIC_URL" ] || [ -z "$RESERVATION_URL" ]; then
        echo "--auth-url, --clinic-url, --reservation-url 은 셋을 함께 줘야 합니다." >&2; exit 2
    fi
    DIRECT=1
    AUTH_URL="${AUTH_URL%/}"; CLINIC_URL="${CLINIC_URL%/}"; RESERVATION_URL="${RESERVATION_URL%/}"
fi

if [ "$DIRECT" = 0 ] && [ -z "$BASE_URL" ]; then
    port=8088
    if [ -f "$ROOT/.env" ]; then
        p=$(grep -E '^WEB_PORT=[0-9]+' "$ROOT/.env" | head -1 | cut -d= -f2 | tr -d '\r')
        [ -n "$p" ] && port="$p"
    fi
    BASE_URL="http://localhost:$port"
fi
BASE_URL="${BASE_URL%/}"

if [ -z "$ISOLATION" ]; then
    if [ "$DIRECT" = 1 ]; then ISOLATION=none; else ISOLATION=compose; fi
fi
case "$ISOLATION" in
    compose|k8s|none) ;;
    *) echo "--isolation 은 compose, k8s, none 중 하나입니다." >&2; exit 2 ;;
esac
if [ "$DIRECT" = 1 ] && [ "$ISOLATION" != none ]; then
    echo "서비스에 직접 요청할 때는 웹 서버가 없어 5번(서비스 격리)을 확인할 수 없습니다. --isolation none 으로 진행합니다."
    ISOLATION=none
fi

WORK="$(mktemp -d)"

PASS=0
FAIL=0
declare -A SAVED_REPLICAS=()

report() {      # report 0|1 이름 설명   (0 = 통과)
    if [ "$1" = 0 ]; then PASS=$((PASS + 1)); printf '[통과] %s — %s\n' "$2" "$3"
    else FAIL=$((FAIL + 1)); printf '[실패] %s — %s\n' "$2" "$3"; fi
}

# 서버의 날짜는 한국 시간이다. 이 스크립트를 UTC 인 서버(EC2)에서 돌려도 같은 날짜를 쓴다.
# 시간대 자료(tzdata)가 없는 환경도 있어서 TZ 를 쓰지 않고 UTC 에 9시간을 더해 계산한다.
kst() { date -u -d "@$(( $(date +%s) + 9 * 3600 + ${2:-0} * 86400 ))" "+$1"; }
day() { kst %F "$1"; }
is_sunday() { [ "$(kst %u "$1")" = 7 ]; }

# 경로를 맡은 서비스 (웹 서버의 프록시 규칙과 같은 순서다)
service_of() {
    case "$1" in
        /api/status/auth*|/api/auth/*)                                          echo auth ;;
        /api/status/clinic*|/api/admin/notices*|/api/pets*|/api/notices*|/api/slots*) echo clinic ;;
        /api/status/reservation*|/api/reservations*|/api/admin/*|/api/director/*)     echo reservation ;;
        *) echo "" ;;
    esac
}

SVC_OVERRIDE=""
url_for() {
    if [ "$DIRECT" = 0 ]; then printf '%s%s' "$BASE_URL" "$1"; return; fi
    local svc="${SVC_OVERRIDE:-$(service_of "$1")}"
    case "$svc" in
        clinic)      printf '%s%s' "$CLINIC_URL" "$1" ;;
        reservation) printf '%s%s' "$RESERVATION_URL" "$1" ;;
        *)           printf '%s%s' "$AUTH_URL" "$1" ;;
    esac
}

# api METHOD PATH [쿠키 파일] [본문]
# 결과는 R_STATUS R_BODY R_WEBNODE R_WEBVER R_SERVEDBY R_APPVER 에 들어간다. 연결하지 못하면 R_STATUS 는 000 이다.
# $( ) 안에서 부르면 결과가 사라지므로 항상 그냥 부른다.
R_STATUS=000; R_BODY=""; R_WEBNODE=""; R_WEBVER=""; R_SERVEDBY=""; R_APPVER=""
header() { grep -i "^$1:" "$WORK/h" 2>/dev/null | tail -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//'; }
api() {
    local method="$1" path="$2" jar="${3:-}" body="${4:-}"
    local args=(-s -m 20 -X "$method" -H 'Accept: application/json' -D "$WORK/h" -o "$WORK/b" -w '%{http_code}')
    [ -n "$jar" ] && args+=(-b "$jar" -c "$jar")
    if [ -n "$body" ]; then args+=(-H 'Content-Type: application/json' --data-binary "$body")
    elif [ "$method" = POST ] || [ "$method" = PUT ]; then args+=(-H 'Content-Length: 0'); fi
    : > "$WORK/h"; : > "$WORK/b"
    R_STATUS=$(curl "${args[@]}" "$(url_for "$path")" 2>/dev/null) || true
    [ -n "$R_STATUS" ] || R_STATUS=000
    R_BODY=$(cat "$WORK/b" 2>/dev/null)
    R_WEBNODE=$(header X-Web-Node); R_WEBVER=$(header X-Web-Version)
    R_SERVEDBY=$(header X-Served-By); R_APPVER=$(header X-App-Version)
}

# 응답은 모두 한 겹짜리 JSON 이라 grep 으로 읽는다 (jq 가 없는 서버에서도 돌도록).
jget() {        # jget 키 [JSON]   처음 나오는 값
    printf '%s' "${2-$R_BODY}" | grep -oE "\"$1\":(\"[^\"]*\"|[^,}]*)" | head -1 | sed -e 's/^"[^"]*"://' -e 's/^"//' -e 's/"$//'
}
jcount() {      # 배열의 항목 수
    local n; n=$(printf '%s' "${1-$R_BODY}" | grep -o '{' | wc -l); echo $((n))
}
jrow() {        # jrow 키 숫자값   배열에서 그 값을 가진 항목 하나
    printf '%s' "$R_BODY" | sed 's/},{/}\n{/g' | grep -E "\"$1\":$2[,}]" | head -1
}

brief() { local t="$R_BODY"; [ "${#t}" -gt 110 ] && t="${t:0:110}…"; printf '%s %s' "$R_STATUS" "$t"; }

login() {       # login 아이디 쿠키파일
    rm -f "$2"
    api POST /api/auth/login "$2" "{\"loginId\":\"$1\",\"password\":\"$PASSWORD\"}"
}

wait_until() {  # wait_until 초 명령...   명령이 성공할 때까지 2초마다 다시 해 본다
    local limit="$1"; shift
    local end=$(( $(date +%s) + limit ))
    while :; do
        "$@" && return 0
        [ "$(date +%s)" -ge "$end" ] && return 1
        sleep 2
    done
}
is_status() { local want="$1"; shift; api "$@"; [ "$R_STATUS" = "$want" ]; }
can_login() { login owner001 "$WORK/probe.jar"; [ "$R_STATUS" = 200 ]; }

# 예약 가능한 시간을 찾아 신청한다. 같은 날 이미 예약이 있으면(409) 다음 날로 넘어간다.
# 결과: N_ID(0 이면 실패) N_DATE N_SLOTS, 마지막 응답은 R_* 에 남는다.
N_ID=0; N_DATE=""; N_SLOTS=0
new_reservation() {     # new_reservation 쿠키파일 petId 시작일(며칠 뒤)
    local jar="$1" pet="$2" d date slot
    N_ID=0; N_DATE=""; N_SLOTS=0
    for d in $(seq "$3" 13); do
        date=$(day "$d")
        api GET "/api/slots?date=$date&type=GENERAL" "$jar"
        [ "$R_STATUS" = 200 ] || return
        N_SLOTS=$(jcount)
        [ "$N_SLOTS" -gt 0 ] || continue                 # 일요일(휴진)이거나 마감
        slot=$(jget slotId)
        api POST /api/reservations "$jar" "{\"petId\":$pet,\"slotId\":$slot}"
        if [ "$R_STATUS" = 201 ]; then N_ID=$(jget reservationId); N_DATE="$date"; return; fi
        [ "$R_STATUS" = 409 ] || return
    done
}

# 2번: 반려동물 조회 → 예약 가능 시간 조회 → 예약 신청(등록) → 내 예약 조회 → 취소(수정)
owner_flow() {  # owner_flow 쿠키파일 이름표
    local jar="$1" label="$2" pets pet id row st
    api GET /api/pets "$jar"
    pets=$(jcount); pet=$(jget petId)
    [ "$R_STATUS" = 200 ] && [ "$pets" -ge 1 ]
    report $? "$label 반려동물 목록" "$R_STATUS, ${pets}마리, 처리 $R_SERVEDBY"
    [ "$pets" -ge 1 ] || return

    new_reservation "$jar" "$pet" 1
    id="$N_ID"
    if [ "$id" -gt 0 ]; then report 0 "$label 예약 가능 시간 조회 → 예약 신청" "$N_DATE 에 빈 시간 ${N_SLOTS}개, 예약 번호 $id, 처리 $R_SERVEDBY"
    else report 1 "$label 예약 가능 시간 조회 → 예약 신청" "$(brief)"; return; fi

    api GET /api/reservations/me "$jar"
    row=$(jrow reservationId "$id"); st=$(jget status "$row")
    [ "$R_STATUS" = 200 ] && [ "$st" = REQUESTED ]
    report $? "$label 내 예약 조회" "$R_STATUS, 방금 신청한 예약 상태 $st"

    api DELETE "/api/reservations/$id" "$jar"
    local del="$R_STATUS"
    api GET /api/reservations/me "$jar"
    row=$(jrow reservationId "$id"); st=$(jget status "$row")
    [ "$del" = 204 ] && [ "$st" = CANCELLED ]
    report $? "$label 예약 취소" "$del, 취소 뒤 상태 $st"
}

set_service() { # set_service 이름 on|off
    local name="$1" count
    if [ "$ISOLATION" = compose ]; then
        if [ "$2" = on ]; then (cd "$ROOT" && docker compose start "$name") >/dev/null 2>&1
        else (cd "$ROOT" && docker compose stop "$name") >/dev/null 2>&1; fi
    elif [ "$ISOLATION" = k8s ]; then
        # 멈출 때 원래 복제본 수를 적어 두고, 켤 때 그 수로 되돌린다
        if [ "$2" = on ]; then
            count="${SAVED_REPLICAS[$name]:-1}"
            kubectl -n "$NAMESPACE" scale "deployment/$name" "--replicas=$count" >/dev/null 2>&1
        else
            SAVED_REPLICAS[$name]=$(kubectl -n "$NAMESPACE" get "deployment/$name" -o 'jsonpath={.spec.replicas}' 2>/dev/null)
            kubectl -n "$NAMESPACE" scale "deployment/$name" --replicas=0 >/dev/null 2>&1
        fi
    fi
}
# 중간에 Ctrl+C 로 끊어도 멈춘 서비스를 다시 켠다
STOPPED=""
restore_stopped() { [ -n "$STOPPED" ] && set_service "$STOPPED" on; STOPPED=""; }
trap 'restore_stopped; rm -rf "$WORK"' EXIT

# 멈춘 서비스의 경로는 HTML 오류 페이지가 아니라 { code, message } JSON 503 이어야 한다
is_down() { api GET "$1" "${2:-}"; [ "$R_STATUS" = 503 ] && [ "$(jget code)" = SERVICE_UNAVAILABLE ]; }
check_down() {  # check_down 이름표 경로 [쿠키파일]
    wait_until 40 is_down "$2" "${3:-}"
    report $? "$1 멈춘 서비스 경로는 503 JSON" "$2 → $(brief)"
}

# 상태 쪽지(/status)가 읽는 응답: 멈춘 서비스의 줄만 503 이고 나머지는 200 이어야 한다
check_status_rows() {   # check_status_rows 이름표 멈춘서비스
    local ok=0 parts="" svc
    for svc in auth clinic reservation; do
        api GET "/api/status/$svc"
        parts="$parts${parts:+, }$svc $R_STATUS"
        if [ "$svc" = "$2" ]; then [ "$R_STATUS" = 503 ] || ok=1
        else [ "$R_STATUS" = 200 ] || ok=1; fi
    done
    report $ok "$1 상태 쪽지는 그 줄만 응답 없음" "$parts"
}

# 서비스의 DB 계정으로 SQL 한 줄을 실행한다 (DB 컨테이너 안의 vet-sql). 결과: DB_CODE DB_TEXT
DB_CODE=0; DB_TEXT=""
db() {          # db 계정 SQL
    local out
    if [ -n "$DB_EXEC" ]; then out=$(MSYS_NO_PATHCONV=1 $DB_EXEC vet-sql "$1" "$2" 2>&1)
    elif [ "$ISOLATION" = k8s ]; then
        [ -n "$DB_TARGET" ] || DB_TARGET="pod/$(kubectl -n "$NAMESPACE" get pods -l app=mysql -o 'jsonpath={.items[0].metadata.name}' 2>/dev/null)"
        out=$(MSYS_NO_PATHCONV=1 kubectl -n "$NAMESPACE" exec "$DB_TARGET" -- vet-sql "$1" "$2" 2>&1)
    else out=$(cd "$ROOT" && MSYS_NO_PATHCONV=1 docker compose exec -T mysql vet-sql "$1" "$2" 2>&1); fi
    DB_CODE=$?
    DB_TEXT=$(printf '%s' "$out" | tr '\r\n' '  ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//')
    [ "${#DB_TEXT}" -gt 90 ] && DB_TEXT="${DB_TEXT:0:90}…"
}
db_allowed() {  # db_allowed 이름 계정 SQL
    db "$2" "$3"
    report $((DB_CODE != 0)) "$1" "vet_$2: 허용됨 $DB_TEXT"
}
db_denied() {
    db "$2" "$3"
    if [ "$DB_CODE" != 0 ] && printf '%s' "$DB_TEXT" | grep -qE 'denied|Unknown column'; then report 0 "$1" "vet_$2: $DB_TEXT"
    elif [ "$DB_CODE" = 0 ]; then report 1 "$1" "vet_$2: 허용됨 (막혀야 한다)"
    else report 1 "$1" "vet_$2: $DB_TEXT"; fi
}

target_line() {
    if [ "$DIRECT" = 1 ]; then echo "대상: auth $AUTH_URL, clinic $CLINIC_URL, reservation $RESERVATION_URL (서비스에 직접)"
    else echo "대상: $BASE_URL (웹 서버를 거침)"; fi
}

MARK_OWNER=owner002      # 표식 예약은 시나리오와 겹치지 않게 다른 보호자로 만든다

# ── --mark: 지우지 않는 예약을 하나 만든다 ────────────────────────────
if [ "$MODE" = mark ]; then
    target_line
    login "$MARK_OWNER" "$WORK/mark.jar"
    [ "$R_STATUS" = 200 ] || { echo "[실패] $MARK_OWNER 로그인 — $(brief)"; exit 1; }
    api GET /api/pets "$WORK/mark.jar"
    pet=$(jget petId)
    [ -n "$pet" ] || { echo "[실패] 반려동물 조회 — $(brief)"; exit 1; }
    new_reservation "$WORK/mark.jar" "$pet" 2
    [ "$N_ID" -gt 0 ] || { echo "[실패] 예약 신청 — $(brief)"; exit 1; }
    echo "[통과] 표식 예약을 만들었다 — 번호 $N_ID, 날짜 $N_DATE, 보호자 $MARK_OWNER, 상태 REQUESTED, 처리 $R_SERVEDBY"
    echo "DB Pod 를 교체한 뒤 확인: scripts/smoke.sh ... --verify $N_ID"
    exit 0
fi

# ── --verify N: 그 예약이 남아 있는지 본다 ────────────────────────────
if [ "$MODE" = verify ]; then
    target_line
    wait_until "$WAIT" is_status 200 POST /api/auth/login "$WORK/mark.jar" "{\"loginId\":\"$MARK_OWNER\",\"password\":\"$PASSWORD\"}"
    [ "$R_STATUS" = 200 ] || { echo "[실패] $MARK_OWNER 로그인 — $(brief)"; exit 1; }
    wait_until "$WAIT" is_status 200 GET /api/reservations/me "$WORK/mark.jar"
    row=$(jrow reservationId "$VERIFY_ID"); st=$(jget status "$row")
    if [ "$R_STATUS" = 200 ] && [ -n "$row" ]; then
        echo "[통과] 표식 예약이 남아 있다 — 번호 $VERIFY_ID, 날짜 $(jget visitDate "$row"), 상태 $st, 처리 $R_SERVEDBY"
    else
        echo "[실패] 표식 예약이 없다 — 번호 $VERIFY_ID, 응답 $(brief)"; exit 1
    fi
    if [ "$CLEANUP" = 1 ]; then
        api DELETE "/api/reservations/$VERIFY_ID" "$WORK/mark.jar"
        echo "뒷정리: 표식 예약 취소 $R_STATUS"
    fi
    exit 0
fi

OWNER_JAR="$WORK/owner.jar"; NURSE_JAR="$WORK/nurse.jar"; DIRECTOR_JAR="$WORK/director.jar"

target_line
echo "격리 확인 방식: $ISOLATION   실행 시각: $(kst '%F %T') KST"

# ── 0. 준비: 어떤 순서로 떴든 전부 응답할 때까지 기다린다 ─────────────
echo
echo '== 0. 준비 =='
if [ "$DIRECT" = 0 ]; then
    wait_until "$WAIT" is_status 200 GET /health; ok=$?
    report $ok 'web /health' "$R_STATUS $R_BODY, X-Web-Node=$R_WEBNODE, X-Web-Version=$R_WEBVER"
    [ "$ok" = 0 ] || { echo '웹 서버가 응답하지 않아 중단합니다.'; exit 1; }
else
    for svc in auth clinic reservation; do
        SVC_OVERRIDE="$svc"
        wait_until "$WAIT" is_status 200 GET /health; ok=$?
        report $ok "$svc /health" "$R_STATUS $R_BODY, X-Served-By=$R_SERVEDBY, X-App-Version=$R_APPVER"
        SVC_OVERRIDE=""
        [ "$ok" = 0 ] || { echo "$svc 서비스가 응답하지 않아 중단합니다."; exit 1; }
    done
fi

wait_until "$WAIT" is_status 200 GET /api/notices
report $? 'clinic 준비 (/api/notices)' "$R_STATUS, 공지 $(jcount)건, 처리 $R_SERVEDBY"

if wait_until "$WAIT" can_login; then report 0 'auth 준비 (로그인 가능)' 'DB 와 Redis 에 연결됨'
else report 1 'auth 준비 (로그인 가능)' "$(brief)"; fi

wait_until "$WAIT" is_status 200 GET /api/reservations/me "$WORK/probe.jar"
report $? 'reservation 준비 (/api/reservations/me)' "$R_STATUS, 처리 $R_SERVEDBY"

if [ "$DIRECT" = 0 ]; then
    api GET /; home="$R_STATUS"
    api GET /app/reserve
    [ "$home" = 200 ] && [ "$R_STATUS" = 200 ]
    report $? '홈과 예약 화면' "/ $home, /app/reserve $R_STATUS"
fi

# ── 1. 보호자 로그인 → /api/auth/me ───────────────────────────────────
echo
echo '== 1. 보호자 로그인 =='
login owner001 "$OWNER_JAR"
[ "$R_STATUS" = 200 ] && [ "$(jget role)" = OWNER ]
report $? '1 보호자 로그인 (owner001)' "$R_STATUS, 역할 $(jget role), 처리 $R_SERVEDBY"
api GET /api/auth/me "$OWNER_JAR"
[ "$R_STATUS" = 200 ] && [ "$(jget loginId)" = owner001 ]
report $? '1 /api/auth/me' "$R_STATUS, $(jget loginId) ($(jget name))"

# ── 2. 반려동물 → 예약 가능 시간 → 신청 → 내 예약 → 취소 ──────────────
echo
echo '== 2. 보호자 예약 흐름 (조회 → 등록 → 조회 → 수정) =='
owner_flow "$OWNER_JAR" '2'

# ── 3. 간호사 로그인 → 예약 현황 → 승인 ───────────────────────────────
echo
echo '== 3. 간호사 (조회 → 수정) =='
api GET /api/pets "$OWNER_JAR"
pet=$(jget petId)
N_ID=0
[ -n "$pet" ] && new_reservation "$OWNER_JAR" "$pet" 1
for_nurse="$N_ID"; nurse_date="$N_DATE"
if [ "$for_nurse" -gt 0 ]; then report 0 '3 승인받을 예약 준비 (보호자가 신청)' "$nurse_date, 예약 번호 $for_nurse"
else report 1 '3 승인받을 예약 준비 (보호자가 신청)' "$(brief)"; fi

login admin1 "$NURSE_JAR"
[ "$R_STATUS" = 200 ] && [ "$(jget role)" = NURSE ]
report $? '3 간호사 로그인 (admin1)' "$R_STATUS, 역할 $(jget role)"
if [ "$for_nurse" -gt 0 ]; then
    api GET "/api/admin/reservations?date=$nurse_date" "$NURSE_JAR"
    row=$(jrow reservationId "$for_nurse"); st=$(jget status "$row")
    [ "$R_STATUS" = 200 ] && [ "$st" = REQUESTED ]
    report $? '3 예약 현황' "$R_STATUS, $nurse_date 예약 $(jcount)건, 대상 예약 상태 $st, 처리 $R_SERVEDBY"
    api POST "/api/admin/reservations/$for_nurse/approve" "$NURSE_JAR"
    [ "$R_STATUS" = 200 ] && [ "$(jget status)" = CONFIRMED ]
    report $? '3 승인' "$R_STATUS, 승인 뒤 상태 $(jget status)"
    api DELETE "/api/reservations/$for_nurse" "$OWNER_JAR"
    [ "$R_STATUS" = 204 ]
    report $? '3 뒷정리 (보호자가 취소)' "$R_STATUS"
fi

# ── 4. 원장 로그인 → 내 일정 ──────────────────────────────────────────
echo
echo '== 4. 원장 =='
login vet1 "$DIRECTOR_JAR"
[ "$R_STATUS" = 200 ] && [ "$(jget role)" = DIRECTOR ]
report $? '4 원장 로그인 (vet1)' "$R_STATUS, 역할 $(jget role), vetId $(jget vetId)"
if is_sunday 1; then work_day=$(day 2); else work_day=$(day 1); fi
api GET "/api/director/schedule?date=$work_day" "$DIRECTOR_JAR"
[ "$R_STATUS" = 200 ] && [ "$(jcount)" -ge 1 ]
report $? '4 내 일정' "$R_STATUS, $work_day 진료 시간 $(jcount)칸, 처리 $R_SERVEDBY"

# ── 버전과 상태 쪽지: 서비스마다 버전과 응답한 서버를 알려 준다 ───────
echo
echo '== 버전과 상태 쪽지 =='
for svc in auth clinic reservation; do
    api GET "/api/status/$svc"
    ver=$(jget version)
    if [ "$R_STATUS" = 200 ] && [ "$(jget service)" = "$svc" ] && [ -n "$ver" ] && [ "$R_APPVER" = "$ver" ]; then
        report 0 "상태 $svc (/api/status/$svc)" "$R_STATUS, 버전 $ver, 응답 $(jget servedBy)"
    elif [ "$R_STATUS" = 200 ]; then
        report 1 "상태 $svc (/api/status/$svc)" "$R_STATUS, 버전 $ver, X-App-Version=$R_APPVER"
    else
        report 1 "상태 $svc (/api/status/$svc)" "$(brief)"
    fi
done
if [ "$DIRECT" = 0 ]; then
    api GET /status
    [ "$R_STATUS" = 200 ] && [ -n "$R_WEBVER" ]
    report $? '상태 쪽지 화면 (/status)' "$R_STATUS, web 버전 $R_WEBVER, 응답 $R_WEBNODE"
fi

# ── DB 경계: 서비스 계정은 자기 스키마만 쓰고, 남의 데이터는 뷰로 읽기만 한다 ──
echo
echo '== DB 경계 =='
if [ "$NO_DB_CHECK" = 1 ] || { [ "$ISOLATION" = none ] && [ -z "$DB_EXEC" ]; }; then
    echo '건너뜀'
else
    db_allowed 'auth 가 자기 사용자 테이블 읽기' auth 'SELECT COUNT(*) FROM users'
    db_denied  'auth 가 예약 읽기' auth 'SELECT COUNT(*) FROM vet_reservation.reservations'
    db_denied  'clinic 이 사용자 읽기' clinic 'SELECT COUNT(*) FROM vet_auth.users'
    db_denied  'clinic 이 예약 지우기' clinic 'DELETE FROM vet_reservation.reservations WHERE reservation_id = 0'
    db_allowed 'reservation 이 뷰로 보호자 읽기' reservation 'SELECT COUNT(*) FROM users'
    db_denied  'reservation 이 비밀번호 해시 읽기 (뷰)' reservation 'SELECT password_hash FROM users LIMIT 1'
    db_denied  'reservation 이 사용자 원본 테이블 읽기' reservation 'SELECT COUNT(*) FROM vet_auth.users'
    db_denied  'reservation 이 반려동물 고치기' reservation 'UPDATE pets SET age = age WHERE pet_id = 1'
    db_denied  'reservation 이 진료 시각 고치기' reservation 'UPDATE slots SET start_at = start_at WHERE slot_id = 1'
    db_denied  'reservation 이 진료 시간 지우기' reservation 'DELETE FROM slots WHERE slot_id = 0'
fi

# ── 5. 서비스 격리: 하나가 멈춰도 다른 서비스 경로는 정상이어야 한다 ───
echo
echo '== 5. 서비스 격리 =='
if [ "$ISOLATION" = none ]; then
    echo '건너뜀 (--isolation none)'
else
    echo '-- auth 를 멈춘 상태'
    STOPPED=auth; set_service auth off
    check_down '5-1' /api/auth/me "$OWNER_JAR"
    check_status_rows '5-1' auth
    owner_flow "$OWNER_JAR" '5-1 (이미 로그인한 세션)'
    restore_stopped
    wait_until "$WAIT" is_status 200 GET /api/auth/me "$OWNER_JAR"
    report $? '5-1 auth 를 다시 켜면 복구' "/api/auth/me $R_STATUS"

    echo '-- clinic 을 멈춘 상태'
    STOPPED=clinic; set_service clinic off
    check_down '5-2' /api/notices
    check_status_rows '5-2' clinic
    api GET /api/reservations/me "$OWNER_JAR"
    [ "$R_STATUS" = 200 ]; report $? '5-2 내 예약 조회' "$R_STATUS, $(jcount)건"
    api GET "/api/admin/reservations?date=$work_day" "$NURSE_JAR"
    [ "$R_STATUS" = 200 ]; report $? '5-2 간호사 예약 현황' "$R_STATUS, $(jcount)건"
    api GET "/api/admin/slots?date=$work_day" "$NURSE_JAR"
    [ "$R_STATUS" = 200 ]; report $? '5-2 간호사 진료 시간 조회' "$R_STATUS, $(jcount)칸"
    api GET "/api/director/schedule?date=$work_day" "$DIRECTOR_JAR"
    [ "$R_STATUS" = 200 ]; report $? '5-2 원장 내 일정' "$R_STATUS, $(jcount)칸"
    api GET /api/director/stats "$DIRECTOR_JAR"
    [ "$R_STATUS" = 200 ]; report $? '5-2 원장 병원 현황' "$R_STATUS"
    restore_stopped
    wait_until "$WAIT" is_status 200 GET /api/notices
    report $? '5-2 clinic 을 다시 켜면 복구' "/api/notices $R_STATUS"

    echo '-- reservation 을 멈춘 상태'
    STOPPED=reservation; set_service reservation off
    check_down '5-3' /api/reservations/me "$OWNER_JAR"
    check_status_rows '5-3' reservation
    api GET /api/notices
    [ "$R_STATUS" = 200 ]; report $? '5-3 공지' "$R_STATUS, $(jcount)건"
    api GET /api/pets "$OWNER_JAR"
    [ "$R_STATUS" = 200 ]; report $? '5-3 반려동물' "$R_STATUS, $(jcount)마리"
    api GET "/api/slots?date=$work_day&type=GENERAL" "$OWNER_JAR"
    [ "$R_STATUS" = 200 ]; report $? '5-3 예약 가능 시간' "$R_STATUS, $(jcount)개"
    api GET /
    [ "$R_STATUS" = 200 ]; report $? '5-3 홈 화면' "$R_STATUS"
    restore_stopped
    wait_until "$WAIT" is_status 200 GET /api/reservations/me "$OWNER_JAR"
    report $? '5-3 reservation 을 다시 켜면 복구' "/api/reservations/me $R_STATUS"
fi

echo
echo "결과: 통과 $PASS, 실패 $FAIL"
exit "$FAIL"
