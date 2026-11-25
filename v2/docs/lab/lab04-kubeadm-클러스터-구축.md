# [실습] lab04: kubeadm 클러스터 구축

| 속성 | 값 |
|---|---|
| 상위 항목 | ③ 쿠버네티스 전환 |
| 선행 작업 | [lab03: AWS 준비와 ECR](lab03-AWS-준비와-ECR.md) |
| 후속 작업 | [lab05: 앱 배포](lab05-앱-배포.md) |

EC2 3대에 kubeadm 으로 쿠버네티스 클러스터를 만든다. 컨트롤 플레인 1대를 초기화하고 워커 2대를 붙인 뒤, 네트워크 플러그인(Flannel)을 넣어 노드가 Ready 가 되는 것을 확인한다. 클러스터 DNS(CoreDNS)가 한 노드에 몰리는 것을 보고 두 노드에 나눈다. MySQL 이 쓸 볼륨을 워커 디스크에 등록한다.

## 실습 목표

- CloudFormation 으로 EC2 3대를 만들고, 각 노드가 준비 스크립트로 쿠버네티스 설치를 마친 것을 확인한다
- `kubeadm init` 으로 컨트롤 플레인을 만들고 `kubeadm join` 으로 워커 2대를 붙인다
- 네트워크 플러그인이 없을 때 노드가 NotReady, CoreDNS 가 Pending 인 것을 확인하고, Flannel 을 넣어 Ready 로 만든다
- CoreDNS 두 개가 한 노드에 놓이는 것을 확인하고 두 노드에 나눈다
- 클러스터 DNS 로 Service 이름이 해석되는 것을 확인한다

## 사전 준비

| 항목 | 내용 | 비고 |
|---|---|---|
| 클러스터 | 없음 (이 실습에서 만든다) | |
| 실행 위치 | 이 PC: AWS CLI 는 WSL, kubectl 은 Windows(Git Bash) | 이 실습의 출력은 이렇게 받았다. kubectl 이 있으면 WSL 하나로도 된다 |
| 노드 명령 | Session Manager 로 보낸다 (SSH 없음) | `bash v2/k8s/kubeadm/ssm-run.sh <인스턴스 ID> '<명령>'`, root 로 실행된다 |
| 스택 | `vet2-network` (lab03) | |
| 비용 | EC2 t3.medium × 3, 시간당 약 0.16달러 | 쓰지 않을 때는 멈춘다 (자원 정리) |
| 쿠버네티스 | v1.36.6, containerd, Flannel v0.28.11 | |
| 작업 디렉터리 | `~/vet2-lab` | lab03 의 변수(`AWS_REGION`, `MY_CIDR`, `REG`, `cf`)를 그대로 쓴다 |

## 1. EC2 3대

### 1. 스택 만들기

```bash
$ t0=$(date +%s); cf kubeadm; echo "$(( $(date +%s) - t0 ))초"
# 출력 예

Waiting for changeset to be created..
Waiting for stack create/update to complete
Successfully created/updated stack - vet2-kubeadm
188초
```

[kubeadm.yaml](../../infra/kubeadm.yaml) 은 시작 템플릿 하나로 EC2 3대(t3.medium, Ubuntu 24.04)를 만든다. 노드의 IAM 역할에는 Session Manager(`AmazonSSMManagedInstanceCore`)와 ECR 읽기 권한이 있다.

### 2. 노드 ID 와 주소

```bash
$ aws cloudformation describe-stacks --stack-name vet2-kubeadm --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table
# 출력 예
--------------------------------------------------
|                 DescribeStacks                 |
+------------------------+-----------------------+
|  ControlPlaneId        |  i-0bd41fd412279eb11  |
|  ControlPlanePrivateIp |  10.20.1.207          |
|  Worker1Id             |  i-068d3a128382bd51e  |
|  Worker2Id             |  i-020d6a9df47ea5ddd  |
+------------------------+-----------------------+

$ aws ec2 describe-instances --filters Name=tag:Project,Values=vet2 Name=instance-state-name,Values=pending,running \
    --query "Reservations[].Instances[].[Tags[?Key==\`Name\`]|[0].Value,InstanceType,PrivateIpAddress,State.Name]" --output table
# 출력 예
----------------------------------------------------
|                 DescribeInstances                |
+---------+-------------+---------------+----------+
|  vet2-cp|  t3.medium  |  10.20.1.207  |  running |
|  vet2-w1|  t3.medium  |  10.20.1.97   |  running |
|  vet2-w2|  t3.medium  |  10.20.1.132  |  running |
+---------+-------------+---------------+----------+
```

