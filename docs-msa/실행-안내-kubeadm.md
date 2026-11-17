# ③ 실행 안내 — EC2 에 직접 만든 클러스터 (kubeadm)

과제의 ③(Kubernetes 전환)을 EC2 3대에서 실행하는 순서다. 배점이 35점으로 가장 크다.

> **이 문서의 명령은 EC2 에서 실행해 보지 않았다.** 배포 파일과 스크립트는 내 PC 의 클러스터(노드 1개)에서 같은 구성(`overlays/local`)으로 확인했고, 그 결과는 [테스트-시나리오.md](테스트-시나리오.md) 에 있다. EC2 에서 처음 드러날 수 있는 것은 맨 아래 "막힐 때"에 모았다.
> 클러스터를 만드는 방법은 **수업에서 배운 것을 우선한다.** 이 문서의 "클러스터 구축"은 확인할 것 위주로 적었다.

과제의 완성 기준과 이 문서의 절:

| 과제 | 완성 기준 | 절 |
|---|---|---|
| 클러스터 구축 | EC2 3대에 kubeadm 으로 구축, 노드가 모두 `Ready`, 필요한 포트만 보안 그룹에 | 1, 2, 3 |
| 배포와 운영 | 여러 Pod 로 배포, Probe, 롤링 업데이트 · 롤백, Pod 삭제 후 자동 복구 | 5, 6 |
| 노출 | 클러스터 밖에서 접속해 테스트 시나리오 통과, DB 는 클러스터 안에서만 | 6 |
| 데이터와 설정 | 볼륨에 저장해 DB Pod 교체 후 데이터 유지, ConfigMap 과 Secret 으로 분리 | 6 |

## 1. EC2 준비

| 항목 | 값 | 이유 |
|---|---|---|
| 대수 | 3대: 컨트롤 플레인 1 + 워커 2 | 과제의 조건. 컨트롤 플레인에는 앱 Pod 가 놓이지 않는다(기본 taint) |
| 크기 | 세 대 모두 t3.medium (2 vCPU, 4GiB) 이상 | 아래 계산 |
| 디스크 | **20GB 이상** (gp3) | 기본 8GB 로는 모자란다. 워커 한 대가 받는 이미지가 약 2.5GB 이고(`vet-db` 1.27GB, 서비스 357MB x 3), 풀어 놓으면 그 두 배쯤 쓴다 |
| 네트워크 | 같은 VPC, 같은 서브넷, 공인 IP | 노드끼리 사설 IP 로 통신한다 |
| OS | 수업에서 쓰는 Ubuntu | |

수업에서 만든 클러스터가 t3.medium 3대에 디스크 30GB 라면 이 표를 그대로 만족한다.

**크기 계산.** 앱 Pod 가 요청하는 자원의 합이다(`resources.requests`).

| | 개수 | CPU 요청 | 메모리 요청 | 메모리 한도 |
|---|---|---|---|---|
| auth, clinic, reservation | 각 2개 = 6 | 100m x 6 = 600m | 256Mi x 6 = 1536Mi | 512Mi x 6 |
| web | 2 | 50m x 2 = 100m | 32Mi x 2 = 64Mi | 128Mi x 2 |
| mysql | 1 | 100m | 256Mi | 768Mi |
| redis | 1 | 25m | 32Mi | 128Mi |
| **합** | 10 | **825m** | **1888Mi** | 4224Mi |

워커 2대(t3.medium)의 합은 4 vCPU, 8GiB 다. 요청 기준으로는 4분의 1쯤 쓴다. 한 대가 죽어 나머지 한 대에 몰려도 요청(1.9GiB)은 4GiB 안에 든다. t3.small(2GiB) 워커는 요청은 들어가지만 실제 사용량(서비스 하나에 약 200MiB)과 시스템 Pod 를 더하면 여유가 거의 없어 권하지 않는다. 컨트롤 플레인은 kubeadm 의 최소 조건이 2 CPU, 2GiB 다.

## 2. 보안 그룹 — 필요한 포트만

노드 3대에 같은 보안 그룹 하나를 붙이는 것을 기준으로 적었다. "출처: 같은 보안 그룹"은 노드끼리만 허용한다는 뜻이다.

