#!/usr/bin/env bash
# RDS 를 쓰는 클러스터에서 시나리오 테스트를 돌린다 (DB 계정 경계 11번 포함).
# RDS 는 클러스터 밖에 있어 exec 할 DB Pod 가 없다. 그래서 mysql 클라이언트만 든 Pod(db-client)를 잠깐 띄워
# 그 안에서 RDS 로 서비스 계정 접속을 시도한다. 끝나면 그 Pod 를 지운다.
#
#   KUBECONFIG=v2/_run/kubeconfig-eks v2/tests/rds-check.sh http://<eks-rds 의 ALB 주소>
#   KUBECONFIG=v2/_run/kubeconfig-kubeadm v2/tests/rds-check.sh http://<워커 공인 IP>:30081
set -uo pipefail
NS="${NS:-vet2-rds}"   # 선택 과제(RDS) 구성의 네임스페이스
BASE="${1:?웹 주소를 주세요}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
set -a; . "$ROOT/v2/_run/secrets.env"; set +a
export MSYS_NO_PATHCONV=1   # Git Bash 가 Pod 안의 경로를 Windows 경로로 바꾸지 않게 한다
# 앱이 실제로 쓰는 DB 주소. ConfigMap 은 값이 바뀔 때마다 이름이 바뀐 새것이 생기고 옛것도 남으므로, ConfigMap 을 고르지 않고 Pod 에서 읽는다
HOST=$(kubectl -n "$NS" exec deploy/clinic -- printenv DB_HOST | tr -d '\r')
kubectl -n "$NS" delete pod db-client --ignore-not-found > /dev/null
kubectl -n "$NS" run db-client --image=mysql:8.4 --restart=Never --command -- sleep 3600 > /dev/null
kubectl -n "$NS" wait --for=condition=Ready pod/db-client --timeout=180s > /dev/null
SCN="$ROOT/v2/tests/scenario.mjs"
command -v cygpath > /dev/null && SCN="$(cygpath -m "$SCN")"   # Windows 의 node 는 /c/... 경로를 모른다
node "$SCN" --base-url "$BASE" --db-exec "kubectl -n "$NS" exec db-client --" --db-host "$HOST"
rc=$?
kubectl -n "$NS" delete pod db-client --wait=false > /dev/null
exit $rc
