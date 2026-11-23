#!/usr/bin/env bash
# ① 워크로드 테스트 — 빈 MySQL 에 앱이 요구하는 스키마, 시드, 서비스 계정을 넣는다.
# 입력은 소스에 있는 SQL 뿐이다: db/schema.sql, db/gen-seed.mjs, msa/db/split.sql, msa/db/grants.sql
#
#   v2/workload/db-init.sh            (v2-mysql 컨테이너에 넣는다)
#
# 비밀번호는 v2/_run/secrets.env 에서 읽고 화면에 출력하지 않는다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN="$ROOT/v2/_run"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-v2-mysql}"
. "$RUN/secrets.env"

# root 로 SQL 을 실행한다. 비밀번호는 명령줄이 아니라 컨테이너의 환경 변수(MYSQL_PWD)로 넘긴다.
sql() { docker exec -i -e MYSQL_PWD="$DB_ROOT_PASSWORD" "$MYSQL_CONTAINER" mysql -uroot --default-character-set=utf8mb4 "$@"; }

# MySQL 이 준비될 때까지 기다린다. 소켓이 아니라 TCP 로 묻는다.
# 공식 이미지는 처음 뜰 때 임시 서버를 소켓으로만 먼저 띄우므로(port 0), 소켓으로 물으면 준비 전인데도 답이 온다.
echo "0) MySQL 준비 기다리기 (TCP 3306)"
t0=$(date +%s)
until docker exec -e MYSQL_PWD="$DB_ROOT_PASSWORD" "$MYSQL_CONTAINER" mysql -h127.0.0.1 -P3306 --protocol=tcp -uroot -e 'SELECT 1' > /dev/null 2>&1; do
    [ $(( $(date +%s) - t0 )) -gt 120 ] && { echo "120초 안에 준비되지 않았습니다." >&2; exit 1; }
    sleep 1
done
echo "   준비됨 ($(( $(date +%s) - t0 ))초 기다림)"

echo "1) 스키마 4개 만들기"
sql <<'SQL'
CREATE DATABASE vet_load        CHARACTER SET utf8mb4;
CREATE DATABASE vet_auth        CHARACTER SET utf8mb4;
CREATE DATABASE vet_clinic      CHARACTER SET utf8mb4;
CREATE DATABASE vet_reservation CHARACTER SET utf8mb4;
SQL

echo "2) 테이블 만들기 (db/schema.sql → vet_load)"
sql vet_load < "$ROOT/db/schema.sql"

echo "3) 오늘 기준 시드 만들어 넣기 (db/gen-seed.mjs → vet_load)"
node "$ROOT/db/gen-seed.mjs" > "$RUN/seed.sql"
tail -1 "$RUN/seed.sql"
sql vet_load < "$RUN/seed.sql"

echo "4) 서비스 계정 3개 만들기"
sql <<SQL
CREATE USER 'vet_auth'@'%'        IDENTIFIED BY '$DB_AUTH_PASSWORD';
CREATE USER 'vet_clinic'@'%'      IDENTIFIED BY '$DB_CLINIC_PASSWORD';
CREATE USER 'vet_reservation'@'%' IDENTIFIED BY '$DB_RESERVATION_PASSWORD';
SQL

echo "5) 테이블을 서비스별 스키마로 옮기고 뷰 만들기 (msa/db/split.sql)"
sql < "$ROOT/msa/db/split.sql"

echo "6) 서비스 계정에 권한 주기 (msa/db/grants.sql)"
sql < "$ROOT/msa/db/grants.sql"

echo "끝. 스키마별 테이블과 뷰:"
sql -t -e "SELECT table_schema, table_name, table_type FROM information_schema.tables WHERE table_schema LIKE 'vet\_%' ORDER BY 1, 3, 2"