| 포트 | 프로토콜 | 출처 | 쓰는 곳 |
|---|---|---|---|
| 22 | TCP | 내 IP | SSH |
| 30080 | TCP | 내 IP (발표 때는 보여 줄 대역) | web 의 NodePort. 밖에서 들어오는 유일한 길 |
| 6443 | TCP | 같은 보안 그룹 | API 서버. 워커의 kubelet 과 Pod 가 쓴다 |
| 10250 | TCP | 같은 보안 그룹 | kubelet. `kubectl logs`, `exec`, 프로브 |
| 2379-2380 | TCP | 같은 보안 그룹 | etcd. 컨트롤 플레인이 1대라 자기 자신만 쓴다 |
| 10257, 10259 | TCP | 같은 보안 그룹 | 컨트롤러 매니저, 스케줄러. 자기 자신만 쓴다 |
| CNI 가 쓰는 것 | 아래 | 같은 보안 그룹 | 다른 노드의 Pod 와 통신 |

CNI 가 쓰는 포트는 수업에서 설치한 방식에 따라 하나를 연다.

| Calico 의 방식 | 열 것 |
|---|---|
| IP-in-IP | IP 프로토콜 4 (보안 그룹 규칙의 유형에서 "사용자 지정 프로토콜", 번호 4) |
| VXLAN | UDP 4789 |
| BGP 를 함께 쓰면 | TCP 179 |

열지 않는 것: 3306(MySQL), 6379(Redis), 8080(서비스), NodePort 범위 전체(30000-32767). DB 와 서비스는 클러스터 안에서만 쓰므로 밖으로 열 이유가 없다. `kubectl` 은 컨트롤 플레인에 SSH 로 들어가서 쓰면 6443 을 밖에 열지 않아도 된다.

출처 표는 쿠버네티스 문서의 "Ports and Protocols"를 따랐다.

## 3. 클러스터 구축 (수업의 방법으로)

끝났을 때 확인할 것:

```bash
kubectl get nodes -o wide          # 3대가 모두 Ready, INTERNAL-IP 가 사설 IP
kubectl get pods -n kube-system    # CNI, CoreDNS, kube-proxy 가 Running
```

다른 노드의 Pod 끼리 통신이 되는지도 본다. 여기서 막히면 5번의 앱이 떠도 web 이 서비스에 닿지 못한다.

```bash
kubectl run t1 --image=busybox:1.36 --restart=Never --overrides='{"spec":{"nodeName":"<워커1 이름>"}}' -- sleep 600
kubectl run t2 --image=busybox:1.36 --restart=Never --overrides='{"spec":{"nodeName":"<워커2 이름>"}}' -- sleep 600
kubectl get pods -o wide                                   # t2 의 IP 를 본다
kubectl exec t1 -- ping -c 3 <t2 의 IP>                    # 응답이 와야 한다
kubectl delete pod t1 t2
```

## 4. 이미지

②에서 올린 레지스트리에서 노드가 직접 받는다. 저장소가 공개면 노드에서 로그인할 필요가 없다. 주소는 `gitops/apps/vet/overlays/kubeadm/kustomization.yaml` 의 `images` 한 곳에 있다(지금 `ghcr.io/9mkpark9`). 다른 레지스트리에 올렸으면 그 값을 고친다.

## 5. 배포

컨트롤 플레인에 SSH 로 들어가 저장소를 받는다.

```bash
git clone https://github.com/9mkpark9/eks-rebuild-lab.git && cd eks-rebuild-lab
```

```bash
# 1) 볼륨 준비. DB 를 둘 워커 하나를 정한다.
#    (그 워커에 SSH 로 들어가서)   sudo mkdir -p /var/lib/vet-mysql
kubectl label node <그 워커 이름> vet-db=true
kubectl apply -f gitops/cluster/kubeadm/
kubectl get sc,pv                                   # vet-local, vet-mysql (Available)

# 2) Secret. 비밀번호는 무작위로 만들어지고 화면에 나오지 않는다
scripts/new-k8s-secrets.sh -n vet

# 3) 무엇이 적용되는지 보고, 적용한다
kubectl kustomize gitops/apps/vet/overlays/kubeadm | less
kubectl apply -k gitops/apps/vet/overlays/kubeadm

# 4) 다 뜰 때까지 본다. 처음에는 이미지를 받느라 몇 분 걸린다
kubectl -n vet get pods -o wide -w
```

기대하는 모습: Pod 10개가 `Running`, `1/1`. auth, clinic, reservation, web 은 2개씩이고 **두 워커에 하나씩** 놓인다. `mysql-0` 은 라벨을 붙인 워커에 놓인다.

## 6. 확인하고 증거를 남긴다

