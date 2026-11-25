#!/usr/bin/env bash
# RDS 에 관리자(admin)로 SQL 을 보내고 결과를 표로 출력한다. 측정용.
# RDS 는 밖에서 접속할 수 없으므로 클러스터 안에 mysql 클라이언트 Pod 를 잠깐 띄워 실행한다.
# 비밀번호는 Secret vet-rds-admin 에서 Pod 가 직접 읽는다 (명령줄, Pod 명세, 화면에 나오지 않는다).
#
#   KUBECONFIG=v2/_run/kubeconfig-eks v2/tests/rds-sql.sh "SHOW GLOBAL STATUS LIKE 'Max_used_connections'"
set -euo pipefail
NS="${NS:-vet2-rds}"
SQL="${1:?SQL 을 주세요}"
export MSYS_NO_PATHCONV=1
HOST=$(kubectl -n "$NS" exec deploy/clinic -- printenv DB_HOST | tr -d '\r')
NAME="rds-sql-$(date +%s)"
# 인자는 JSON 문자열로 넘긴다 (SQL 의 따옴표 때문)
ARGS=$(node -e 'console.log(JSON.stringify(["mysql","-h",process.argv[1],"-uadmin","-t","-e",process.argv[2]]))' "$HOST" "$SQL")
kubectl -n "$NS" apply -f - > /dev/null <<EOF
{"apiVersion":"v1","kind":"Pod","metadata":{"name":"$NAME"},"spec":{"restartPolicy":"Never","containers":[{"name":"q","image":"mysql:8.4",
 "env":[{"name":"MYSQL_PWD","valueFrom":{"secretKeyRef":{"name":"vet-rds-admin","key":"password"}}}],"command":$ARGS}]}}
EOF
for _ in $(seq 1 60); do
    ph=$(kubectl -n "$NS" get pod "$NAME" -o jsonpath='{.status.phase}')
    [ "$ph" = Succeeded ] || [ "$ph" = Failed ] && break
    sleep 2
done
kubectl -n "$NS" logs "$NAME"
kubectl -n "$NS" delete pod "$NAME" --wait=false > /dev/null
