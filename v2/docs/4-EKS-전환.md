# ④ EKS 전환

③의 kubeadm 배포를 Amazon EKS 로 옮긴 기록이다.
③에서 쓴 배포 파일을 **그대로 올려서 무엇이 안 되는지부터** 보고, 걸린 것을 하나씩 고쳤다.
여기 실린 명령과 출력은 모두 2026-11-23 에 직접 실행한 것이다. AWS 계정 번호와 IP 는 가렸다.

## 1. 결과

| 점검 기준 | kubeadm 배포 파일 그대로 | 최종 | 근거 |
|---|---|---|---|
| 시나리오 테스트 전부 통과 (ALB 를 거쳐서) | 밖에서 접속할 길이 없음, MySQL 안 뜸 | **통과 65 / 65** | E-1, E-2, 6.1 |
| 배포·업데이트·롤백 중 실패한 요청 0 | - | 0건 | 6.2 |
| Pod 를 지우면 스스로 복구 | - | 실패 0건 | 6.2 |
| DB Pod 를 교체해도 데이터 유지 | - | 통과 (교체 17초 동안 DB 요청 실패) | 6.2 |
| 노드가 없어져도 서비스 지속 | - | 앱은 실패 0건. DB 는 다른 노드로 옮겨 감 | 6.3 |
| ③의 숙제: ECR 을 Secret 없이 | **처음부터 됨** | 통과 | 4.2 |
| ③의 숙제: DB 가 다른 노드로 옮겨 가는가 (K-11) | - | **옮겨 감** (같은 가용 영역 안에서) | 6.3 |
| 다 지운 뒤 과금 자원이 남지 않음 | - | 지우지 않고 멈춤 (사용자 결정, 8장) | |

만난 문제는 4건이다.

| 번호 | 문제 | 상태 |
|---|---|---|
| E-1 | 웹에 밖에서 접속할 길이 없다 (NodePort 만 있음) | 해결 — ALB |
| E-2 | MySQL 의 볼륨이 만들어지지 않는다. 클러스터에 있는 `gp2` 로도 안 된다 | 해결 — Auto Mode 용 StorageClass |
| E-3 | 노드가 하나 빠지자 모든 Pod 가 남은 노드 1대에 몰렸다 | 해결 — `minDomains`, 가용 영역 분산 |
| E-4 | DB 를 지키려고 붙인 표시 때문에 노드를 지워도 24시간 동안 지워지지 않는다 | **맞바꿈** — 직접 옮기는 절차로 |

예상했는데 일어나지 않은 것도 기록한다.

| 예상 | 결과 |
|---|---|
| 새로 포맷한 EBS 에 `lost+found` 폴더가 있어 MySQL 이 초기화를 거부한다 | 폴더는 있었지만(`drwxrws--- lost+found`) MySQL 8.4 는 초기화를 마쳤다. **재현 안 됨** |
| ALB 가 내려가는 Pod 를 늦게 빼서 배포 중 502 가 난다 | `preStop: sleep 5` 그대로 실패 0건. **재현 안 됨** |
| 클러스터 DNS 가 한 노드에 몰린다 (③ K-10) | Auto Mode 에서는 CoreDNS 가 Pod 로 보이지 않는다(`kube-system` 에 Pod 없음). 노드마다 들어 있는 것으로 보이며, 노드를 지운 실험들에서 DNS 실패는 없었다 |

## 2. 환경

| 항목 | 값 |
|---|---|
| 클러스터 | EKS 1.36 (플랫폼 eks.19), **Auto Mode** |
| 노드 | Auto Mode 가 고름: `c5a.large` (2 vCPU, 4GiB), Bottlerocket OS. 처음 2대 |
| 네트워크 | ③의 `vet2-vpc` 에 퍼블릭 서브넷을 하나 더해 2개 (ap-northeast-2a, 2c). NAT 없음 |
| API 접속 | 공개 엔드포인트를 이 PC 의 IP 에만 열었다 |
| 밖으로 여는 법 | Ingress → ALB (internet-facing), 이 PC 의 IP 에서만 |
| 볼륨 | EBS gp3 2GiB, 암호화 |
| 이미지 | ③과 같은 ECR |
| IAM | 클러스터 역할 `vet2-eks-cluster` (Auto Mode 정책 5개), 노드 역할 `vet2-eks-node` (`AmazonEKSWorkerNodeMinimalPolicy`, `AmazonEC2ContainerRegistryPullOnly`) |

