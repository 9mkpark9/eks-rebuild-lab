# ④ 실행 안내 — Amazon EKS (Auto Mode)

과제의 ④(EKS 전환)를 실행하는 순서다. ③에서 쓴 바탕(base)을 그대로 쓰고, EKS 에서 달라지는 것만 `overlays/eks` 에 있다.

> **이 문서의 명령은 EKS 에서 실행해 보지 않았다.** ALB, EBS, ECR 부분은 AWS 문서의 형식을 따랐고, 배포 파일이 렌더되는 것과 계정 번호가 가려지는 것만 확인했다. 바탕은 내 PC 의 클러스터에서 확인한 것과 같다.
> 클러스터를 만드는 방법은 **수업에서 배운 것을 우선한다.**

과제의 완성 기준과 이 문서의 절:

| 과제 | 완성 기준 | 절 |
|---|---|---|
| ECR · EKS 준비 | 이미지를 ECR 로 옮기고 클러스터를 생성했다. 직접 구축과 비교해 EKS 가 대신하는 일을 정리했다 | 1, 2, 3 |
| 배포와 노출 | ③의 구성을 배포하고 ALB 주소로 테스트 시나리오 통과. ③에서 바꾼 값과 이유 | 4, 5, 6 |
| 데이터 유지 | APP · DB Pod 를 교체해도 데이터 유지 (StorageClass 를 직접 생성) | 4, 5 |
| 비용과 정리 | 과금 자원과 삭제 순서, 발표 후 삭제하고 남은 자원이 없음을 확인 | 7 |

## 1. 준비

내 PC 의 WSL 에서 실행한다. 필요한 도구: `aws`(로그인돼 있을 것), `kubectl`, `eksctl`(0.195.0 이상, 수업에서 eksctl 을 쓴다면), `docker`.

```bash
aws sts get-caller-identity --query Arn --output text    # 로그인 확인. 문서에 올릴 때는 계정 번호를 가린다
aws configure get region                                  # ap-northeast-2
```

## 2. 이미지를 ECR 로 옮긴다

②에서 만든 이미지에 ECR 주소로 태그를 붙여 올린다. 저장소가 없으면 만든다.

```bash
scripts/push-images.sh --ecr --dry-run     # 무엇을 올릴지, linux/amd64 인지 본다
scripts/push-images.sh --ecr
scripts/push-images.sh --ecr --list        # 저장소마다 올라간 태그
```

ECR 을 쓰는 이유: EKS 의 노드는 자기 IAM 역할로 같은 계정의 ECR 에서 이미지를 받는다. 노드에 로그인 정보를 넣거나 `imagePullSecrets` 를 만들 필요가 없다.

## 3. 클러스터를 만든다 (수업의 방법으로)

참고로, eksctl 로는 명령 하나다(AWS 문서). 15~20분쯤 걸린다.

```bash
eksctl create cluster --name=vet --region=ap-northeast-2 --enable-auto-mode
aws eks update-kubeconfig --name vet --region ap-northeast-2
kubectl get nodes          # Auto Mode 는 Pod 가 생길 때 노드를 만든다. 처음에는 비어 있을 수 있다
kubectl get nodepools      # general-purpose, system
```

### 직접 만든 클러스터와 비교 — EKS 가 대신하는 일

| 일 | kubeadm (③) | EKS Auto Mode (④) |
|---|---|---|
| 컨트롤 플레인 (API 서버, etcd, 스케줄러) | EC2 한 대에 직접 설치. 그 한 대가 죽으면 `kubectl` 과 배포가 멈춘다 | AWS 가 여러 가용 영역에 두고 관리한다. 인스턴스가 보이지 않는다 |
| 노드 만들기 | EC2 를 만들고, 컨테이너 런타임과 kubelet 을 설치하고, `kubeadm join` | Pod 가 생기면 맞는 크기의 노드를 자동으로 만들고, 비면 없앤다 |
| 노드의 OS 와 패치 | 직접 | AWS 가 관리하는 이미지. 노드에 SSH 로 들어가지 않는다 |
| Pod 네트워크 (CNI) | Calico 를 직접 설치하고 보안 그룹에 포트를 연다 | 들어 있다. Pod 가 VPC 의 IP 를 받는다 |
| 클러스터 DNS, kube-proxy | kubeadm 이 설치한 것을 직접 관리 | 들어 있다 |
| 밖으로 여는 법 | NodePort. 로드밸런서가 없다 | Ingress 를 만들면 ALB 를 만들어 준다 (IngressClass 는 직접 만든다) |
| 볼륨 | 노드의 폴더를 직접 등록 | PVC 를 만들면 EBS 를 만들어 붙인다 (StorageClass 는 직접 만든다) |
| 보안 그룹 | 포트를 하나씩 직접 연다 | 클러스터와 노드의 것은 만들어 준다 |
| 버전 올리기 | `kubeadm upgrade` 를 노드마다 | 컨트롤 플레인은 명령 하나, 노드는 자동으로 교체 |
| 이미지 받기 | 공개 레지스트리, 또는 노드에 로그인 정보 | 노드의 IAM 역할로 ECR 에서 |
| 비용 | EC2 3대 | 컨트롤 플레인 요금 + 노드 + Auto Mode 관리 요금 + ALB + NAT + EBS |

