#!/usr/bin/env bash
# 스택 vet2-kubeadm 의 EC2 3대로 쿠버네티스 클러스터를 만들고 앱까지 올린다 (③ 9장의 순서).
#   v2/infra/kubeadm-bootstrap.sh
#
# 1) 세 노드의 준비(user-data)가 끝나기를 기다린다
# 2) 컨트롤 플레인에서 kubeadm init (API 서버 인증서에 공인 IP 를 넣는다)
# 3) 워커 2대 kubeadm join (토큰은 화면과 파일에 남기지 않는다)
# 4) kubeconfig 를 v2/_run/kubeconfig-kubeadm 으로 받아 온다 (Git 밖)
# 5) Flannel, CoreDNS 분산(③ K-10), 노드 디스크 볼륨(③ K-6)
# 6) Secret, ECR 로그인 Secret(③ K-5, 12시간), 앱 적용
set -euo pipefail
export AWS_PAGER="" MSYS_NO_PATHCONV=1
REGION="${AWS_REGION:-ap-northeast-2}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
SSM="v2/k8s/kubeadm/ssm-run.sh"
FLANNEL=v0.28.11
out() { aws --region "$REGION" cloudformation describe-stacks --stack-name vet2-kubeadm --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text | tr -d '\r'; }
CP=$(out ControlPlaneId); W1=$(out Worker1Id); W2=$(out Worker2Id); CP_PRIV=$(out ControlPlanePrivateIp)
CP_PUB=$(aws --region "$REGION" ec2 describe-instances --instance-ids "$CP" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text | tr -d '\r')
mkdir -p v2/_run
KC="v2/_run/kubeconfig-kubeadm"

echo "1) 노드 준비 기다리기"
for i in "$CP" "$W1" "$W2"; do
    for _ in $(seq 1 60); do
        bash "$SSM" "$i" 'test -f /var/lib/vet2-ready' 30 > /dev/null 2>&1 && break
        sleep 10
    done
    echo "   $i 준비됨: $(bash "$SSM" "$i" 'hostname; kubeadm version -o short' 30 | tr '\n' ' ')"
done

echo "2) kubeadm init"
bash "$SSM" "$CP" "kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-cert-extra-sans=$CP_PUB > /var/log/vet2-init.log 2>&1 && grep -E 'initialized successfully' /var/log/vet2-init.log" 600

echo "3) kubeadm join"
JOIN=$(bash "$SSM" "$CP" 'kubeadm token create --print-join-command --ttl 1h' 60 | grep '^kubeadm join' | tr -d '\r')
for w in "$W1" "$W2"; do bash "$SSM" "$w" "$JOIN 2>&1 | grep -E 'This node has joined'" 300; done

echo "4) kubeconfig"
bash "$SSM" "$CP" 'base64 -w0 /etc/kubernetes/admin.conf' 60 | tr -d '\r\n' | base64 -d > "$KC"
chmod 600 "$KC"
sed -i "s#server: https://$CP_PRIV:6443#server: https://$CP_PUB:6443#" "$KC"
export KUBECONFIG="$(cygpath -m "$ROOT/$KC" 2>/dev/null || echo "$ROOT/$KC")"
P() { cygpath -m "$ROOT/$1" 2>/dev/null || echo "$ROOT/$1"; }

echo "5) 네트워크 플러그인, CoreDNS, 볼륨"
curl -sL -m 30 -o v2/_run/kube-flannel-$FLANNEL.yml "https://github.com/flannel-io/flannel/releases/download/$FLANNEL/kube-flannel.yml"
kubectl apply -f "$(P v2/_run/kube-flannel-$FLANNEL.yml)" > /dev/null
kubectl wait --for=condition=Ready node --all --timeout=300s
kubectl -n kube-system patch deploy coredns --patch-file "$(P v2/k8s/cluster/kubeadm/coredns-patch.yaml)" > /dev/null
kubectl -n kube-system rollout status deploy coredns --timeout=180s > /dev/null
kubectl apply -f "$(P v2/k8s/cluster/kubeadm/storage.yaml)" > /dev/null

echo "6) Secret 과 앱 — 필수 구성 (네임스페이스 vet2, 클러스터 안 MySQL)"
bash v2/k8s/secrets.sh -n vet2
bash v2/k8s/kubeadm/ecr-pull-secret.sh -n vet2
bash v2/k8s/apply.sh kubeadm > /dev/null
for d in web auth clinic reservation redis; do kubectl -n vet2 rollout status deploy/$d --timeout=300s > /dev/null; done
kubectl -n vet2 rollout status sts/mysql --timeout=300s > /dev/null
kubectl -n vet2 get pods -o wide
echo "웹: http://<워커 공인 IP>:30080"

# 선택 과제 "RDS 로 DB 전환": 스택 vet2-rds 가 있을 때만 같은 클러스터에 따로 띄운다 (네임스페이스 vet2-rds)
if aws --region "${AWS_REGION:-ap-northeast-2}" cloudformation describe-stacks --stack-name vet2-rds > /dev/null 2>&1; then
    echo "7) 선택 구성 (네임스페이스 vet2-rds, RDS)"
    bash v2/k8s/secrets.sh -n vet2-rds
    bash v2/k8s/rds-secret.sh -n vet2-rds
    bash v2/k8s/kubeadm/ecr-pull-secret.sh -n vet2-rds
    bash v2/k8s/apply.sh kubeadm-rds > /dev/null
    kubectl -n vet2-rds wait --for=condition=complete job/db-init --timeout=300s > /dev/null
    for d in web auth clinic reservation redis; do kubectl -n vet2-rds rollout status deploy/$d --timeout=300s > /dev/null; done
    echo "웹 (RDS): http://<워커 공인 IP>:30081"
fi
