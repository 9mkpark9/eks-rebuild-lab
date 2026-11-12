# 공식 MySQL 이미지의 초기화 단계에서 source 로 읽힌다 (실행 권한 없음 = source).
# 데이터 폴더가 비어 있을 때 한 번만 돈다. 이 시점에 MYSQL_DATABASE 와 MYSQL_USER 는 이미 만들어져 있다.
#
# 1) 스키마  2) 오늘 날짜 기준 시드  3) 앱 계정 권한을 원본(db/init.sh)과 같게 좁힌다

: "${MYSQL_DATABASE:?MYSQL_DATABASE 가 필요합니다}"
: "${MYSQL_USER:?MYSQL_USER 가 필요합니다}"

mysql_note "vet: 스키마 적용"
docker_process_sql --database="$MYSQL_DATABASE" < /opt/vet/db/schema.sql

mysql_note "vet: 시드 생성 ($(date +%F) 부터 14일)"
node /opt/vet/db/gen-seed.mjs > /tmp/seed.sql
docker_process_sql --database="$MYSQL_DATABASE" < /tmp/seed.sql
rm -f /tmp/seed.sql

# 앱 계정: SELECT·INSERT·UPDATE 만, 공지 삭제(간호사)를 위해 notices 에만 DELETE.
# 공식 이미지는 MYSQL_USER 에 ALL 을 주므로 걷어 낸 뒤 다시 준다.
mysql_note "vet: 앱 계정 권한 설정"
docker_process_sql --database=mysql <<SQL
REVOKE ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* FROM '${MYSQL_USER}'@'%';
GRANT SELECT, INSERT, UPDATE ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
GRANT DELETE ON \`${MYSQL_DATABASE}\`.notices TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
SQL

docker_process_sql --database="$MYSQL_DATABASE" -N <<SQL
SELECT CONCAT('vet: slots=', (SELECT COUNT(*) FROM slots), ' reservations=', (SELECT COUNT(*) FROM reservations),
              ' users=', (SELECT COUNT(*) FROM users), ' notices=', (SELECT COUNT(*) FROM notices),
              ' first_slot=', (SELECT MIN(DATE(start_at)) FROM slots), ' now=', NOW());
SQL
