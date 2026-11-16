#!/usr/bin/env bash
# ① 앱 — 서비스 3개를 컨테이너 없이 소스에서 빌드한 jar 로 직접 실행한다 (WSL 2 Ubuntu).
# 앱이 붙을 MySQL 과 Redis 만 컨테이너로 띄운다. 웹 서버는 띄우지 않는다.
#
#   scripts/run-app.sh build      소스를 빌드한다 (./gradlew build, 자동 테스트 포함)
#   scripts/run-app.sh up         MySQL, Redis 를 띄우고 서비스 3개를 실행한다
#   scripts/run-app.sh test       테스트 시나리오를 돌린다 (scripts/smoke.sh 를 서비스 주소로)
#   scripts/run-app.sh status     프로세스, 포트, /health 를 본다
#   scripts/run-app.sh restart    서비스 3개만 다시 실행한다 (DB 는 그대로. 데이터가 남는지 볼 때)
#   scripts/run-app.sh logs auth  서비스의 로그를 본다 (auth | clinic | reservation)
#   scripts/run-app.sh down       서비스를 끝내고 MySQL, Redis 컨테이너를 지운다
#
# 필요한 것: JDK 21, Docker, curl.
# 포트: auth 18081, clinic 18082, reservation 18083, MySQL 13306, Redis 16379 (모두 이 PC 안에서만 열린다)
# 비밀번호는 처음 up 할 때 무작위로 만들어 build/app-run/secrets.env 에 둔다 (Git 에 올라가지 않는 폴더). 화면에 출력하지 않는다.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT/build/app-run"
SECRETS="$RUN_DIR/secrets.env"
MYSQL=vet-app-mysql
REDIS=vet-app-redis
DB_IMAGE="${DB_IMAGE:-ghcr.io/9mkpark9/vet-db:1.0.0}"
SERVICES="auth clinic reservation"