이후 명령이 쓸 변수를 만든다. 인스턴스 ID 와 주소는 환경마다 다르다.

```bash
$ out() { aws cloudformation describe-stacks --stack-name vet2-kubeadm --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
$ CP=$(out ControlPlaneId); W1ID=$(out Worker1Id); W2ID=$(out Worker2Id); CP_PRIV=$(out ControlPlanePrivateIp)
$ CP_PUB=$(aws ec2 describe-instances --instance-ids $CP --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
$ S=v2/k8s/kubeadm/ssm-run.sh
```

`CP_PUB` 는 컨트롤 플레인의 공인 IP 다. 이 PC 의 kubectl 이 이 주소로 API 서버에 붙는다. 이 문서의 출력에서는 `<CP 공인 IP>` 로 가렸다.

### 3. 노드 준비 확인

각 노드는 처음 켜질 때 시작 템플릿의 준비 스크립트(user-data)로 아래를 하고, 끝나면 `/var/lib/vet2-ready` 를 만든다.

| 순서 | 준비 스크립트가 하는 일 | 왜 |
|---|---|---|
| 1 | 호스트 이름 = 인스턴스의 Name 태그 (`vet2-cp` 등) | 노드 이름이 된다 |
| 2 | `swapoff -a` | 스왑이 켜져 있으면 kubelet 이 시작하지 않는다 |
| 3 | 커널 모듈 `overlay`, `br_netfilter`, `ip_forward = 1` | 컨테이너 파일 시스템과 Pod 네트워크에 필요하다 |
| 4 | containerd 설치, `SystemdCgroup = true` | kubelet 과 같은 cgroup 관리자를 쓰게 한다 |
| 5 | kubeadm·kubelet·kubectl v1.36 설치 (`pkgs.k8s.io`), 버전 고정 | |
| 6 | `/var/lib/vet2-mysql` 폴더 | lab05 의 MySQL 볼륨 자리 |

```bash
$ bash $S $CP 'test -f /var/lib/vet2-ready && hostname && kubeadm version -o short && tail -2 /var/log/vet2-prepare.log'
# 출력 예
vet2-cp
v1.36.6
+ mkdir -p /var/lib/vet2-mysql
+ touch /var/lib/vet2-ready

$ bash $S $W1ID 'hostname; swapon --show | wc -l; lsmod | grep -E "^(overlay|br_netfilter)" | cut -d" " -f1;
    sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables; grep SystemdCgroup /etc/containerd/config.toml;
    systemctl is-active containerd kubelet; ls -d /var/lib/vet2-mysql'
# 출력 예
vet2-w1
0
br_netfilter
overlay
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
            SystemdCgroup = true
active
activating
/var/lib/vet2-mysql
```

스왑 0줄, 모듈 2개, 커널 설정, cgroup 설정이 모두 맞다. kubelet 이 `activating` 인 것은 정상이다. 아직 클러스터 설정이 없어 시작했다 멈추기를 반복하고, `join` 뒤에 `active` 가 된다.

### 4. 결과 확인

| 항목 | 내용 |
|---|---|
| EC2 | vet2-cp, vet2-w1, vet2-w2 (t3.medium), 사설 IP 10.20.1.x |
| 준비 | 모든 노드에 containerd, kubeadm v1.36.6 |

## 2. 컨트롤 플레인과 워커

### 1. kubeadm init (vet2-cp)

```bash
$ bash $S $CP "kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-cert-extra-sans=$CP_PUB" 600
# 출력 예
[init] Using Kubernetes version: v1.36.6
[preflight] Running pre-flight checks
[preflight] Pulling images required for setting up a Kubernetes cluster
...(생략)...
[certs] apiserver serving cert is signed for DNS names [kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local vet2-cp] and IPs [10.96.0.1 10.20.1.207 <CP 공인 IP>]
...(생략)...
[etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
...(생략)...
[control-plane-check] kube-controller-manager is healthy after 6.548024ms
[control-plane-check] kube-scheduler is healthy after 10.614819ms
[control-plane-check] kube-apiserver is healthy after 2.002081778s
...(생략)...
[mark-control-plane] Marking the node vet2-cp as control-plane by adding the taints [node-role.kubernetes.io/control-plane:NoSchedule]
[bootstrap-token] Using token: <토큰>
...(생략)...
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!
...(생략)...
Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 10.20.1.207:6443 --token <토큰> \
	--discovery-token-ca-cert-hash sha256:<해시>
```

