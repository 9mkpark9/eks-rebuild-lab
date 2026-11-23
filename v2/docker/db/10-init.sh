#!/bin/bash
# db 이미지의 초기화 스크립트. 공식 MySQL 이미지의 진입 스크립트가 데이터 폴더가 비어 있을 때 한 번 실행한다.
# 그때는 임시 서버가 소켓으로만 떠 있고 root 비밀번호는 이미 설정되어 있다. 순서는 ① 문서 5.2 와 같다.
#
# 진입 스크립트의 함수(docker_process_sql)에 기대지 않고 mysql 을 직접 부른다.
# 이 파일이 실행 파일로 복사되면 별도 프로세스로 돌아서 그 함수가 보이지 않기 때문이다 (문제 C-8).
# 한 줄이라도 실패하면 거기서 멈춘다. 멈추지 않으면 빈 DB 가 "초기화 끝"으로 남는다.
set -euo pipefail

: "${DB_AUTH_PASSWORD:?DB_AUTH_PASSWORD 가 필요합니다}"
: "${DB_CLINIC_PASSWORD:?DB_CLINIC_PASSWORD 가 필요합니다}"
: "${DB_RESERVATION_PASSWORD:?DB_RESERVATION_PASSWORD 가 필요합니다}"

sql() { MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot --default-character-set=utf8mb4 "$@"; }

echo "[vet] 1) 스키마 4개와 서비스 계정 3개"
sql <<SQL
CREATE DATABASE vet_load        CHARACTER SET utf8mb4;
CREATE DATABASE vet_auth        CHARACTER SET utf8mb4;
CREATE DATABASE vet_clinic      CHARACTER SET utf8mb4;
CREATE DATABASE vet_reservation CHARACTER SET utf8mb4;
CREATE USER 'vet_auth'@'%'        IDENTIFIED BY '${DB_AUTH_PASSWORD}';
CREATE USER 'vet_clinic'@'%'      IDENTIFIED BY '${DB_CLINIC_PASSWORD}';
CREATE USER 'vet_reservation'@'%' IDENTIFIED BY '${DB_RESERVATION_PASSWORD}';
SQL

echo "[vet] 2) 테이블과 시드 (vet_load)"
sql vet_load < /opt/vet/db/schema.sql
# 시드는 지금(처음 뜨는 날)을 기준으로 만든다
node /opt/vet/db/gen-seed.mjs | sql vet_load

echo "[vet] 3) 서비스별 스키마로 옮기고 권한 주기"
sql < /opt/vet/db/split.sql
sql < /opt/vet/db/grants.sql
echo "[vet] 초기화 끝"