eksctl 은 설치하지 않았다. AWS CLI 로만 만들어 명령을 그대로 남겼다.

**Auto Mode 를 고른 이유.** 일반 EKS 에서 ALB 와 EBS 를 쓰려면 AWS Load Balancer Controller 와 EBS CSI 드라이버를 따로 설치하고, 각각 IAM 권한을 연결해야 한다. Auto Mode 에는 둘이 들어 있다. 대신 노드를 직접 고르거나 멈출 수 없고, AWS 가 노드를 정리하는 동작이 생긴다. 그것이 E-3, E-4 다.

```
                   이 PC (IP 하나에만 열림)
                          │ http
                          ▼
                 ALB (internet-facing)  ─ 대상: Pod 의 IP (target-type ip)
          ┌───────────────┴───────────────┐
  ap-northeast-2a                  ap-northeast-2c
  노드 (c5a.large)                 노드 (c5a.large)
  web, auth, clinic, reservation   web, auth, clinic, reservation
  mysql-0 ── EBS (2a)              redis
```

## 3. 만든 것

```
v2/k8s/
├── cluster/eks/
│   ├── storage.yaml       StorageClass vet2-ebs (E-2)
│   └── alb.yaml           IngressClass vet2-alb (E-1)
└── overlays/eks/
    ├── kustomization.yaml kubeadm 과 다른 것: 볼륨, Ingress, 노드·영역 분산, 정리 예외
    ├── ingress.yaml
    └── namespace.yaml
```

`apply.sh` 가 적용할 때 `ECR_REGISTRY`(계정 번호)와 `MY_CIDR`(이 PC 의 IP)를 채워 넣는다. 둘 다 Git 에 적지 않는다.

kubeadm 과 달라진 점은 overlay 하나에 모였다. base 는 ③과 같다.

| | kubeadm (③) | EKS (④) |
|---|---|---|
| 밖으로 | NodePort 30080 | Ingress → ALB |
| MySQL 볼륨 | 워커1 의 디스크 (local PV) | EBS (`vet2-ebs`) |
| ECR 로그인 | Secret, 12시간 | 없음 (노드 IAM 역할) |
| 클러스터 DNS | 직접 나눠 둠 (③ K-10) | Auto Mode 가 맡음 |
| 노드 분산 | 워커 2대 고정 | `minDomains: 2` + 가용 영역 분산 (E-3) |
| mysql, redis | - | 정리 예외 표시 (E-4) |

## 4. 진행

### 4.1 클러스터 만들기

```bash
aws eks create-cluster --name vet2-eks --kubernetes-version 1.36 \
  --role-arn arn:aws:iam::<계정>:role/vet2-eks-cluster \
  --resources-vpc-config "subnetIds=<2a>,<2c>,endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs=<내 IP>/32" \
  --compute-config "enabled=true,nodeRoleArn=arn:aws:iam::<계정>:role/vet2-eks-node,nodePools=general-purpose,system" \
  --kubernetes-network-config '{"elasticLoadBalancing":{"enabled":true}}' \
  --storage-config '{"blockStorage":{"enabled":true}}' \
  --access-config authenticationMode=API,bootstrapClusterCreatorAdminPermissions=true \
  --no-bootstrap-self-managed-addons
aws eks wait cluster-active --name vet2-eks        # 514초
```

ALB 가 서브넷을 찾을 수 있게 두 서브넷에 `kubernetes.io/role/elb=1` 태그를 붙였다.

준비된 직후의 클러스터는 거의 비어 있다.