### 클러스터 밖에서 — 테스트 시나리오

내 PC 의 WSL 에서, 노드의 공인 IP 로 접속한다. ① ②에서 쓴 것과 같은 스크립트다.

```bash
scripts/smoke.sh --base-url http://<노드의 공인 IP>:30080 --isolation none
```

`--isolation none` 은 `kubectl` 이 필요한 부분(서비스를 멈춰 보는 5번, DB 경계)을 건너뛴다. 등록 · 조회 · 수정이 들어 있는 22개 항목이 돈다. 어느 노드의 IP 로 접속해도 된다. 브라우저에서 `http://<노드의 공인 IP>:30080` 과 `/status` 도 열어 본다.

### 클러스터 안에서 — 전체 시나리오와 운영 동작

컨트롤 플레인에서 실행한다. `kubectl` 을 쓰는 항목까지 모두 돈다.

```bash
scripts/smoke.sh --base-url http://localhost:30080 --isolation k8s -n vet        # 54개
scripts/test-k8s-ops.sh --base-url http://localhost:30080 -n vet --compare       # 15개 + 비교
```

`test-k8s-ops.sh` 가 차례로 하는 일: Pod 배치 출력 → 다시 배포 4번 → clinic 의 롤링 업데이트와 롤백 → Pod 하나 삭제 → MySQL Pod 삭제 뒤 데이터 확인 → (비교) Recreate 로 배포.

### 과제 항목마다 남길 것

| 완성 기준 | 명령 | 봐야 할 것 |
|---|---|---|
| 노드가 모두 `Ready` | `kubectl get nodes -o wide` | 3대, `Ready` |
| 필요한 포트만 열었다 | 보안 그룹의 인바운드 규칙 화면 | 2번의 표와 같다 |
| 여러 Pod 로 배포 | `kubectl -n vet get deploy,sts` 와 `kubectl -n vet get pods -o wide` | `READY 2/2`, 두 Pod 의 `NODE` 가 다르다 |
| Probe | `kubectl -n vet describe deploy auth` | `Liveness`, `Readiness`, `Startup` 줄 |
| 롤링 업데이트 · 롤백 | `test-k8s-ops.sh` 의 2번, `kubectl -n vet rollout history deploy/clinic` | 버전 `1.0.0` → `rollback-test` → `1.0.0`, 리비전 증가 |
| Pod 삭제 후 자동 복구 | `test-k8s-ops.sh` 의 3번 | 지운 Pod 대신 새 이름의 Pod, 그동안 실패 0 |
| 클러스터 밖에서 접속 | PC 에서 돌린 `smoke.sh` 의 출력, 브라우저 화면 | `결과: 통과 22, 실패 0` |
| DB 는 클러스터 안에서만 | `kubectl -n vet get svc` 와, PC 에서 `nc -zv -w 3 <노드 공인 IP> 3306` | mysql 이 `ClusterIP`, PC 에서는 접속 실패 |
| DB Pod 교체 후 데이터 유지 | `test-k8s-ops.sh` 의 4번, `kubectl -n vet get pvc,pv` | "표식 예약이 남아 있다", PVC `Bound` |
| 설정은 ConfigMap | `kubectl -n vet get configmap vet-config -o yaml` | DB 주소, 연결 수, Redis 주소 |
| 비밀번호는 Secret | `kubectl -n vet describe secret vet-db` | 키 이름과 바이트 수만 나온다. **`-o yaml` 로 찍지 않는다**(값이 base64 로 보인다) |

### 손으로 하나씩 해 보려면

스크립트가 하는 일을 발표에서 직접 보여 줄 때 쓴다.

```bash
# 롤링 업데이트: 버전을 바꾼다 → Pod 가 하나씩 바뀐다
kubectl -n vet set env deployment/clinic APP_VERSION=1.0.1
kubectl -n vet rollout status deployment/clinic
curl -s http://localhost:30080/api/status/clinic        # "version":"1.0.1"

# 롤백
kubectl -n vet rollout history deployment/clinic
kubectl -n vet rollout undo deployment/clinic
curl -s http://localhost:30080/api/status/clinic        # "version":"1.0.0"

# 자동 복구
kubectl -n vet delete pod <clinic Pod 하나>
kubectl -n vet get pods -l app=clinic -w

# 데이터 유지
scripts/smoke.sh --base-url http://localhost:30080 --mark
kubectl -n vet delete pod mysql-0
scripts/smoke.sh --base-url http://localhost:30080 --verify <번호> --cleanup
```

