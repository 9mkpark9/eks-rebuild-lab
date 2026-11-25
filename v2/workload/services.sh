#!/usr/bin/env bash
# ① 워크로드 테스트 — 서비스 3개를 jar 로 직접 실행한다 (컨테이너 아님).
# MySQL(127.0.0.1:23306)과 Redis(127.0.0.1:26379)는 먼저 떠 있어야 한다.
#
#   v2/workload/services.sh start     3개를 실행하고 /health 가 200 이 될 때까지 기다린다
#   v2/workload/services.sh status    포트, 프로세스 번호, 메모리, /health
#   v2/workload/services.sh stop      3개를 끝낸다
#
# 포트: auth 28081, clinic 28082, reservation 28083
# 비밀번호는 v2/_run/secrets.env 에서 읽고 화면에 출력하지 않는다.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN="$ROOT/v2/_run"
LOGS="$RUN/1-workload"
SERVICES="auth clinic reservation"
. "$RUN/secrets.env"

port_of() { case "$1" in auth) echo 28081 ;; clinic) echo 28082 ;; reservation) echo 28083 ;; esac; }
password_of() { case "$1" in auth) echo "$DB_AUTH_PASSWORD" ;; clinic) echo "$DB_CLINIC_PASSWORD" ;; reservation) echo "$DB_RESERVATION_PASSWORD" ;; esac; }
# 그 포트를 듣고 있는 프로세스 번호. Windows(Git Bash)는 netstat, Linux(WSL 2)는 ss 로 찾는다
if command -v taskkill > /dev/null 2>&1; then WIN=1; else WIN=0; fi
pid_of() {
    if [ $WIN = 1 ]; then netstat -ano | grep -E "[:.]$(port_of "$1") .*LISTENING" | awk '{print $NF}' | head -1
    else ss -ltnpH "sport = :$(port_of "$1")" 2>/dev/null | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2; fi
}
health() { curl -s -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$(port_of "$1")/health" 2>/dev/null || true; }

start() {
    for s in $SERVICES; do
        [ -n "$(pid_of "$s")" ] && { echo "$s: 이미 실행 중"; continue; }
        # 서비스가 읽는 설정은 전부 환경 변수다 (msa/common/src/main/resources/vet-common.yml)
        SERVER_PORT="$(port_of "$s")" \
        SPRING_DATASOURCE_URL="jdbc:mysql://127.0.0.1:23306/vet_$s?connectionTimeZone=LOCAL&characterEncoding=UTF-8" \
        SPRING_DATASOURCE_USERNAME="vet_$s" \
        SPRING_DATASOURCE_PASSWORD="$(password_of "$s")" \
        SPRING_DATA_REDIS_HOST=127.0.0.1 \
        SPRING_DATA_REDIS_PORT=26379 \
        SPRING_DATA_REDIS_PASSWORD="$REDIS_PASSWORD" \
        REDIS_TLS=false \
        ${DB_POOL_MAX:+DB_POOL_MAX="$DB_POOL_MAX"} \
        nohup java -jar "$ROOT/msa/$s-service/build/libs/vet-$s-1.0.0.jar" > "$LOGS/$s.log" 2>&1 &
    done
    for s in $SERVICES; do
        for _ in $(seq 1 60); do [ "$(health "$s")" = 200 ] && break; sleep 1; done
        echo "$s: /health $(health "$s")  $(grep -o 'Started .* seconds' "$LOGS/$s.log" | head -1)"
    done
}

status() {
    for s in $SERVICES; do
        pid="$(pid_of "$s")"
        mem="-"
        if [ -n "$pid" ] && [ $WIN = 1 ]; then mem="$(tasklist //FI "PID eq $pid" //FO CSV //NH 2>/dev/null | awk -F'","' '{gsub(/"/,"",$5); print $5}')"
        elif [ -n "$pid" ]; then mem="$(( $(ps -o rss= -p "$pid") / 1024 )) MiB (RSS)"; fi
        echo "$s: 포트 $(port_of "$s")  PID ${pid:--}  메모리 $mem  /health $(health "$s")"
    done
}

stop() {
    for s in $SERVICES; do
        pid="$(pid_of "$s")"
        [ -z "$pid" ] && { echo "$s: 실행 중이 아님"; continue; }
        if [ $WIN = 1 ]; then taskkill //PID "$pid" //F > /dev/null 2>&1; else kill "$pid"; fi && echo "$s: 끝냄 (PID $pid)"
    done
}

case "${1:-}" in
    start) start ;;
    status) status ;;
    stop) stop ;;
    *) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
