#!/bin/bash
# vet-sql <auth|clinic|reservation> "<SQL>"
# 그 서비스의 DB 계정으로, 그 서비스의 스키마에서 SQL 한 줄을 실행한다.
# 헬스 체크와 "남의 데이터에 손댈 수 없는가" 확인(scripts/smoke.ps1)에 쓴다.
# 비밀번호는 컨테이너의 환경 변수에서 읽는다. 바깥 DB 를 볼 때는 DB_HOST, DB_PORT 를 준다.
set -euo pipefail

service="${1:-}"
shift || true
case "$service" in
  auth)        password="${VET_AUTH_PASSWORD:?VET_AUTH_PASSWORD 가 필요합니다}" ;;
  clinic)      password="${VET_CLINIC_PASSWORD:?VET_CLINIC_PASSWORD 가 필요합니다}" ;;
  reservation) password="${VET_RESERVATION_PASSWORD:?VET_RESERVATION_PASSWORD 가 필요합니다}" ;;
  *) echo '사용법: vet-sql <auth|clinic|reservation> "<SQL>"' >&2; exit 2 ;;
esac

MYSQL_PWD="$password" exec mysql --protocol=tcp --host="${DB_HOST:-127.0.0.1}" --port="${DB_PORT:-3306}" \
  --user="vet_${service}" --database="vet_${service}" --default-character-set=utf8mb4 -N -e "$*"
