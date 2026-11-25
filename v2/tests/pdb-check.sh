#!/usr/bin/env bash
# PodDisruptionBudget(minAvailable: 1)이 노드 정비(drain) 때 복제본을 지키는지 본다 (kubeadm, 워커 2대).
#   1) 두 워커를 모두 cordon 한다 (새 Pod 를 놓을 곳이 없게)
#   2) 워커2 에서 앱 Pod 만 내보낸다 → 각 앱의 복제본이 워커1 의 하나만 남는다 (PDB 가 허락하는 1개)
#   3) 워커1 의 auth 를 내보내려 한다 → PDB 가 거부해야 한다
#   4) 원래대로 돌린다 (uncordon, 다시 배포해 두 노드에 나눔)
# MySQL 과 Redis 는 건드리지 않는다 (--pod-selector 로 앱만 고른다).
# Pod 의 /tmp 는 emptyDir 라서 --delete-emptydir-data 로 지워도 된다고 알려야 drain 이 진행된다 (임시 파일뿐이다).
#   KUBECONFIG=v2/_run/kubeconfig-kubeadm v2/tests/pdb-check.sh
set -u
APPS='app in (web,auth,clinic,reservation)'
show() { kubectl get pdb -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,MIN:.spec.minAvailable,HEALTHY:.status.currentHealthy,ALLOWED:.status.disruptionsAllowed --no-headers | grep -v kube-system; }

echo "■ 0) 지금 PDB (ALLOWED = 지금 내보내도 되는 Pod 수)"; show
echo; echo "■ 1) 두 워커를 cordon"; kubectl cordon vet2-w1 vet2-w2
echo; echo "■ 2) 워커2 에서 앱 Pod 만 내보낸다"
out=$(kubectl drain vet2-w2 --pod-selector="$APPS" --ignore-daemonsets --delete-emptydir-data --timeout=90s 2>&1)
echo "   내보낸 Pod: $(printf '%s
' "$out" | grep -c ' evicted$')개"; printf '%s
' "$out" | grep -E 'drained|error' | sed 's/^/   /'
sleep 3
echo; echo "■ 3) 이제 각 앱은 워커1 의 하나만 Ready (새 Pod 는 놓을 곳이 없어 Pending)"; show
kubectl get pods -A -l "$APPS" -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase --no-headers | grep -E ' auth-'
echo; echo "■ 4) 워커1 의 auth 를 내보내려 한다 (20초 제한)"
kubectl drain vet2-w1 --pod-selector=app=auth --ignore-daemonsets --delete-emptydir-data --timeout=20s 2>&1     | grep -oE '(evicting pod [a-z0-9/-]+|Cannot evict pod as it would violate the pod.s disruption budget|global timeout reached: 20s|node/vet2-w1 drained)' | sed -E 's/-[a-z0-9]+-[a-z0-9]+$//' | sort | uniq -c | sed 's/^/   /'
echo "   → auth 의 Pod 수: $(kubectl get pods -A -l app=auth --field-selector=status.phase=Running -o name | wc -l) (Running)"
[ -n "${STOP_FILE:-}" ] && touch "$STOP_FILE"   # 트래픽 측정은 여기까지 (다시 배포 구간과 섞지 않는다)
echo; echo "■ 5) 원래대로"
kubectl uncordon vet2-w1 vet2-w2
for ns in vet2 vet2-rds; do kubectl -n $ns rollout restart deploy web auth clinic reservation > /dev/null; done
for ns in vet2 vet2-rds; do for d in web auth clinic reservation; do kubectl -n $ns rollout status deploy/$d --timeout=300s > /dev/null; done; done
show
