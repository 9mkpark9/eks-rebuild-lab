# 배포 파일 (Kustomize)

쿠버네티스에 올리는 파일은 전부 이 폴더에 있다. **같은 바탕(base)을 두 종류의 클러스터에 올리고, 다른 점만 overlay 에 적는다.**

```
gitops/
├─ cluster/                 클러스터에 한 번 준비하는 것 (네임스페이스에 속하지 않는 자원)
│  ├─ kubeadm/storage.yaml    StorageClass vet-local + PersistentVolume (노드의 디스크)
│  └─ eks/
│     ├─ storage.yaml         StorageClass vet-ebs (EBS)
│     └─ alb.yaml             IngressClass vet-alb (ALB)
└─ apps/vet/
   ├─ base/                 환경과 무관한 바탕
   │  ├─ config.yaml          ConfigMap vet-config (DB 주소, 연결 수, Redis 주소)
   │  ├─ web.yaml             웹 서버 (Deployment 2개 + Service)
   │  ├─ auth.yaml clinic.yaml reservation.yaml   서비스 3개 (각 Deployment 2개 + Service)
   │  ├─ redis.yaml           로그인 세션 저장소
   │  └─ pdb.yaml             PodDisruptionBudget 4개
   ├─ components/           골라 쓰는 조각
   │  ├─ db-in-cluster/       MySQL (StatefulSet + PVC + Service)
   │  ├─ db-external/         바깥 DB, 예: RDS (초기화 Job + DB 주소를 Secret 에서 받게 하는 패치)
   │  └─ autoscale/           reservation 자동 확장 (HPA). 지표 서버가 있을 때만
   ├─ overlays/
   │  ├─ kubeadm/             EC2 에 직접 만든 클러스터 (과제 ③)
   │  ├─ eks/                 Amazon EKS Auto Mode (과제 ④)
   │  └─ local/               내 PC 의 클러스터에서 미리 돌려 볼 때 (kubeadm 과 같고 노출만 다르다)
   └─ secrets.example.yaml  Secret 의 이름과 키만 보여 주는 예시. 값은 Git 에 없다
```

## kubeadm 과 EKS 에서 다른 것

두 overlay 의 차이가 곧 "③에서 ④로 가면서 바꾼 값"이다. 바탕(base)은 한 글자도 다르지 않다.

| 항목 | kubeadm (③) | EKS (④) | 바꾼 이유 |
|---|---|---|---|
| 밖으로 여는 법 | `Service` 를 NodePort 30080 으로 | `Ingress` → ALB. `Service` 는 ClusterIP 그대로 | kubeadm 에는 로드밸런서를 만들어 주는 장치가 없다. EKS 는 Ingress 를 보고 ALB 를 만들어 준다 |
| DB 의 볼륨 | 노드 한 대의 디스크 (`vet-local`, 볼륨을 직접 등록) | EBS (`vet-ebs`, 자동으로 만들어짐) | kubeadm 에는 볼륨을 만들어 주는 장치가 없다. EKS 는 StorageClass 만 만들어 두면 EBS 를 만들어 붙인다 |
| 이미지를 받는 곳 | `ghcr.io/9mkpark9/vet-*` | ECR (`<계정>.dkr.ecr.<리전>.amazonaws.com/vet-*`) | 과제가 ECR 로 옮기라고 한다. 노드가 별도 로그인 없이 받을 수 있다 |
| redis 이미지 | `redis:7-alpine` (Docker Hub) | `public.ecr.aws/docker/library/redis:7-alpine` | Docker Hub 의 익명 내려받기 제한을 피한다. 같은 이미지다 |
| web 의 종료 대기 | 5초 | 15초 | ALB 는 내려가는 Pod 를 대상에서 빼는 데 시간이 더 걸린다 |
| 적용 명령 | `kubectl apply -k` | `scripts/eks-apply.sh` | ECR 주소에 계정 번호가 들어 있어 Git 에 적지 않고 적용할 때 넣는다 |

같은 것: Deployment 와 Service 의 내용, 프로브, 자원 요청, 복제본 수(2개), 분산 규칙, PDB, ConfigMap, Secret 의 이름과 키, MySQL 의 StatefulSet.

## 올리는 순서

### kubeadm (③)