```
$ kubectl get nodes
No resources found                 ← 노드 0대. Pod 를 올려야 생긴다
$ kubectl get pods -A
No resources found
$ kubectl get sc,ingressclass
storageclass.storage.k8s.io/gp2   kubernetes.io/aws-ebs   Delete   WaitForFirstConsumer
```

### 4.2 kubeadm 배포 파일을 그대로 올렸을 때

```bash
v2/k8s/secrets.sh -n vet2
v2/k8s/apply.sh kubeadm
```

160초 뒤:

```
NAME                  STATUS   VERSION               INTERNAL-IP   OS-IMAGE
i-0a26cadaa4be3f221   Ready    v1.36.5-eks-577a51e   10.20.1.43    Bottlerocket (EKS Auto)
i-0e27eab4ebd02edf6   Ready    v1.36.5-eks-577a51e   10.20.1.200   Bottlerocket (EKS Auto)

auth-...       1/1  Running     10.20.1.210
...
mysql-0        0/1  Pending
data-mysql-0   Pending   vet2-local
service/web    NodePort  80:30080/TCP

mysql-0       FailedScheduling     no nodes available to schedule pods
data-mysql-0  ProvisioningFailed   storageclass.storage.k8s.io "vet2-local" not found
```

| 본 것 | 뜻 |
|---|---|
| 노드 2대가 2분 안에 생겼다 | Pod 를 올리자 Auto Mode 가 요청량에 맞는 노드를 만들었다 (`FailedScheduling ... no nodes available` 은 그 전의 기록이다) |
| 이미지를 모두 받았다. 기본 ServiceAccount 에 `imagePullSecrets` 없음 | **③ K-5 가 여기서는 없다.** 노드가 IAM 역할로 ECR 에 로그인한다 |
| Pod 의 IP 가 `10.20.1.x` (VPC 의 주소) | ③의 Flannel(10.244.x.x)과 달리 Pod 가 VPC 의 실제 IP 를 받는다. ALB 가 Pod 로 바로 보낼 수 있는 이유다 |
| MySQL 의 볼륨 요청이 `vet2-local` 을 찾는다 | kubeadm 용 설정이다 (E-2) |
| web 은 NodePort | 노드의 보안 그룹은 Auto Mode 가 관리하고 30080 은 열려 있지 않다 (E-1) |

## 5. 최종 구성

kubeadm overlay 와 다른 것만 적는다 ([overlays/eks](../k8s/overlays/eks/kustomization.yaml)).

| 설정 | 이유 |
|---|---|
| Ingress `web` (IngressClass `vet2-alb`), `target-type: ip`, `healthcheck-path: /health`, `inbound-cidrs: <내 IP>/32` | E-1 |
| MySQL 볼륨 `storageClassName: vet2-ebs` | E-2 |
| web·서비스 3개: 노드 분산에 `minDomains: 2`, 가용 영역 분산(`topology.kubernetes.io/zone`, `minDomains: 2`) | E-3 |
| mysql, redis: `karpenter.sh/do-not-disrupt: "true"` | E-4 |

## 6. 기준별 측정 (최종 구성)

### 6.1 시나리오 테스트

```bash
node v2/tests/scenario.mjs --base-url http://<ALB 주소> --db-exec "kubectl -n vet2 exec mysql-0 --"
```

```
결과: 통과 65 / 실패 0
```

ALB 의 보안 그룹에는 80 포트가 이 PC 의 IP 하나에만 열려 있다.

### 6.2 배포, 업데이트, 자동 복구, 데이터

같은 측정을 세 환경에서 한 결과다 (모두 최종 구성).

| 작업 | 이 PC | EC2 kubeadm | EKS (ALB) |
|---|---|---|---|
| 다시 배포 | 0 / 7,619 | 1 / 6,905 | **0 / 7,691** |
| 업데이트·롤백 | 0 / 5,183 | 1 / 5,522 | **0 / 5,330** |
| web Pod 삭제 | 0 / 1,188 | 0 / 1,069 | **0 / 1,265** (8초에 복구) |
| reservation Pod 삭제 | 0 / 1,388 | 0 / 1,711 | **0 / 1,767** (15초) |
| MySQL Pod 삭제 | 30건, 7초 | 28건, 7초 | 47건, 17초. 예약 200번 남음 |

