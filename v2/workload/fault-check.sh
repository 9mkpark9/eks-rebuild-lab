#!/usr/bin/env bash
# ① 워크로드 테스트 — 구성 요소 하나가 멈췄을 때 나머지가 어떻게 답하는지 본다.
# 서비스 3개, MySQL, Redis 가 모두 떠 있는 상태에서 실행한다. 끝나면 모두 다시 떠 있다.
#
#   v2/workload/fault-check.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN="$ROOT/v2/_run"
SVC="$ROOT/v2/workload/services.sh"
JAR="$RUN/1-workload/cookie.txt"; command -v cygpath > /dev/null && JAR="$(cygpath -m "$JAR")"   # Windows 의 curl 은 /tmp 를 모른다
trap 'rm -f "$JAR"' EXIT
A=http://127.0.0.1:28081; C=http://127.0.0.1:28082; R=http://127.0.0.1:28083

# 요청 하나: 상태 코드, 오류 코드, 걸린 시간
req() { # req <이름> <주소> [쿠키 사용 여부]
    local out code body
    out="$(curl -s -m 10 ${3:+-b "$JAR"} -w '\n%{http_code} %{time_total}' "$2" 2>/dev/null)"
    code="$(printf '%s' "$out" | tail -1)"
    body="$(printf '%s' "$out" | head -1 | grep -o '"code":"[A-Z_]*"' | head -1)"
    printf '    %-34s %s %s\n' "$1" "$code" "$body"
}
probe() {
    echo "  [$1]"
    req "auth /health"                  "$A/health"
    req "clinic /health"                "$C/health"
    req "reservation /health"           "$R/health"
    req "auth 내 정보 (세션)"            "$A/api/auth/me" 1
    req "clinic 공지 (DB)"              "$C/api/notices"
    req "clinic 반려동물 (세션+DB)"      "$C/api/pets" 1
    req "reservation 내 예약 (세션+DB)" "$R/api/reservations/me" 1
}
wait_ok() { # wait_ok <주소> : 200 이 될 때까지 기다린 초
    local t0 n; t0=$(date +%s)
    for n in $(seq 1 90); do
        [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "$1")" = 200 ] && { echo $(( $(date +%s) - t0 )); return; }
        sleep 1
    done
    echo "90초 안에 회복 안 됨"
}

curl -s -o /dev/null -c "$JAR" -H 'Content-Type: application/json' -d '{"loginId":"owner252","password":"test-only"}' "$A/api/auth/login"
probe "기준: 모두 정상"

echo; echo "■ A. clinic 서비스를 멈춘다"
if command -v taskkill > /dev/null 2>&1; then taskkill //PID "$(netstat -ano | grep -E '[:.]28082 .*LISTENING' | awk '{print $NF}' | head -1)" //F > /dev/null
else kill -9 "$(ss -ltnpH 'sport = :28082' | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)"; fi
sleep 1
probe "clinic 중지"
bash "$SVC" start | sed 's/^/    /'
probe "clinic 다시 실행 (같은 쿠키)"

echo; echo "■ B. MySQL 을 멈춘다"
docker stop v2-mysql > /dev/null
probe "MySQL 중지"
docker start v2-mysql > /dev/null
echo "    MySQL 시작 뒤 공지 조회가 200 이 되기까지: $(wait_ok "$C/api/notices")초 (서비스는 다시 실행하지 않음)"
probe "MySQL 다시 실행"

echo; echo "■ C. Redis 를 멈춘다"
docker stop v2-redis > /dev/null
probe "Redis 중지"
docker start v2-redis > /dev/null
sleep 3
probe "Redis 다시 실행 (같은 쿠키)"