**그래도 직접 해야 하는 것**: StorageClass 와 IngressClass 만들기, 배포 파일, Secret, 그리고 자원을 지우는 일.

## 4. 배포

```bash
# 1) 클러스터에 한 번: StorageClass(EBS)와 IngressClass(ALB)
kubectl apply -f gitops/cluster/eks/
kubectl get sc,ingressclass

# 2) Secret
scripts/new-k8s-secrets.sh -n vet

# 3) 무엇이 적용되는지 보고(계정 번호는 가려서 나온다), 적용한다
scripts/eks-apply.sh --render | less
scripts/eks-apply.sh

# 4) 다 뜰 때까지 본다. 노드가 새로 만들어지는 동안 Pod 는 Pending 이다 (1~2분)
kubectl -n vet get pods -o wide -w
kubectl get nodes -L topology.kubernetes.io/zone

# 5) ALB 주소. ADDRESS 가 채워지고도 응답하기까지 몇 분 더 걸린다
kubectl -n vet get ingress web
ALB=$(kubectl -n vet get ingress web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s -o /dev/null -w '%{http_code}\n' "http://$ALB/health"
```

`scripts/eks-apply.sh` 를 쓰는 이유: ECR 주소에 AWS 계정 번호가 들어 있어 Git 에 적지 않았다. 배포 파일에는 `ECR_REGISTRY` 라는 자리 표시가 있고, 스크립트가 적용하는 순간에 지금 로그인한 계정의 주소로 바꾼다.

## 5. 확인하고 증거를 남긴다

```bash
scripts/smoke.sh --base-url "http://$ALB" --isolation k8s -n vet           # 54개
scripts/test-k8s-ops.sh --base-url "http://$ALB" -n vet --compare          # 15개 + 비교
```

①부터 써 온 것과 같은 스크립트이고 주소만 ALB 로 바뀐다. 브라우저에서 `http://<ALB 주소>` 와 `/status` 도 연다.

| 완성 기준 | 명령 | 봐야 할 것 |
|---|---|---|
| 이미지를 ECR 로 옮겼다 | `scripts/push-images.sh --ecr --list`, `kubectl -n vet describe pod <auth Pod>` 의 Events | 태그 목록, `Pulled … dkr.ecr …/vet-auth:1.0.0` |
| 클러스터를 생성했다 | `kubectl get nodes -o wide -L topology.kubernetes.io/zone` | 노드와 가용 영역 |
| ALB 주소로 시나리오 통과 | `smoke.sh` 의 출력, `kubectl -n vet get ingress web` | `결과: 통과 54, 실패 0`, ALB 주소 |
| StorageClass 를 직접 생성 | `kubectl get sc vet-ebs -o yaml`, `kubectl -n vet get pvc,pv` | `ebs.csi.eks.amazonaws.com`, PVC `Bound` |
| APP · DB Pod 교체 후 데이터 유지 | `test-k8s-ops.sh` 의 3번과 4번 | "표식 예약이 남아 있다" |
| 가용 영역 분산 (선택) | `kubectl -n vet get pods -o wide` 와 노드의 영역 | 같은 앱의 두 Pod 가 다른 노드, 다른 영역 |
| 무중단 배포 (선택) | `test-k8s-ops.sh` 의 1, 2번과 `--compare` | 실패한 요청 수. **0이 아니면 그대로 적고** 아래 "막힐 때"의 ALB 항목을 본다 |

## 6. ③에서 바꾼 값과 그 이유

바탕(base)은 한 글자도 다르지 않다. 다른 것은 `overlays/kubeadm` 과 `overlays/eks` 두 폴더의 차이가 전부다.

```bash
diff -r gitops/apps/vet/overlays/kubeadm gitops/apps/vet/overlays/eks     # 차이를 그대로 볼 수 있다
```