EKS 에서 MySQL 이 다시 응답하기까지 더 걸린 것(17초)은 EBS 를 떼고 붙이는 시간이 더해졌기 때문으로 보인다. 나눠서 재지는 않았다.

③의 O-1(배포 직후 몇 초는 옛 버전이 답한다)은 여기서도 그대로였다. 업데이트 3초 뒤 1.0.0, 롤백 3초 뒤 1.0.1 이 답했다.

### 6.3 노드가 없어질 때

Auto Mode 의 노드는 멈출 수 없다.

```
$ aws ec2 stop-instances --instance-ids <EKS 노드> --force --dry-run
UnauthorizedOperation ... not authorized to perform: ec2:StopInstances
$ aws ec2 terminate-instances ... --dry-run   → UnauthorizedOperation
$ aws ec2 reboot-instances ... --dry-run      → UnauthorizedOperation
```

EKS 가 관리하는 인스턴스라 관리자 계정으로도 EC2 에서 손댈 수 없다. **그래서 ③처럼 노드가 갑자기 죽는 실험은 하지 못했다.** 대신 `kubectl delete node` 로 노드를 지웠다. Auto Mode 가 Pod 를 차례로 내보내고(PodDisruptionBudget 을 지키며) 노드를 없앤다. 갑작스런 장애가 아니라 **계획된 노드 교체**에 해당한다.

**1차: MySQL 이 있는 노드를 지움 (정리 예외 표시 전, 남은 노드도 같은 영역)**

```
MySQL 노드: i-0e27eab4ebd02edf6, EBS: vol-07ce852aac3e8f1b6
+0s   kubectl delete node i-0e27eab4ebd02edf6
+8s   ... mysql-0=Pending (다른 노드로)
      FailedAttachVolume  Volume is already exclusively attached to one node, waiting on detach
      SuccessfulAttachVolume  AttachVolume.Attach succeeded
      Pulled  ... vet2-db:1.0.0 in 14.424s        ← 새 노드에는 이미지가 없어 받았다
+37s  ... mysql-0=Running ready=true
[트래픽] 425.2초 동안 요청 26170건, 실패 74건 (마지막 46.2초)  ← 모두 DB 를 쓰는 요청
예약 186: "status":"REQUESTED"
EBS vol-07ce852aac3e8f1b6 가 붙은 곳: ap-northeast-2a  i-0a26cadaa4be3f221  in-use
```

**③ K-11 의 첫째 원인(볼륨이 노드에 묶임)은 EBS 로 풀렸다.** 볼륨이 떨어졌다가 다른 노드에 붙었고, 예약 데이터가 그대로 있었다. 둘째 원인(죽은 노드를 확인할 수 없어 StatefulSet 이 기다림)은 계획된 교체라 생기지 않았고, 갑작스런 장애는 재 보지 못했다.

이 실험 뒤에 E-3 이 드러났다.

**2차: 다른 노드가 다른 영역에 있을 때 (E-3, E-4 를 고친 뒤)**

MySQL 은 2a, 남은 노드는 2c 였다. EBS 는 2c 의 노드에 붙을 수 없다.

```
MySQL 노드: i-0a26cadaa4be3f221 (ap-northeast-2a), 다른 노드: i-0b23a27153e9cadca (ap-northeast-2c)
+0s   kubectl delete node i-0a26cadaa4be3f221
+22s  노드: ba075/a(Ready) 3f221/a(Ready) cadca/c(Ready)    ← 2a 에 새 노드
+49s  auth=2/2 clinic=2/2 redis=1/1 reservation=2/2 web=2/2 | mysql-0=Running/..3f221
[트래픽] 490.1초 동안 요청 32254건, 실패 0건
```

