#!/bin/bash
# TC-07 정합성 검사 — 관리 EC2에서 실행 (bash deploy/aws.sh tc07). 문서 05장: 앞의 둘은 0행, 셋째는 두 값 일치.
set -euo pipefail
CLIENT=${CLIENT:-vet01}
REGION=${AWS_REGION:-ap-northeast-2}
command -v mysql >/dev/null || dnf install -y mariadb105 jq >/dev/null
DB=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$CLIENT-db" \
  --query "DBInstances[0].[Endpoint.Address,MasterUserSecret.SecretArn]" --output text)
DB_HOST=$(cut -f1 <<<"$DB"); MASTER_ARN=$(cut -f2 <<<"$DB")
MASTER=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$MASTER_ARN" --query SecretString --output text)
export MYSQL_PWD=$(jq -r .password <<<"$MASTER")
M="mysql -h $DB_HOST -u $(jq -r .username <<<"$MASTER") --default-character-set=utf8mb4 vet"

echo "--- TC-07 ① 같은 슬롯에 활성 예약 2건 이상 (0행이어야 함)"
$M -e "SELECT slot_id, COUNT(*) AS n FROM reservations WHERE status IN ('REQUESTED','CONFIRMED') GROUP BY slot_id HAVING n > 1"
c1=$($M -N -e "SELECT COUNT(*) FROM (SELECT slot_id FROM reservations WHERE status IN ('REQUESTED','CONFIRMED') GROUP BY slot_id HAVING COUNT(*) > 1) t")
echo "--- TC-07 ② 같은 반려동물·같은 날 활성 예약 2건 이상 (0행이어야 함)"
$M -e "SELECT pet_id, visit_date, COUNT(*) AS n FROM reservations WHERE status IN ('REQUESTED','CONFIRMED') GROUP BY pet_id, visit_date HAVING n > 1"
c2=$($M -N -e "SELECT COUNT(*) FROM (SELECT pet_id FROM reservations WHERE status IN ('REQUESTED','CONFIRMED') GROUP BY pet_id, visit_date HAVING COUNT(*) > 1) t")
echo "--- TC-07 ③ 채워진 슬롯 수 = 활성 예약 수"
read -r filled active < <($M -N -e "SELECT (SELECT COUNT(*) FROM slots WHERE reservation_id IS NOT NULL), (SELECT COUNT(*) FROM reservations WHERE status IN ('REQUESTED','CONFIRMED'))")
echo "filled_slots=$filled active_reservations=$active"
echo "--- TC-07 ④ WAS별 처리 건수 (seed 는 시드 데이터)"
$M -e "SELECT served_by, COUNT(*) AS n, SUM(status='CANCELLED') AS cancelled FROM reservations GROUP BY served_by ORDER BY n DESC"
r=PASS; [ "$c1" = 0 ] && [ "$c2" = 0 ] && [ "$filled" = "$active" ] || r=FAIL
echo "TC07_RESULT=$r (dup_slot=$c1 dup_pet_day=$c2 filled=$filled active=$active)"
