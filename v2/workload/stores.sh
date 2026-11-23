#!/usr/bin/env bash
# ① 워크로드 테스트 — 앱이 붙을 MySQL 과 Redis 를 공식 이미지 그대로 띄운다.
#
#   v2/workload/stores.sh up      v2-mysql (127.0.0.1:23306), v2-redis (127.0.0.1:26379)
#   v2/workload/stores.sh down    두 컨테이너를 지운다 (데이터도 함께 사라진다)
#
# 비밀번호는 처음 up 할 때 무작위로 만들어 v2/_run/secrets.env 에 둔다 (Git 에 올라가지 않는 폴더). 화면에 출력하지 않는다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN="$ROOT/v2/_run"
mkdir -p "$RUN/1-workload"

new_secret() { head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

case "${1:-}" in
up)
    if [ ! -f "$RUN/secrets.env" ]; then
        ( umask 077
          for k in DB_ROOT_PASSWORD DB_AUTH_PASSWORD DB_CLINIC_PASSWORD DB_RESERVATION_PASSWORD REDIS_PASSWORD; do
              echo "$k=$(new_secret)"
          done > "$RUN/secrets.env" )
        echo "비밀번호 파일을 만들었습니다: v2/_run/secrets.env"
    fi
    . "$RUN/secrets.env"
    docker run -d --name v2-mysql -p 127.0.0.1:23306:3306 -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PASSWORD" mysql:8.4 > /dev/null
    docker run -d --name v2-redis -p 127.0.0.1:26379:6379 redis:7-alpine redis-server --requirepass "$REDIS_PASSWORD" > /dev/null
    docker ps --filter name=v2- --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    ;;
down)
    docker rm -f v2-mysql v2-redis 2>/dev/null || true
    ;;
*)
    sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