앱 Pod 는 2a 의 새 노드로 옮겨 갔고 실패는 0건이었다. 하지만 MySQL 과 Redis 는 옮겨 가지 않았다. 이것이 E-4 다.

**3차: MySQL 과 Redis 를 직접 옮김**

```
mysql-0 다시 준비까지 35초
[트래픽] 60.0초 동안 요청 1800건, 실패 65건 (마지막 39.1초)
    /api/auth/login → 503: 33건     ← DB 가 없는 동안 다시 로그인하려다 실패
mysql → i-01c86d4a7672ba075 (ap-northeast-2a)    ← EBS 가 있는 영역의 노드로
redis → i-0b23a27153e9cadca (ap-northeast-2c)
```

스케줄러가 볼륨의 영역을 보고 2a 노드를 골랐다. Redis 가 새로 떠서 로그인이 모두 풀렸다(401).

## 7. 문제와 해결

### E-1. 웹에 밖에서 접속할 길이 없다

**증상.** kubeadm overlay 는 web 을 NodePort 30080 으로 연다. EKS 노드의 보안 그룹은 Auto Mode 가 만들고 관리하며, 30080 은 열려 있지 않다. 노드의 IP 도 Auto Mode 가 노드를 바꿀 때마다 바뀐다.

**검토한 방법.**

| 방법 | 판단 |
|---|---|
| 노드 보안 그룹에 30080 을 연다 | Auto Mode 가 관리하는 그룹을 손대야 하고, 노드 IP 가 바뀐다 |
| Service 를 LoadBalancer 로 (NLB) | 된다. 하지만 TCP 수준이라 `/health` 로 Pod 상태를 보는 HTTP 확인을 쓰려면 설정이 더 필요하다 |
| Ingress → ALB | HTTP 로 Pod 의 `/health` 를 본다. 접속을 허락할 IP 를 Ingress 에 적을 수 있다 |

**고른 방법.** Ingress → ALB. Auto Mode 에는 ALB 를 만드는 기능이 들어 있지만, 어떤 Ingress 를 맡을지 알려 주는 IngressClass 는 직접 만들어야 한다 ([alb.yaml](../k8s/cluster/eks/alb.yaml)). 기본은 VPC 안에서만 보이는(internal) ALB 라서 `scheme: internet-facing` 을 적었다.

**확인.** Ingress 를 만들고 약 100초 뒤 ALB 의 `/health` 가 200 이 됐다. ALB 는 두 영역(2a, 2c)에 걸쳐 있고, 보안 그룹은 80 포트를 이 PC 의 IP 에만 연다.

### E-2. MySQL 의 볼륨이 만들어지지 않는다

**증상.** kubeadm overlay 의 `vet2-local` 은 없다. 그렇다면 클러스터에 처음부터 있는 `gp2` 는 될까 해서 시험했다.

```
$ kubectl get sc gp2
gp2   provisioner=kubernetes.io/aws-ebs
$ (gp2 로 1Gi 볼륨을 요청하는 Pod 를 띄움, 60초 뒤)
ExternalProvisioning  Waiting for a volume to be created either by the external provisioner 'ebs.csi.aws.com' ...
$ kubectl get csidrivers
ebs.csi.eks.amazonaws.com
efs.csi.aws.com
spiffe.csi.eks.amazonaws.com
```

**원인.** `gp2` 는 쿠버네티스에 내장되어 있던 옛 방식(`kubernetes.io/aws-ebs`)이다. 지금의 쿠버네티스는 이것을 `ebs.csi.aws.com` 드라이버로 넘긴다. 그런데 Auto Mode 에 들어 있는 EBS 드라이버의 이름은 `ebs.csi.eks.amazonaws.com` 이다. 맡을 드라이버가 없어서 볼륨이 영영 만들어지지 않는다.

**고른 방법.** Auto Mode 의 드라이버를 쓰는 StorageClass 를 만들었다 ([storage.yaml](../k8s/cluster/eks/storage.yaml)). gp3, 암호화, `WaitForFirstConsumer`(Pod 가 놓일 영역이 정해진 뒤에 그 영역에 볼륨을 만든다 — EBS 는 한 영역에서만 붙는다), `reclaimPolicy: Delete`.