| 항목 | kubeadm (③) | EKS (④) | 바꾼 이유 |
|---|---|---|---|
| 밖으로 여는 법 | NodePort 30080 | Ingress → ALB. Service 는 ClusterIP | EKS 는 Ingress 를 보고 ALB 를 만들어 준다. 주소가 노드에 묶이지 않고 포트가 80 이다 |
| DB 의 볼륨 | 노드 한 대의 디스크 (`vet-local`, 볼륨을 직접 등록) | EBS (`vet-ebs`, 자동 생성) | 노드가 바뀌어도 같은 가용 영역 안에서는 볼륨이 따라간다. 직접 등록할 필요가 없다 |
| 이미지를 받는 곳 | 공개 레지스트리 | ECR | 과제의 요구. 노드가 IAM 역할로 받는다 |
| redis 이미지 | Docker Hub | ECR Public 의 같은 이미지 | Docker Hub 의 익명 내려받기 제한을 피한다 |
| web 의 종료 대기 | 5초 | 15초 | ALB 가 내려가는 Pod 를 대상에서 빼는 데 kube-proxy 보다 오래 걸린다 |
| mysql, redis 의 표시 | 없음 | `karpenter.sh/do-not-disrupt` | Auto Mode 는 덜 찬 노드를 스스로 정리한다. Pod 가 하나뿐인 둘은 옮기지 않게 한다 |
| 클러스터 준비 | StorageClass + PersistentVolume, 노드 라벨, 폴더 만들기 | StorageClass + IngressClass | EKS 는 볼륨을 만들어 주므로 직접 등록하는 부분이 없다 |
| 적용 명령 | `kubectl apply -k` | `scripts/eks-apply.sh` | ECR 주소의 계정 번호를 Git 에 넣지 않으려고 |
| 보안 그룹 | 포트를 직접 열었다 | 손대지 않았다 | 클러스터가 만들어 준다 |

## 7. 비용과 정리

### 요금이 나오는 자원

| 자원 | 과금 단위 | 누가 만드나 | 지우는 법 |
|---|---|---|---|
| EKS 컨트롤 플레인 | 클러스터 x 시간 | 클러스터 생성 | 클러스터 삭제 |
| 노드 (EC2) | 인스턴스 x 시간 + Auto Mode 관리 요금 | Auto Mode 가 Pod 를 보고 | Pod 를 지우면 줄어들고, 클러스터 삭제로 모두 없어진다 |
| ALB | 시간 + 처리량 | Ingress | **Ingress 를 지운다** (`eks-apply.sh --delete`) |
| EBS 볼륨 | GB x 월 | PVC | **PVC 를 지운다** (`eks-apply.sh --delete`). 노드의 디스크는 노드와 함께 없어진다 |
| NAT 게이트웨이, 탄력적 IP | 시간 + 처리량 | 클러스터용 VPC 를 만들 때 (eksctl 등) | VPC 와 함께 (eksctl 이면 클러스터 삭제에 포함) |
| ECR | 저장한 GB x 월 | `push-images.sh --ecr` | `push-images.sh --ecr --delete` |
| RDS (선택 과제를 했다면) | 인스턴스 x 시간 + 저장 | 직접 | 콘솔이나 CLI 로 삭제 |
| ③의 EC2 3대 | 인스턴스 x 시간, 정지해도 디스크 요금 | 직접 | 종료(terminate) |

금액은 리전과 시점에 따라 달라지므로 AWS 요금표에서 확인해 적는다. 쓰지 않는 밤에는 클러스터를 지우는 것이 가장 확실하다. 배포 파일과 스크립트가 Git 에 있으므로 다시 만드는 데 드는 것은 4번의 명령뿐이다.

### 지우는 순서

순서가 중요하다. **클러스터를 먼저 지우면 ALB 와 EBS 가 주인 없이 남아 요금이 계속 나오고, VPC 도 지워지지 않는다.**

```bash
# 1) 앱을 지운다. Ingress 가 지워지면서 ALB 가, PVC 가 지워지면서 EBS 볼륨이 함께 지워진다
scripts/eks-apply.sh --delete
kubectl -n vet get ingress,pvc           # 아무것도 없을 때까지 기다린다
kubectl get pv                           # vet 의 볼륨이 없어야 한다

# 2) 클러스터 준비물
kubectl delete -f gitops/cluster/eks/

# 3) 클러스터 (수업에서 만든 방법으로 지운다. eksctl 로 만들었으면)
eksctl delete cluster --name=vet --region=ap-northeast-2

# 4) ECR 저장소
scripts/push-images.sh --ecr --delete

# 5) ③의 EC2 3대를 종료한다 (콘솔 또는 aws ec2 terminate-instances)

# 6) 남은 것이 없는지 확인한다
scripts/aws-leftovers.sh
```