| 옵션 | 왜 |
|---|---|
| `--pod-network-cidr=10.244.0.0/16` | Pod 가 받을 IP 대역. Flannel 의 기본값과 맞춘다 |
| `--apiserver-cert-extra-sans=$CP_PUB` | API 서버 인증서에 공인 IP 를 넣는다. 출력의 `IPs [10.96.0.1 10.20.1.207 <CP 공인 IP>]` 가 그것이다. 넣지 않으면 이 PC 의 kubectl 이 인증서 확인에서 실패한다 |

kubeadm 이 인증서를 만들고, etcd·API 서버·컨트롤러 매니저·스케줄러를 **정적 Pod**(`/etc/kubernetes/manifests` 의 파일을 kubelet 이 직접 띄우는 Pod)로 띄웠다. 컨트롤 플레인 노드에는 `NoSchedule` taint 를 붙여 앱 Pod 가 올라가지 않게 했다. 마지막 줄의 `join` 명령에는 토큰과 CA 인증서 해시가 들어 있다. 이 문서에서는 `<토큰>`, `<해시>` 로 가렸다.

### 2. join 명령 만들기

```bash
$ JOIN=$(bash $S $CP 'kubeadm token create --print-join-command --ttl 1h' 60 | grep '^kubeadm join')
$ echo "$JOIN" | sed -E 's/--token [a-z0-9.]+/--token <토큰>/; s/sha256:[0-9a-f]+/sha256:<해시>/'
# 출력 예
kubeadm join 10.20.1.207:6443 --token <토큰> --discovery-token-ca-cert-hash sha256:<해시>
```

`init` 이 출력한 토큰은 24시간 유효하다. 새 토큰을 1시간짜리로 만들어 변수에만 담는다. 이 명령을 가진 사람은 누구나 노드를 붙일 수 있으므로 파일에 남기지 않는다.

### 3. 워커 붙이기 (vet2-w1, vet2-w2)

```bash
$ bash $S $W1ID "$JOIN" 300
# 출력 예
[preflight] Running pre-flight checks
[preflight] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
...(생략)...
[kubelet-start] Starting the kubelet
[kubelet-check] The kubelet is healthy after 502.388033ms
[kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap

This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The Kubelet was informed of the new secure connection details.

$ bash $S $W2ID "$JOIN" 300
# 출력 예
...(생략)...
This node has joined the cluster:
```

워커의 kubelet 이 토큰으로 API 서버에 인증서를 요청해 받았다(TLS Bootstrap). 이제부터 kubelet 은 이 인증서로 API 서버와 통신한다.

### 4. 이 PC 에서 kubectl

컨트롤 플레인의 관리자 설정(`admin.conf`)을 가져와 서버 주소를 공인 IP 로 바꾼다. 이 파일은 클러스터 관리자 권한이므로 내용을 화면에 출력하지 않고 `v2/_run/`(Git 밖)에만 둔다.

```bash
$ bash $S $CP 'base64 -w0 /etc/kubernetes/admin.conf' 60 | tr -d '\r\n' | base64 -d > v2/_run/kubeconfig-kubeadm
$ chmod 600 v2/_run/kubeconfig-kubeadm
$ sed -i "s#server: https://$CP_PRIV:6443#server: https://$CP_PUB:6443#" v2/_run/kubeconfig-kubeadm
$ export KUBECONFIG=$PWD/v2/_run/kubeconfig-kubeadm
```

`base64` 로 감싸 옮기는 것은 Session Manager 의 출력 처리에서 줄바꿈과 특수 문자가 바뀌지 않게 하려는 것이다. API 서버 포트 6443 은 보안 그룹이 이 PC 의 IP 에만 연다 (lab03).

Windows 의 kubectl 을 Git Bash 에서 쓸 때는 `KUBECONFIG` 를 `C:/...` 형식으로 준다 (`export KUBECONFIG="$(cygpath -m $PWD/v2/_run/kubeconfig-kubeadm)"`). `/c/...` 형식이면 Windows 의 kubectl 이 그 파일을 찾지 못하고 기본 설정으로 다른 곳에 붙는다. 이번 실습에서 `the server could not find the requested resource` 로 실패해 알게 되었다.

