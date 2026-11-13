#!/bin/bash
# 예약 DB 를 처음 상태로 만든다: 스키마 → 오늘 기준 시드 → 서비스별 스키마·뷰 → 서비스 계정과 권한
#
# 두 군데에서 쓴다.
#   1) 컨테이너 DB (compose, dev): 공식 MySQL 이미지의 초기화 단계가 이 파일을 source 한다 (10-vet-init.sh).
#      데이터 폴더가 비어 있을 때만 돌므로, 컨테이너가 다시 뜨면 매번 처음 상태가 된다.
#   2) 바깥 DB (prod 의 RDS): 쿠버네티스 Job 이 `vet-provision` 으로 실행한다.
#      이미 초기화돼 있으면 아무것도 하지 않는다. 운영 데이터를 실수로 지우지 않기 위해서다.
#
# 환경 변수
#   VET_AUTH_PASSWORD, VET_CLINIC_PASSWORD, VET_RESERVATION_PASSWORD   서비스 계정의 비밀번호 (필수)
#   DB_HOST, DB_PORT(기본 3306), DB_ADMIN_USER, DB_ADMIN_PASSWORD       바깥 DB 일 때만
#   VET_FORCE=1                                                         이미 있어도 지우고 다시 만든다

VET_DB_DIR=/opt/vet/db

# 관리자 권한으로 SQL 을 실행한다. 컨테이너 초기화 중이면 공식 이미지의 함수(소켓, root)를 쓰고,
# 아니면 환경 변수의 주소와 관리자 계정으로 접속한다.
vet_admin_sql() {
  if declare -F docker_process_sql > /dev/null; then
    docker_process_sql "$@"
  else
    MYSQL_PWD="${DB_ADMIN_PASSWORD:?DB_ADMIN_PASSWORD 가 필요합니다}" mysql --protocol=tcp \
      --host="${DB_HOST:?DB_HOST 가 필요합니다}" --port="${DB_PORT:-3306}" \
      --user="${DB_ADMIN_USER:?DB_ADMIN_USER 가 필요합니다}" --default-character-set=utf8mb4 "$@"
  fi
}

vet_note() { echo "$(date '+%F %T%:z') [Note] [vet] $*"; }

vet_provision() {
  local name value
  for name in VET_AUTH_PASSWORD VET_CLINIC_PASSWORD VET_RESERVATION_PASSWORD; do
    value="${!name:-}"
    if [ -z "$value" ]; then echo "[vet] $name 이 필요합니다" >&2; return 1; fi
    # 비밀번호를 SQL 문자열에 넣으므로 따옴표와 역슬래시는 받지 않는다
    case "$value" in *\'*|*\\*) echo "[vet] $name 에 작은따옴표나 역슬래시를 쓸 수 없습니다" >&2; return 1;; esac
  done

  local existing
  existing=$(vet_admin_sql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'vet_reservation' AND table_name = 'reservations'") || return 1
  if [ "$existing" != "0" ] && [ "${VET_FORCE:-0}" != "1" ]; then
    vet_note "이미 초기화되어 있어 건너뜁니다 (지우고 다시 만들려면 VET_FORCE=1)"
    return 0
  fi

  vet_note "스키마 만들기"
  # 스키마끼리 외래 키로 서로 참조한다 (users.vet_id → vets, pets.owner_id → users).
  # 그대로 지우면 "참조되고 있다"며 막히므로, 지우는 동안만 외래 키 검사를 끈다.
  vet_admin_sql <<'SQL' || return 1
SET FOREIGN_KEY_CHECKS = 0;
DROP DATABASE IF EXISTS vet_load;
DROP DATABASE IF EXISTS vet_reservation;
DROP DATABASE IF EXISTS vet_clinic;
DROP DATABASE IF EXISTS vet_auth;
SET FOREIGN_KEY_CHECKS = 1;
CREATE DATABASE vet_load       CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE vet_auth        CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE vet_clinic      CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE vet_reservation CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
SQL

  vet_note "테이블과 시드 ($(date +%F) 부터 14일)"
  vet_admin_sql --database=vet_load < "$VET_DB_DIR/schema.sql" || return 1
  node "$VET_DB_DIR/gen-seed.mjs" > /tmp/vet-seed.sql || return 1
  vet_admin_sql --database=vet_load < /tmp/vet-seed.sql || return 1
  rm -f /tmp/vet-seed.sql

  vet_note "서비스별 스키마로 나누고 뷰 만들기"
  vet_admin_sql < "$VET_DB_DIR/split.sql" || return 1

  vet_note "서비스 계정과 권한"
  vet_admin_sql <<SQL || return 1
CREATE USER IF NOT EXISTS 'vet_auth'@'%'        IDENTIFIED BY '${VET_AUTH_PASSWORD}';
CREATE USER IF NOT EXISTS 'vet_clinic'@'%'      IDENTIFIED BY '${VET_CLINIC_PASSWORD}';
CREATE USER IF NOT EXISTS 'vet_reservation'@'%' IDENTIFIED BY '${VET_RESERVATION_PASSWORD}';
ALTER USER 'vet_auth'@'%'        IDENTIFIED BY '${VET_AUTH_PASSWORD}';
ALTER USER 'vet_clinic'@'%'      IDENTIFIED BY '${VET_CLINIC_PASSWORD}';
ALTER USER 'vet_reservation'@'%' IDENTIFIED BY '${VET_RESERVATION_PASSWORD}';
SQL
  vet_admin_sql < "$VET_DB_DIR/grants.sql" || return 1

  vet_admin_sql -N <<'SQL' || return 1
SELECT CONCAT('[vet] slots=', (SELECT COUNT(*) FROM vet_clinic.slots),
              ' reservations=', (SELECT COUNT(*) FROM vet_reservation.reservations),
              ' users=', (SELECT COUNT(*) FROM vet_auth.users),
              ' notices=', (SELECT COUNT(*) FROM vet_clinic.notices),
              ' first_slot=', (SELECT MIN(DATE(start_at)) FROM vet_clinic.slots),
              ' now=', NOW());
SQL
}

# source 로 읽혔으면(컨테이너 초기화) 함수만 부르고, 직접 실행됐으면(Job) 실패를 종료 코드로 돌려준다
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  vet_provision || { echo "[vet] 초기화 실패" >&2; exit 1; }
else
  set -o pipefail
  vet_provision || { echo "[vet] 초기화 실패" >&2; exit 1; }
fi