```bash
# 1) 볼륨: DB 를 둘 워커 노드 하나를 정해, 그 노드에서 폴더를 만들고 라벨을 붙인다
#    (그 노드에서)        sudo mkdir -p /var/lib/vet-mysql
kubectl label node <노드 이름> vet-db=true
kubectl apply -f gitops/cluster/kubeadm/

# 2) Secret (비밀번호는 무작위로 만들어지고 화면에 나오지 않는다)
scripts/new-k8s-secrets.sh -n vet

# 3) 앱
kubectl apply -k gitops/apps/vet/overlays/kubeadm
kubectl -n vet get pods -o wide

# 4) 확인: http://<노드의 공인 IP>:30080
scripts/smoke.sh --base-url http://<노드 IP>:30080 --isolation k8s -n vet
scripts/test-k8s-ops.sh --base-url http://<노드 IP>:30080 -n vet --compare
```

### EKS (④)

```bash
# 1) StorageClass 와 IngressClass
kubectl apply -f gitops/cluster/eks/

# 2) Secret
scripts/new-k8s-secrets.sh -n vet

# 3) 앱 (ECR 주소를 넣어 적용한다. 계정 번호는 화면에 가려서 나온다)
scripts/eks-apply.sh
kubectl -n vet get pods -o wide
kubectl -n vet get ingress web          # ADDRESS 에 ALB 주소가 나올 때까지 몇 분 걸린다

# 4) 확인
scripts/smoke.sh --base-url http://<ALB 주소> --isolation k8s -n vet
scripts/test-k8s-ops.sh --base-url http://<ALB 주소> -n vet --compare
```

### 내 PC 에서 미리 돌려 보기

`overlays/local` 은 kubeadm 구성에서 노출 방법만 LoadBalancer 로 바꾼 것이다. Docker Desktop 의 클러스터는 그것을 `http://localhost` 로 열어 준다. 이미지를 노드에 넣는 방법은 `docs-msa/로컬실행.md` 에 있다.

```bash
docker exec desktop-control-plane mkdir -p /var/lib/vet-mysql
kubectl label node desktop-control-plane vet-db=true
kubectl apply -f gitops/cluster/kubeadm/
scripts/new-k8s-secrets.sh -n vet
kubectl apply -k gitops/apps/vet/overlays/local
```

## 내리는 순서

```bash
# kubeadm
kubectl delete -k gitops/apps/vet/overlays/kubeadm

# EKS — ALB 와 EBS 볼륨도 함께 지워진다. 클러스터를 지우기 전에 반드시 먼저 한다
scripts/eks-apply.sh --delete
kubectl delete -f gitops/cluster/eks/
```

### kubeadm 에서 DB 를 처음 상태로 되돌리려면

kubeadm 의 볼륨은 PVC 를 지워도 노드에 데이터가 남는다(`Retain`). 그래서 앱을 지웠다가 그대로 다시 올리면 두 가지가 걸린다.

- 볼륨이 `Released` 상태로 남아 새 PVC 와 묶이지 않는다. `mysql-data` 가 `Pending`, `mysql-0` 이 `Pending` 에 머문다 (로컬 클러스터에서 확인했다).
- 네임스페이스와 함께 Secret 도 지워진다. 새로 만든 Secret 의 비밀번호는 남아 있는 데이터의 계정 비밀번호와 다르다.

**앱을 지웠으면 볼륨도 비우고 다시 등록한다.** 아래 순서로 한 뒤 Secret 과 앱을 다시 올리면 처음 상태로 뜬다.

```bash
# (DB 노드에서)  sudo rm -rf /var/lib/vet-mysql/mysql
kubectl delete pv vet-mysql
kubectl apply -f gitops/cluster/kubeadm/
```

EKS 에서는 PVC 를 지우면 EBS 볼륨도 지워지므로(`Delete`) 이 문제가 없다.

## DB 를 RDS 로 바꾸려면 (선택 과제)

`overlays/eks/kustomization.yaml` 에서 두 줄을 고친다.

1. `components` 의 `../../components/db-in-cluster` 를 `../../components/db-external` 로 바꾼다.
2. `patches` 의 `mysql-storage.yaml` 줄을 지운다 (MySQL Pod 가 없으므로 볼륨도 없다).

그리고 RDS 주소와 관리자 계정을 Secret 으로 넣는다 (`scripts/new-k8s-secrets.sh --help`). 초기화 Job 이 RDS 에 스키마, 시드, 서비스 계정을 만든다. RDS 에서는 실행하지 않았다.
