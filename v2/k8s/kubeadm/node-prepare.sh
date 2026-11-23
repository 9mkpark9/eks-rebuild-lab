#!/bin/bash
# EC2 (Ubuntu 24.04) 를 쿠버네티스 노드로 준비한다. 인스턴스를 만들 때 user-data 로 넣는다.
# 맨 위의 NODE_NAME 줄은 만들 때 붙인다 (vet2-cp, vet2-w1, vet2-w2).
# 끝나면 /var/lib/vet2-ready 를 만든다. kubeadm init / join 은 여기서 하지 않는다 (출력을 남기려고 따로 실행한다).
set -euxo pipefail
exec > /var/log/vet2-prepare.log 2>&1
K8S_MINOR=v1.36

hostnamectl set-hostname "$NODE_NAME"

# 1) kubelet 은 스왑이 켜져 있으면 뜨지 않는다 (EC2 Ubuntu 는 원래 스왑이 없다. 혹시 몰라 끈다)
swapoff -a

# 2) 컨테이너 네트워크에 필요한 커널 모듈과 설정
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# 3) 컨테이너 런타임: containerd. kubelet 과 같은 cgroup 관리자(systemd)를 쓰게 한다
apt-get update
apt-get install -y containerd apt-transport-https ca-certificates curl gpg
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# 4) kubeadm, kubelet, kubectl (쿠버네티스 공식 저장소)
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/$K8S_MINOR/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$K8S_MINOR/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

touch /var/lib/vet2-ready
