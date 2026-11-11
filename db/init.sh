#!/bin/bash
# DB 초기화 (문서 10.5) — 관리 EC2에서 Session Manager 명령으로 실행한다 (deploy/aws.sh dbinit).
# 비밀번호는 Secrets Manager에서 읽어 환경 변수로만 쓰고 명령줄이나 파일에 남기지 않는다.
set -euo pipefail
CLIENT=${CLIENT:-vet01}
REGION=${AWS_REGION:-ap-northeast-2}
: "${BUCKET:?BUCKET 이 필요합니다}"

command -v mysql >/dev/null || dnf install -y mariadb105 jq >/dev/null

DB=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$CLIENT-db" \
  --query "DBInstances[0].[Endpoint.Address,MasterUserSecret.SecretArn]" --output text)
DB_HOST=$(cut -f1 <<<"$DB"); MASTER_ARN=$(cut -f2 <<<"$DB")
MASTER=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$MASTER_ARN" --query SecretString --output text)
APP=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$CLIENT/db/app" --query SecretString --output text)
export MYSQL_PWD=$(jq -r .password <<<"$MASTER")
M="mysql -h $DB_HOST -u $(jq -r .username <<<"$MASTER") --default-character-set=utf8mb4"

mkdir -p /tmp/db && aws s3 cp "s3://$BUCKET/db/" /tmp/db --recursive --region "$REGION" --only-show-errors
$M -e "CREATE DATABASE IF NOT EXISTS vet CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci"
$M vet < /tmp/db/schema.sql      # 6장의 테이블과 회원·수의사·반려동물·공지
$M vet < /tmp/db/seed.sql        # 슬롯, 테스트 보호자 300명, 간호사 2명, 원장 3명, 공지
APP_PW=$(jq -r .password <<<"$APP")
# WAS 전용 계정: SELECT·INSERT·UPDATE 만 (10.3). 공지 삭제(간호사)를 위해 notices 에만 DELETE 를 더한다.
$M -e "CREATE USER IF NOT EXISTS 'vet_app'@'%' IDENTIFIED BY '$APP_PW';
       ALTER USER 'vet_app'@'%' IDENTIFIED BY '$APP_PW';
       GRANT SELECT, INSERT, UPDATE ON vet.* TO 'vet_app'@'%';
       GRANT DELETE ON vet.notices TO 'vet_app'@'%';"
echo "--- max_connections (57 이상이어야 함, 8장)"
$M -N -e "SHOW GLOBAL VARIABLES LIKE 'max_connections'"
echo "--- 데이터"
$M -N vet -e "SELECT 'slots', COUNT(*) FROM slots UNION ALL SELECT 'reservations', COUNT(*) FROM reservations UNION ALL SELECT 'users', COUNT(*) FROM users UNION ALL SELECT 'notices', COUNT(*) FROM notices"
$M -N vet -e "SELECT @@time_zone, NOW()"