StatefulSet 의 볼륨 설정은 바꿀 수 없으므로(③ K-7) StatefulSet 과 PVC 를 지우고 다시 만들었다.

**확인.**

```
data-mysql-0   Bound   pvc-5a621c26-...   2Gi   RWO   vet2-ebs
/dev/nvme2n1    2.0G  210M  1.7G  11% /var/lib/mysql
[vet] 초기화 끝
```

적용부터 MySQL 준비까지 42초.

### E-3. 노드가 하나 빠지자 모든 Pod 가 남은 노드 1대에 몰렸다

**증상.** 6.3 의 1차 실험 뒤:

```
i-0a26cadaa4be3f221  Ready  c5a.large  ap-northeast-2a      ← 노드는 이것 하나
web:         i-0a26cadaa4be3f221 i-0a26cadaa4be3f221
auth:        i-0a26cadaa4be3f221 i-0a26cadaa4be3f221
clinic:      i-0a26cadaa4be3f221 i-0a26cadaa4be3f221
reservation: i-0a26cadaa4be3f221 i-0a26cadaa4be3f221
redis:       i-0a26cadaa4be3f221
mysql:       i-0a26cadaa4be3f221
```

Auto Mode 는 지운 노드를 다시 만들지 않았다. 처음 만든 노드 2대도 둘 다 2a 였다.

**원인.** 두 가지다.

1. **Auto Mode 는 노드를 적게 쓰려 한다.** NodePool 의 설정:

   ```
   {"budgets":[{"nodes":"10%"}],"consolidateAfter":"30s","consolidationPolicy":"WhenEmptyOrUnderutilized"}
   ```

   Pod 가 다 들어가면 노드를 늘리지 않고, 덜 찬 노드는 30초 뒤 정리해 Pod 를 몰아넣는다. 11개의 요청량(CPU 825m, 메모리 2144Mi)이 `c5a.large` 1대에 들어갔다.

2. **분산 규칙은 있는 노드끼리만 비교한다.** `maxSkew: 1` 은 "노드 사이의 개수 차이를 1 이하로"라는 뜻인데, 노드가 1대면 차이가 0 이라 둘 다 같은 노드에 놓아도 규칙이 지켜진 것이 된다. 노드가 고정인 kubeadm 에서는 드러나지 않았다.

**고른 방법.** EKS overlay 에만 더했다 (이 PC 의 클러스터는 노드가 1대라 base 에 넣으면 둘째 복제본이 뜨지 못한다).

- 노드 분산에 `minDomains: 2`: 노드가 2대보다 적으면 "없는 노드에 0개가 있다"고 보고 계산한다. 그러면 둘째 복제본은 같은 노드에 놓일 수 없어 `Pending` 이 되고, Auto Mode 가 노드를 새로 만든다.
- 가용 영역 분산(`topology.kubernetes.io/zone`, `minDomains: 2`): 처음 노드 2대가 같은 영역이었으므로.

**확인.**

```
i-0a26cadaa4be3f221  Ready  23m  c5a.large  ap-northeast-2a
i-0b23a27153e9cadca  Ready  34s  c5a.large  ap-northeast-2c     ← 적용 뒤 새로 생김
web:         2c  2a
auth:        2c  2a
clinic:      2c  2a
reservation: 2c  2a
```

적용부터 전부 준비까지 67초.

### E-4. DB 를 지키려고 붙인 표시 때문에 노드를 지워도 24시간 동안 지워지지 않는다 (맞바꿈)

E-3 을 고치면서, Auto Mode 가 노드를 정리할 때 복제본이 하나뿐인 mysql 과 redis 를 옮기지 않게 `karpenter.sh/do-not-disrupt: "true"` 를 붙였다. 옮기는 동안 DB 와 로그인이 끊기기 때문이다. **정리 때문에 mysql 이 옮겨지는 것을 실제로 보지는 못했다.** 예방으로 붙인 것이다.