### 5. 결과 확인

```bash
$ kubectl get nodes -o wide
# 출력 예
NAME      STATUS     ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION           ...
vet2-cp   NotReady   control-plane   82s   v1.36.6   10.20.1.207   <none>        Ubuntu 24.04.5 LTS   7.0.0-1018-aws (amd64)   ...
vet2-w1   NotReady   <none>          65s   v1.36.6   10.20.1.97    <none>        Ubuntu 24.04.5 LTS   7.0.0-1018-aws (amd64)   ...
vet2-w2   NotReady   <none>          59s   v1.36.6   10.20.1.132   <none>        Ubuntu 24.04.5 LTS   7.0.0-1018-aws (amd64)   ...

$ kubectl -n kube-system get pods -o wide
# 출력 예
NAME                              READY   STATUS    RESTARTS   AGE   IP            NODE      ...
coredns-589f44dc88-5xzc4          0/1     Pending   0          72s   <none>        <none>    ...
coredns-589f44dc88-8ckws          0/1     Pending   0          72s   <none>        <none>    ...
etcd-vet2-cp                      1/1     Running   0          78s   10.20.1.207   vet2-cp   ...
kube-apiserver-vet2-cp            1/1     Running   0          78s   10.20.1.207   vet2-cp   ...
kube-controller-manager-vet2-cp   1/1     Running   0          78s   10.20.1.207   vet2-cp   ...
kube-proxy-ghv4j                  1/1     Running   0          65s   10.20.1.97    vet2-w1   ...
kube-proxy-m6mpq                  1/1     Running   0          59s   10.20.1.132   vet2-w2   ...
kube-proxy-zjxn5                  1/1     Running   0          72s   10.20.1.207   vet2-cp   ...
kube-scheduler-vet2-cp            1/1     Running   0          78s   10.20.1.207   vet2-cp   ...
```

| 항목 | 내용 |
|---|---|
| 노드 | 3대 모두 보이지만 `NotReady` |
| 컨트롤 플레인 | etcd, API 서버, 컨트롤러 매니저, 스케줄러가 vet2-cp 에서 Running (노드 IP 를 그대로 쓴다) |
| CoreDNS | `Pending`. Pod 네트워크가 없어 놓일 곳이 없다 |

## 3. Pod 네트워크 (Flannel)

### 1. 적용

```bash
$ kubectl apply -f https://github.com/flannel-io/flannel/releases/download/v0.28.11/kube-flannel.yml
# 출력 예
namespace/kube-flannel created
serviceaccount/flannel created
clusterrole.rbac.authorization.k8s.io/flannel created
clusterrolebinding.rbac.authorization.k8s.io/flannel created
configmap/kube-flannel-cfg created
daemonset.apps/kube-flannel-ds created

$ kubectl wait --for=condition=Ready node --all --timeout=300s
# 출력 예
node/vet2-cp condition met
node/vet2-w1 condition met
node/vet2-w2 condition met

$ kubectl get nodes
# 출력 예
NAME      STATUS   ROLES           AGE   VERSION
vet2-cp   Ready    control-plane   93s   v1.36.6
vet2-w1   Ready    <none>          76s   v1.36.6
vet2-w2   Ready    <none>          70s   v1.36.6
```

Flannel 은 DaemonSet 이라 노드마다 하나씩 뜬다. 노드마다 Pod 대역(10.244.x.0/24)을 나눠 주고, 노드 사이의 Pod 통신을 VXLAN(UDP 8472)으로 감싸 보낸다. 노드끼리 UDP 8472 를 여는 보안 그룹 규칙이 이것 때문이다.

### 2. CoreDNS 의 위치

```bash
$ kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
# 출력 예
NAME                       READY   STATUS              RESTARTS   AGE   IP       NODE      ...
coredns-589f44dc88-5xzc4   0/1     ContainerCreating   0          84s   <none>   vet2-w1   ...
coredns-589f44dc88-8ckws   0/1     ContainerCreating   0          84s   <none>   vet2-w1   ...
```

CoreDNS 두 개가 **모두 vet2-w1** 에 놓였다. kubeadm 이 넣은 CoreDNS 는 "되도록 다른 노드에" 규칙만 있어서, 먼저 Ready 가 된 노드에 둘 다 놓일 수 있다. 이 노드가 죽으면 클러스터 안의 이름 찾기가 모두 멈춘다. DB 를 쓰지 않는 요청까지 전부 실패한다 (③ K-10).

