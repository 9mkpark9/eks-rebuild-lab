#!/bin/bash
# db 이미지의 초기화 스크립트. 두 곳에서 쓴다. 순서는 ① 문서 5.2 와 같다.
#
#   1) 이 이미지로 MySQL 을 띄울 때 (compose, 로컬 클러스터)
#      공식 MySQL 이미지의 진입 스크립트가 데이터 폴더가 비어 있을 때 한 번 실행한다.
#      그때는 임시 서버가 소켓으로만 떠 있고 root 비밀번호는 이미 설정되어 있다.
#   2) 밖의 DB(RDS)를 초기화할 때 (kubeadm, EKS 의 Job db-init, v2/k8s/rds/db-init.yaml)
#      DB_ADMIN_HOST, DB_ADMIN_USER, DB_ADMIN_PASSWORD 를 주고 이 파일을 직접 실행한다.
#      Job 은 다시 실행될 수 있으므로, 이미 끝난 DB 면 아무것도 하지 않고 끝난다.
#
# 진입 스크립트의 함수(docker_process_sql)에 기대지 않고 mysql 을 직접 부른다.
# 이 파일이 실행 파일로 복사되면 별도 프로세스로 돌아서 그 함수가 보이지 않기 때문이다 (문제 C-8).
# 한 줄이라도 실패하면 거기서 멈춘다. 멈추지 않으면 빈 DB 가 "초기화 끝"으로 남는다.
set -euo pipefail

: "${DB_AUTH_PASSWORD:?DB_AUTH_PASSWORD 가 필요합니다}"
: "${DB_CLINIC_PASSWORD:?DB_CLINIC_PASSWORD 가 필요합니다}"
: "${DB_RESERVATION_PASSWORD:?DB_RESERVATION_PASSWORD 가 필요합니다}"

ADMIN_USER="${DB_ADMIN_USER:-root}"
ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
HOST_OPT=()
[ -n "${DB_ADMIN_HOST:-}" ] && HOST_OPT=(-h "$DB_ADMIN_HOST" --protocol=tcp)
sql() { MYSQL_PWD="$ADMIN_PASSWORD" mysql "${HOST_OPT[@]}" -u"$ADMIN_USER" --default-character-set=utf8mb4 "$@"; }

if [ -n "${DB_ADMIN_HOST:-}" ]; then
    echo "[vet] 0) $DB_ADMIN_HOST 에 접속되는지 확인 (최대 5분)"
    for i in $(seq 1 60); do sql -N -e 'SELECT 1' > /dev/null 2>&1 && break; [ "$i" = 60 ] && { sql -e 'SELECT 1'; exit 1; }; sleep 5; done
    # 마지막 단계(권한)까지 끝났는지: reservation 의 slots 뷰와 vet_reservation 계정이 있는가
    done_mark=$(sql -N -e "SELECT (SELECT COUNT(*) FROM information_schema.views WHERE table_schema='vet_reservation' AND table_name='slots') + (SELECT COUNT(*) FROM mysql.user WHERE user='vet_reservation')")
    started=$(sql -N -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name LIKE 'vet\_%'")
    if [ "$done_mark" = 2 ]; then echo "[vet] 이미 초기화된 DB 입니다. 아무것도 하지 않습니다."; exit 0; fi
    if [ "$started" != 0 ]; then
        echo "[vet] 초기화가 중간에 멈춘 DB 입니다 (vet_ 스키마 $started 개). 자동으로 이어 하지 않습니다. 지우고 다시 하세요 (⑤ 문서)." >&2
        exit 1
    fi
fi

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