상태 쪽지(`/status`)를 브라우저에 띄워 두면 버전과 응답한 Pod 이름이 5초마다 바뀌는 것이 보인다.

## 7. 노출 방법을 NodePort 로 정한 이유

과제가 이유를 적으라고 한 부분이다.

- kubeadm 으로 만든 클러스터에는 `LoadBalancer` Service 에 주소를 주는 장치가 없다. 수업의 MetalLB(L2)는 같은 네트워크 안에서 ARP 로 주소를 알리는 방식인데, AWS 의 VPC 는 그 방식을 받아 주지 않는다.
- NodePort 는 추가 설치 없이 모든 노드의 같은 포트(30080)로 들어올 수 있다. 어느 노드로 들어와도 kube-proxy 가 web 의 Pod 로 보낸다.
- 밖에서 들어오는 길을 web 하나로 좁혔다. 서비스 3개와 DB, Redis 는 `ClusterIP` 라 클러스터 안에서만 보인다.
- 잃는 것: 주소가 노드의 IP 다. 그 노드가 죽으면 다른 노드의 IP 로 바꿔 접속해야 하고, 포트가 80 이 아니다. ④에서는 ALB 가 이 둘을 해결한다.

## 8. 끝나면 정지한다

EC2 는 켜 둔 시간만큼 요금이 나온다.

```bash
# 내 PC 에서. 인스턴스 ID 는 콘솔이나 아래 명령으로 본다
aws ec2 stop-instances --instance-ids <ID 3개>
```

- 정지해도 디스크(EBS) 요금은 나온다. ③의 증거를 다 남겼으면 종료(terminate)한다.
- 다시 켜면 **공인 IP 가 바뀐다**(사설 IP 는 그대로다). 클러스터는 사설 IP 로 묶여 있어 그대로 돌아오고, 접속 주소와 보안 그룹의 "내 IP"만 다시 확인한다.
- MySQL 의 데이터는 워커의 디스크에 있어 정지했다 켜도 남는다.

## 막힐 때

| 증상 | 볼 것 | 원인과 조치 |
|---|---|---|
| `mysql-0` 과 `mysql-data` 가 `Pending` | `kubectl -n vet describe pvc mysql-data`, `kubectl get pv` | 라벨(`vet-db=true`)을 붙이지 않았거나, PV 가 `Released` 다. `gitops/README.md` 의 "DB 를 처음 상태로 되돌리려면" |
| `mysql-0` 이 `ContainerCreating` 에서 멈춘다 | `kubectl -n vet describe pod mysql-0` | 워커에 `/var/lib/vet-mysql` 폴더가 없다. 그 워커에서 만든다 |
| `ImagePullBackOff` | `kubectl -n vet describe pod <이름>` 의 Events | 이미지 주소나 태그가 다르다. 저장소가 비공개다. overlay 의 `images` 를 확인한다 |
| Pod 가 `Evicted`, 노드에 `DiskPressure` | `kubectl describe node <이름>`, 노드에서 `df -h /` | 디스크가 8GB 다. 1번의 표대로 20GB 이상으로 한다 |
| web 은 뜨는데 `/api/…` 가 503 | `kubectl -n vet logs deploy/web`, 3번의 ping 시험 | 다른 노드의 Pod 로 가는 길이 막혔다. 보안 그룹에 CNI 의 포트(프로토콜 4 또는 UDP 4789)가 없다 |
| 배포 중 새 Pod 가 `Pending`, 사유가 `didn't match pod topology spread constraints` | `kubectl -n vet describe pod <이름>` | 분산 규칙에 `nodeTaintsPolicy: Honor` 가 빠졌다. 없으면 컨트롤 플레인도 "Pod 가 0개인 노드"로 세어 배포가 멈춘다. 바탕에는 들어 있다(문제 기록 23번) |
| PC 에서 30080 으로 접속이 안 된다 | 보안 그룹, `kubectl -n vet get svc web` | 30080 이 내 IP 에 열려 있지 않다. 집과 학원의 IP 가 다르다 |
| 서비스가 뜨는 데 2분을 넘겨 재시작한다 | `kubectl -n vet describe pod <이름>` | t3 는 CPU 가 버스트형이라 느릴 수 있다. `startupProbe` 의 `failureThreshold`(60)를 늘린다 |
| 예약 날짜가 하루 어긋난다 | | 스크립트는 한국 시간으로 계산한다. 노드의 시간대는 상관없다 |