### 3. 결과 확인

| 항목 | 내용 |
|---|---|
| 노드 | 3대 Ready |
| Flannel | 노드마다 하나 (DaemonSet) |
| CoreDNS | 두 개가 한 노드(vet2-w1)에 |

## 4. 클러스터 DNS 와 볼륨

### 1. CoreDNS 를 두 노드에 나누기

① `v2/k8s/cluster/kubeadm/coredns-patch.yaml`

```yaml
spec:
  template:
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          nodeTaintsPolicy: Honor
          labelSelector:
            matchLabels:
              k8s-app: kube-dns
          matchLabelKeys: [pod-template-hash]
      tolerations:
        - { key: CriticalAddonsOnly, operator: Exists }
        - { key: node-role.kubernetes.io/control-plane, effect: NoSchedule }
        - { key: node.kubernetes.io/not-ready, operator: Exists, effect: NoExecute, tolerationSeconds: 30 }
        - { key: node.kubernetes.io/unreachable, operator: Exists, effect: NoExecute, tolerationSeconds: 30 }
```

| 설정 | 왜 |
|---|---|
| `whenUnsatisfiable: DoNotSchedule` | "되도록" 이 아니라 "반드시" 노드 사이의 개수 차이를 1 이하로 |
| `matchLabelKeys: [pod-template-hash]` | 교체 중에는 새 버전 Pod 끼리만 센다. 곧 내려갈 Pod 까지 세면 새 Pod 둘이 한 노드에 놓일 수 있다 |
| control-plane toleration | 컨트롤 플레인 노드에도 놓일 수 있게. 워커가 하나 죽어도 나머지 둘에 나뉜다 |
| `tolerationSeconds: 30` | 노드가 응답하지 않으면 기본 300초가 아니라 30초 뒤 다른 노드로 옮긴다 |

```bash
$ kubectl -n kube-system patch deploy coredns --patch-file v2/k8s/cluster/kubeadm/coredns-patch.yaml
# 출력 예
deployment.apps/coredns patched

$ kubectl -n kube-system rollout status deploy coredns --timeout=180s
# 출력 예
Waiting for deployment "coredns" rollout to finish: 1 old replicas are pending termination...
...(생략)...
deployment "coredns" successfully rolled out

$ kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
# 출력 예
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE      ...
coredns-5b88d67cc6-mp7pm   1/1     Running   0          4s    10.244.2.2   vet2-w2   ...
coredns-5b88d67cc6-qbxqv   1/1     Running   0          4s    10.244.0.2   vet2-cp   ...
```

패치로 Pod 템플릿이 바뀌어 새 CoreDNS 두 개가 vet2-w2 와 vet2-cp 에 하나씩 떴다. IP 가 Flannel 의 대역(10.244.x.x)이다.

### 2. 클러스터 DNS 확인

```bash
$ kubectl run dnstest --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default.svc.cluster.local
# 출력 예
pod/dnstest created

$ kubectl logs dnstest
# 출력 예
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	kubernetes.default.svc.cluster.local
Address: 10.96.0.1

$ kubectl delete pod dnstest
# 출력 예
pod "dnstest" deleted from default namespace
```

Pod 의 DNS 서버 10.96.0.10 은 CoreDNS 앞에 있는 Service(`kube-dns`)의 주소다. `kubernetes` Service 이름이 API 서버의 Service 주소 10.96.0.1 로 해석되었다.

### 3. MySQL 볼륨

① `v2/k8s/cluster/kubeadm/storage.yaml`

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vet2-local
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: vet2-mysql
spec:
  capacity:
    storage: 2Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: vet2-local
  local:
    path: /var/lib/vet2-mysql
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - { key: kubernetes.io/hostname, operator: In, values: [vet2-w1] }
```

kubeadm 클러스터에는 볼륨을 자동으로 만들어 주는 것(provisioner)이 없다. 그래서 vet2-w1 의 디스크 폴더를 PV 로 직접 등록한다. `nodeAffinity` 때문에 이 볼륨을 쓰는 MySQL Pod 는 항상 vet2-w1 에 놓인다. 데이터는 Pod 를 바꿔도 남지만, vet2-w1 이 죽으면 MySQL 도 다른 노드로 옮겨 가지 못한다 (③ K-11, 선택 과제의 RDS 가 이것을 푼다).

```bash
$ kubectl apply -f v2/k8s/cluster/kubeadm/storage.yaml
# 출력 예
storageclass.storage.k8s.io/vet2-local created
persistentvolume/vet2-mysql created