**증상.** 6.3 의 2차 실험에서 MySQL 이 있는 노드를 지웠는데, 노드가 남아 있었다.

```
deletionTimestamp=2026-11-23T07:56:36Z
finalizers=["karpenter.sh/termination"]
taints=[{"effect":"NoSchedule","key":"karpenter.sh/disrupted"}]
vet2 mysql-0 Running
vet2 redis-69bc48d667-tftn9 Running
FailedDraining                 Failed to drain node, 5 pods are waiting to be evicted
TerminationGracePeriodExpiring All pods will be deleted by 2026-11-24T07:46:53Z
$ kubectl get nodepool general-purpose -o jsonpath='{.spec.template.spec.terminationGracePeriod}'
24h0m0s
```

**원인.** 이 표시는 Auto Mode 의 정리만이 아니라 노드를 지울 때 Pod 를 내보내는 것도 막는다. Auto Mode 는 NodePool 의 `terminationGracePeriod`(24시간)가 지나야 강제로 지운다.

**판단.** 둘 중 하나를 고르는 문제다.

| | 표시 없음 | 표시 있음 |
|---|---|---|
| Auto Mode 가 노드를 정리할 때 | DB·Redis 가 예고 없이 옮겨질 수 있다 (재 보지 않음) | 옮겨지지 않는다 |
| 노드를 지우거나 교체할 때 | 저절로 옮겨 간다 (1차: 37초) | **사람이 옮겨야 한다.** 안 하면 24시간 뒤 강제 |

DB 를 언제 끊을지 사람이 정하는 쪽을 골라 표시를 남겼다. 노드를 바꿀 때는 3차처럼 Pod 를 직접 지운다 (35초 끊김).

```bash
kubectl -n vet2 delete pod mysql-0
kubectl -n vet2 delete pod -l app=redis
```

## 8. 멈춤 (지우지 않음)

모든 측정을 마친 뒤 **자원은 지우지 않고 멈추기만 했다** (사용자 결정). 무엇을 어떻게 멈췄는지와 남는 요금은 ⑤ 최종 문서에 적는다.

## 9. 확인하지 못한 것

| 항목 | 이유 |
|---|---|
| EKS 노드가 갑자기 죽을 때 | Auto Mode 노드는 멈추거나 지울 권한이 없다. 계획된 교체만 쟀다 |
| 갑작스런 장애에서 StatefulSet 이 기다리는 문제(③ K-11 둘째 원인) | 위와 같은 이유 |
| Auto Mode 의 정리가 실제로 Pod 를 옮기는 것 | 일부러 일으키지 못했다. E-4 의 표시는 예방이다 |
| MySQL 의 EBS 가 있는 영역이 통째로 죽을 때 | EBS 는 다른 영역으로 옮길 수 없다. DB 는 그 영역이 돌아올 때까지 멈출 것이다 (재 보지 않음) |
| 실제 사용량 (CPU, 메모리) | 지표 서버를 설치하지 않았다 |
| HTTPS | 인증서(도메인)가 없어 HTTP 로만 열었다 |

## 10. 다시 실행하는 순서

```bash
# (4.1 의 명령으로 클러스터를 만든 뒤)
aws eks update-kubeconfig --name vet2-eks --kubeconfig v2/_run/kubeconfig-eks
export KUBECONFIG=v2/_run/kubeconfig-eks
kubectl apply -f v2/k8s/cluster/eks/
v2/k8s/secrets.sh -n vet2
v2/k8s/apply.sh eks
kubectl -n vet2 get ingress web          # ADDRESS 가 ALB 주소. 1 ~ 2분 뒤 응답한다
node v2/tests/scenario.mjs --base-url http://<ALB 주소> --db-exec "kubectl -n vet2 exec mysql-0 --"
v2/tests/k8s-ops.sh --base-url http://<ALB 주소> -n vet2 --new-clinic-image <ECR 주소>/vet2-clinic:1.0.1
```