`scripts/aws-leftovers.sh` 는 읽기만 한다. EKS 클러스터, EC2, 로드밸런서, NAT 게이트웨이, 탄력적 IP, EBS 볼륨과 스냅샷, ECR, RDS 를 보고 남은 것을 출력한다. 전부 지웠으면 마지막 줄이 `결과: 남은 자원이 없다.` 이고, 이 출력이 "남은 자원이 없음을 확인했다"의 증거다. 계정 번호는 가려서 나온다.

## 선택 과제

| 과제 | 하는 법 | 남길 것 |
|---|---|---|
| RDS 로 DB 전환 | 사설 서브넷에 RDS(MySQL 8.4)를 만들고, 보안 그룹에서 클러스터의 노드가 3306 으로 들어오게 한다. `scripts/new-k8s-secrets.sh -n vet --external-db-host <주소> --external-db-admin-user <계정>` 으로 Secret 을 넣고, `overlays/eks/kustomization.yaml` 에서 DB 조각을 `db-external` 로 바꾼다(`gitops/README.md`). 초기화 Job 이 스키마와 계정을 만든다 | RDS 의 서브넷과 보안 그룹 화면, `kubectl -n vet logs job/db-provision`, `smoke.sh --no-db-check`, Pod 교체 뒤 `--verify` |
| 자동 확장 | 지표 서버(metrics-server)를 애드온으로 설치하고 `overlays/eks/kustomization.yaml` 의 `autoscale` 줄을 살린다 | `kubectl -n vet get hpa reservation -w` 가 부하에서 2 → 3 → 4 |
| 가용 영역 분산 | 바탕에 들어 있다 | 5번 표의 "가용 영역 분산" |
| Kustomize | `gitops/` 전체 | 폴더 구조, 6번의 표, `kubectl apply -k` 와 `eks-apply.sh` 의 출력 |
| 무중단 롤링 업데이트 | 바탕에 들어 있다 | `test-k8s-ops.sh --compare` 의 실패 수 비교 |
| 리소스 요청 · 분산 배치 · PDB | 바탕에 들어 있다 | `kubectl -n vet get pdb`, Pod 배치 |

RDS 에서의 초기화, 자동 확장, RDS 장애 조치는 실행해 보지 않았다.

## 막힐 때

| 증상 | 볼 것 | 원인과 조치 |
|---|---|---|
| `mysql-data` 가 `Pending` | `kubectl -n vet describe pvc mysql-data`, `kubectl get sc` | StorageClass `vet-ebs` 가 없다. 4번의 1)을 했는지 본다. Pod 가 놓일 노드가 정해지기 전에는 `Pending` 이 정상이다(`WaitForFirstConsumer`) |
| Ingress 의 `ADDRESS` 가 비어 있다 | `kubectl -n vet describe ingress web` 의 Events | IngressClass `vet-alb` 가 없다. 공개 서브넷에 `kubernetes.io/role/elb=1` 태그가 없다(eksctl 로 만든 VPC 에는 있다) |
| ALB 주소는 나왔는데 접속이 안 된다 | `curl -v`, 콘솔의 대상 그룹 | 만들어진 직후에는 DNS 와 대상 등록에 몇 분 걸린다. 대상이 `unhealthy` 면 `/health` 경로와 Pod 의 `Ready` 를 본다 |
| `ImagePullBackOff` | `kubectl -n vet describe pod <이름>` | ECR 에 그 태그가 없다(`push-images.sh --ecr --list`). 이미지가 `linux/amd64` 가 아니다. `kubectl apply -k` 로 직접 적용해 주소가 `ECR_REGISTRY/…` 그대로다 → `scripts/eks-apply.sh` 로 적용한다 |
| Pod 가 한동안 `Pending` | `kubectl get nodes -w`, `kubectl get nodeclaims` | Auto Mode 가 노드를 만드는 중이다. 1~2분 기다린다 |
| 배포 중 요청이 몇 건 실패한다 | `test-k8s-ops.sh` 의 FAIL 줄 | web 이 내려갈 때 ALB 가 아직 그 Pod 로 보낸 것이다. `overlays/eks/web-prestop.yaml` 의 대기 시간(15초)을 늘린다. 결과는 숨기지 말고 고치기 전후를 함께 적는다 |
| `mysql-0` 이 다른 영역의 노드로 가지 못한다 | `kubectl -n vet describe pod mysql-0` | EBS 볼륨은 만든 가용 영역에만 붙는다. 같은 영역에 노드가 생기기를 기다린다 |
| 클러스터를 지웠는데 요금이 나온다 | `scripts/aws-leftovers.sh` | 로드밸런서, NAT 게이트웨이, 탄력적 IP, EBS 볼륨이 남았다. 7번의 순서대로 하지 않았을 때 생긴다 |