port_of() { case "$1" in auth) echo 18081 ;; clinic) echo 18082 ;; reservation) echo 18083 ;; esac; }
jar_of() { ls "$ROOT/msa/$1-service/build/libs/"vet-"$1"-*.jar 2>/dev/null | grep -v -- '-plain\.jar$' | head -1; }
new_secret() { head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
health() { curl -s -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$(port_of "$1")/health" 2>/dev/null || true; }
alive() { [ -f "$RUN_DIR/$1.pid" ] && kill -0 "$(cat "$RUN_DIR/$1.pid")" 2>/dev/null; }

do_build() {
    java -version 2>&1 | head -1
    (cd "$ROOT/msa" && ./gradlew build) || exit 1
    echo
    for s in $SERVICES; do
        j=$(jar_of "$s"); [ -n "$j" ] && echo "jar: ${j#"$ROOT"/} ($(du -h "$j" | cut -f1))"
    done
}

load_secrets() {
    mkdir -p "$RUN_DIR"
    if [ ! -f "$SECRETS" ]; then
        ( umask 077
          { echo "MYSQL_ROOT_PASSWORD=$(new_secret)"
            echo "VET_AUTH_PASSWORD=$(new_secret)"
            echo "VET_CLINIC_PASSWORD=$(new_secret)"
            echo "VET_RESERVATION_PASSWORD=$(new_secret)"
            echo "REDIS_PASSWORD=$(new_secret)"; } > "$SECRETS" )
    fi
    set -a; . "$SECRETS"; set +a
}

start_infra() {
    if ! docker image inspect "$DB_IMAGE" >/dev/null 2>&1; then
        echo "DB 이미지($DB_IMAGE)가 없어 먼저 만든다."
        (cd "$ROOT" && docker compose build mysql) || exit 1
    fi
    if ! docker ps --format '{{.Names}}' | grep -qx "$MYSQL"; then
        docker rm -f "$MYSQL" >/dev/null 2>&1
        # -e 이름 만 주면 값은 이 셸의 환경 변수에서 넘어간다. 명령줄에 비밀번호가 남지 않는다.
        docker run -d --name "$MYSQL" -p 127.0.0.1:13306:3306 \
            -e MYSQL_ROOT_PASSWORD -e VET_AUTH_PASSWORD -e VET_CLINIC_PASSWORD -e VET_RESERVATION_PASSWORD \
            "$DB_IMAGE" >/dev/null || exit 1
        echo "MySQL 컨테이너를 띄웠다 ($MYSQL, 127.0.0.1:13306)"
    fi
    if ! docker ps --format '{{.Names}}' | grep -qx "$REDIS"; then
        docker rm -f "$REDIS" >/dev/null 2>&1
        docker run -d --name "$REDIS" -p 127.0.0.1:16379:6379 -e REDIS_PASSWORD redis:7-alpine \
            sh -c 'exec redis-server --save "" --appendonly no --requirepass "$REDIS_PASSWORD"' >/dev/null || exit 1
        echo "Redis 컨테이너를 띄웠다 ($REDIS, 127.0.0.1:16379)"
    fi
    printf 'DB 가 준비되기를 기다린다 (처음에는 스키마와 시드를 만든다) '
    for _ in $(seq 1 90); do
        users=$(docker exec "$MYSQL" vet-sql auth 'SELECT COUNT(*) FROM users' 2>/dev/null)
        [ -n "$users" ] && break
        printf '.'; sleep 2
    done
    echo
    [ -n "${users:-}" ] || { echo 'DB 가 준비되지 않았다. docker logs vet-app-mysql 을 본다.'; exit 1; }
    echo "DB 준비됨: 사용자 ${users}명"
}

start_services() {
    for s in $SERVICES; do
        jar=$(jar_of "$s")
        [ -n "$jar" ] || { echo "msa/$s-service 의 jar 가 없다. 먼저 scripts/run-app.sh build 를 실행한다."; exit 1; }
        if alive "$s"; then echo "$s 는 이미 실행 중이다 (PID $(cat "$RUN_DIR/$s.pid"))"; continue; fi
        pw_var="VET_$(echo "$s" | tr '[:lower:]' '[:upper:]')_PASSWORD"
        # 설정은 전부 환경 변수로 준다. 서비스마다 자기 스키마에 자기 계정으로 접속한다.
        SPRING_DATASOURCE_URL="jdbc:mysql://127.0.0.1:13306/vet_${s}?connectionTimeZone=LOCAL&characterEncoding=UTF-8" \
        SPRING_DATASOURCE_USERNAME="vet_$s" \
        SPRING_DATASOURCE_PASSWORD="${!pw_var}" \
        SPRING_DATA_REDIS_HOST=127.0.0.1 SPRING_DATA_REDIS_PORT=16379 SPRING_DATA_REDIS_PASSWORD="$REDIS_PASSWORD" \
        REDIS_TLS=false DB_POOL_MAX=3 APP_VERSION=app-local \
        nohup java -Dfile.encoding=UTF-8 -jar "$jar" "--server.port=$(port_of "$s")" > "$RUN_DIR/$s.log" 2>&1 &
        echo $! > "$RUN_DIR/$s.pid"
        echo "$s 실행: PID $!, 포트 $(port_of "$s"), 로그 build/app-run/$s.log"
    done
    for s in $SERVICES; do
        for _ in $(seq 1 90); do [ "$(health "$s")" = 200 ] && break; sleep 1; done
        echo "$s /health → $(health "$s")"
    done
}

stop_services() {
    for s in $SERVICES; do
        if alive "$s"; then
            pid=$(cat "$RUN_DIR/$s.pid"); kill "$pid" 2>/dev/null
            for _ in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
            kill -9 "$pid" 2>/dev/null
            echo "$s 를 끝냈다 (PID $pid)"
        fi
        rm -f "$RUN_DIR/$s.pid"
    done
}

do_status() {
    for s in $SERVICES; do
        if alive "$s"; then printf '%-12s 실행 중  PID %-7s 포트 %s  /health %s\n' "$s" "$(cat "$RUN_DIR/$s.pid")" "$(port_of "$s")" "$(health "$s")"
        else printf '%-12s 꺼짐\n' "$s"; fi
    done
    docker ps --filter "name=vet-app-" --format '{{.Names}}  {{.Status}}  {{.Ports}}'
}

do_test() {
    bash "$ROOT/scripts/smoke.sh" \
        --auth-url http://127.0.0.1:18081 --clinic-url http://127.0.0.1:18082 --reservation-url http://127.0.0.1:18083 \
        --db-exec "docker exec $MYSQL" "$@"
}

case "${1:-}" in
    build)   do_build ;;
    up)      load_secrets; start_infra; start_services; echo; echo '테스트: scripts/run-app.sh test' ;;
    test)    shift; do_test "$@" ;;
    status)  do_status ;;
    restart) load_secrets; stop_services; start_services ;;
    logs)    tail -n "${3:-60}" "$RUN_DIR/${2:?서비스 이름을 준다 (auth | clinic | reservation)}.log" ;;
    down)    stop_services; docker rm -f "$MYSQL" "$REDIS" >/dev/null 2>&1; rm -f "$SECRETS"; echo 'MySQL, Redis 컨테이너를 지웠다.' ;;
    *)       sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
