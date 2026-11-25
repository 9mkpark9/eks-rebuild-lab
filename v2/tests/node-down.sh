#!/usr/bin/env bash
# 노드 장애: kubeadm 의 워커 하나를 강제로 멈추고, 필수 구성(vet2, NodePort 30080)과 RDS 구성(vet2-rds, 30081)에
# 동시에 요청을 보내며 5초마다 상태를 본다. 끝나면 워커를 다시 켜고 Pod 를 두 노드에 다시 나눈다.
#   W1=<워커1 공인 IP> W2=<워커2 공인 IP> v2/tests/node-down.sh <instance-id> <노드 이름> <요청을 보낼 IP> [관찰 초]
set -u
ID="$1"; NODE="$2"; IP="$3"; SECS="${4:-240}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$ROOT"
W="$ROOT/v2/_run/ops"; mkdir -p "$W"; command -v cygpath > /dev/null && W="$(cygpath -m "$W")"
T="$(cygpath -m "$ROOT/v2/tests/traffic.mjs" 2>/dev/null || echo "$ROOT/v2/tests/traffic.mjs")"
export AWS_PAGER=""
rm -f "$W/stop-nd"
node "$T" --base-url "http://$IP:30080" --seconds 900 --label "필수 구성 vet2 (DB: 클러스터 안 MySQL)" --stop-file "$W/stop-nd" > "$W/nd-vet2.txt" 2>&1 &
node "$T" --base-url "http://$IP:30081" --seconds 900 --label "RDS 구성 vet2-rds (DB: RDS)" --stop-file "$W/stop-nd" > "$W/nd-rds.txt" 2>&1 &
sleep 5
ready() { kubectl -n "$1" get deploy --no-headers 2>/dev/null | awk '{printf "%s=%s ", $1, $2}'; }
t0=$(date +%s)
echo "+0s   $NODE 강제 중지 요청: $(aws --region ap-northeast-2 ec2 stop-instances --instance-ids "$ID" --force --query 'StoppingInstances[0].CurrentState.Name' --output text)"
last=""
while [ $(( $(date +%s) - t0 )) -lt "$SECS" ]; do
    st=$(kubectl get node "$NODE" --no-headers 2>/dev/null | awk '{print $2}')
    db=$(kubectl -n vet2 get pod mysql-0 --no-headers 2>/dev/null | awk '{print $3}')
    line="노드=$st | vet2: $(ready vet2)mysql-0=$db | vet2-rds: $(ready vet2-rds)"
    [ "$line" != "$last" ] && echo "+$(( $(date +%s) - t0 ))s  $line"
    last="$line"; sleep 5
done
touch "$W/stop-nd"; wait
echo; grep -h '트래픽' "$W/nd-vet2.txt" "$W/nd-rds.txt"
echo; echo "■ $NODE 다시 켜기"
aws --region ap-northeast-2 ec2 start-instances --instance-ids "$ID" --query 'StartingInstances[0].CurrentState.Name' --output text > /dev/null
kubectl wait --for=condition=Ready "node/$NODE" --timeout=400s
s=$(date +%s); until [ "$(kubectl -n vet2 get pod mysql-0 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" = true ]; do sleep 3; [ $(( $(date +%s) - s )) -gt 300 ] && break; done
echo "노드가 Ready 된 뒤 mysql-0 이 다시 준비되기까지 $(( $(date +%s) - s ))초"
for n in vet2 vet2-rds; do kubectl -n $n rollout restart deploy web auth clinic reservation > /dev/null; done
for n in vet2 vet2-rds; do for d in web auth clinic reservation; do kubectl -n $n rollout status deploy/$d --timeout=300s > /dev/null; done; done
echo "Pod 를 두 노드에 다시 나눴다 (rollout restart)"