$ kubectl get storageclass,pv
# 출력 예
NAME                                     PROVISIONER                    RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
storageclass.storage.k8s.io/vet2-local   kubernetes.io/no-provisioner   Retain          WaitForFirstConsumer   false                  0s

NAME                          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   ...
persistentvolume/vet2-mysql   2Gi        RWO            Retain           Available           vet2-local     ...
```

PV 는 아직 아무도 쓰지 않아 `Available` 이다. lab05 에서 MySQL 이 요청하면 `Bound` 가 된다.

### 4. 결과 확인

```bash
$ kubectl get pods -A -o wide
# 출력 예
NAMESPACE      NAME                              READY   STATUS    RESTARTS   AGE    IP            NODE      ...
kube-flannel   kube-flannel-ds-bm47x             1/1     Running   0          32s    10.20.1.207   vet2-cp   ...
kube-flannel   kube-flannel-ds-jcmfb             1/1     Running   0          32s    10.20.1.132   vet2-w2   ...
kube-flannel   kube-flannel-ds-kvhtf             1/1     Running   0          32s    10.20.1.97    vet2-w1   ...
kube-system    coredns-5b88d67cc6-mp7pm          1/1     Running   0          11s    10.244.2.2    vet2-w2   ...
kube-system    coredns-5b88d67cc6-qbxqv          1/1     Running   0          11s    10.244.0.2    vet2-cp   ...
kube-system    etcd-vet2-cp                      1/1     Running   0          111s   10.20.1.207   vet2-cp   ...
kube-system    kube-apiserver-vet2-cp            1/1     Running   0          111s   10.20.1.207   vet2-cp   ...
kube-system    kube-controller-manager-vet2-cp   1/1     Running   0          111s   10.20.1.207   vet2-cp   ...
kube-system    kube-proxy-ghv4j                  1/1     Running   0          98s    10.20.1.97    vet2-w1   ...
kube-system    kube-proxy-m6mpq                  1/1     Running   0          92s    10.20.1.132   vet2-w2   ...
kube-system    kube-proxy-zjxn5                  1/1     Running   0          105s   10.20.1.207   vet2-cp   ...
kube-system    kube-scheduler-vet2-cp            1/1     Running   0          111s   10.20.1.207   vet2-cp   ...
```

| 항목 | 내용 |
|---|---|
| 노드 | 3대 Ready, v1.36.6 |
| 시스템 Pod | 모두 Running. CoreDNS 는 두 노드에 하나씩 |
| 볼륨 | StorageClass `vet2-local`, PV `vet2-mysql` (vet2-w1, 2Gi) |

## 자원 정리

클러스터는 lab05, lab06 에서 그대로 쓴다. 쉬는 동안 요금을 줄이려면 EC2 를 멈춘다.

```bash
$ aws ec2 stop-instances --instance-ids $CP $W1ID $W2ID
$ aws ec2 start-instances --instance-ids $CP $W1ID $W2ID          # 다시 켤 때
```

다시 켜면 공인 IP 가 바뀐다. 인증서에는 예전 공인 IP 가 들어 있으므로, kubeconfig 의 서버 주소를 새 IP 로 바꾸고 인증서에 들어 있는 이름 `kubernetes` 로 확인하게 한다.

```bash
$ CP_PUB=$(aws ec2 describe-instances --instance-ids $CP --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
$ kubectl config set-cluster kubernetes --server=https://$CP_PUB:6443 --tls-server-name=kubernetes
```

이 `set-cluster` 명령은 이번 실습에서 실행해 보지 않았다. 이 작업에서는 kubeconfig 파일의 `server:` 줄을 고치고 `tls-server-name: kubernetes` 줄을 직접 더해 같은 결과를 얻었다 (⑤ 문서 7.2).

| 항목 | 내용 |
|---|---|
| EC2 3대 | 멈추면 디스크 요금만 남는다 |
| 완전히 지우기 | `aws cloudformation delete-stack --stack-name vet2-kubeadm` (클러스터와 그 안의 데이터가 모두 사라진다) |

**한 번에 하기:** 1 ~ 4단계는 `v2/infra/stacks.sh up kubeadm` 뒤 `v2/infra/kubeadm-bootstrap.sh` 가 같은 순서로 실행한다 (lab05 의 앱 배포까지 한다).
