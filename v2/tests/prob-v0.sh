#!/usr/bin/env bash
# ③ 문제 장면 재현: 가장 단순한 배포(v0)를 이 PC 의 클러스터에 따로 띄워 K-1 ~ K-4 를 다시 보인다.
# 운영 중인 vet2 와 섞이지 않게 네임스페이스 vet2-v0, 포트 28085 로 띄우고 끝나면 지운다. v0/all.yaml 은 고치지 않는다.
#   v2/tests/prob-v0.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$ROOT"
. v2/tests/cap.sh
K="kubectl --context docker-desktop -n vet2-v0"
B=http://localhost:28085
R="$ROOT/v2/_run/3-k8s"; mkdir -p "$R"
command -v cygpath > /dev/null && R="$(cygpath -m "$R")"
set -a; . v2/_run/secrets.env; set +a
envsubst < v2/k8s/v0/all.yaml | sed -e 's/namespace: vet2$/namespace: vet2-v0/' -e 's/name: vet2$/name: vet2-v0/' -e 's/port: 28080, targetPort/port: 28085, targetPort/' > "$R/v0-rendered-v0ns.yaml"
kubectl --context docker-desktop apply -f "$R/v0-rendered-v0ns.yaml" > /dev/null
for d in mysql redis auth clinic reservation web; do $K rollout status deploy/$d --timeout=300s > /dev/null; done
for _ in $(seq 1 60); do [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' $B/api/notices)" = 200 ] && break; sleep 2; done

cap prob-k3-secret-visible "③ 문제 장면 K-3: 비밀번호가 배포 정보에 그대로 보인다 (v0)" bash -c "$K get deploy -o yaml | grep -n -A1 -E 'name: (SPRING_DATASOURCE_PASSWORD|SPRING_DATA_REDIS_PASSWORD|MYSQL_ROOT_PASSWORD|DB_[A-Z]+_PASSWORD)\$' | grep -E 'name:|value:' | head -12; echo; echo \"값이 그대로 나온 줄: \$($K get deploy -o yaml | grep -c -E 'value: \"?[0-9a-f]{36}')\""
cap prob-k4-besteffort "③ 문제 장면 K-4: 자원 요청·한도가 없다 (QoS BestEffort)" $K get pods -o custom-columns=POD:.metadata.name,QOS:.status.qosClass,REQUESTS:.spec.containers[0].resources.requests,LIMITS:.spec.containers[0].resources.limits
cap prob-k1-v0-rollout "③ 문제 장면 K-1: v0 를 다시 배포하는 동안 요청이 실패한다" bash v2/tests/k8s-ops.sh --base-url $B -n vet2-v0 --context docker-desktop --only 1
cap prob-k2-data-lost "③ 문제 장면 K-2: 볼륨 없는 MySQL Pod 를 지우면 예약이 사라진다 (v0)" bash v2/tests/k8s-ops.sh --base-url $B -n vet2-v0 --context docker-desktop --only 4

kubectl --context docker-desktop delete ns vet2-v0 --wait=false > /dev/null && echo "vet2-v0 를 지웠다"
