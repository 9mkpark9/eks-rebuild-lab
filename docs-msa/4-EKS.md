# ④ EKS — AWS 에 배포

> **이 문서는 틀이다.** EKS 에서는 아직 아무것도 실행하지 않았다.
> "결과" 칸은 비어 있고, 프로젝트 기간(11월 19일 ~ 25일)에 실행하면서 채운다.
> 지금 적혀 있는 것은 무엇을 확인할지, 어떤 명령으로 확인할지, 그리고 ① ~ ③에서 알게 된 주의점이다.

③까지는 로컬 클러스터(노드 1개)였다. 이 단계에서 보는 것은 "같은 배포 파일이 AWS 에서도 그대로 도는가", 그리고 "노드가 여러 대이고 관리형 서비스가 있어야만 볼 수 있는 것"이다.

- 테스트한 날: (실행 전)
- 환경: (실행 전) EKS 버전, 노드 종류와 대수, 가용 영역, 리전

## 무엇을 만드나

| 자원 | 계획 | 누가 | 상태 |
|---|---|---|---|
| EKS 클러스터, VPC, 노드 그룹 | 노드는 t3.medium 3대를 가용 영역 2 ~ 3곳에 (근거: `검토한-대안.md` 4번) | Terraform | 실행 전 |
| RDS MySQL 8.4 Multi-AZ | prod 의 DB. 노드에서 3306 으로 접속할 수 있어야 한다 | Terraform | 실행 전 |
| 이미지 저장소 | ghcr.io 에 공개로 올린다. 이미지 6개 | GitHub Actions 또는 직접 | 실행 전 |
| 지표 서버 (metrics-server) | 자동 확장에 필요하다 | EKS 애드온 | 실행 전 |
| Argo CD | dev 는 `gitops/apps/vet/overlays/dev`, prod 는 `…/overlays/prod` 를 본다 | Terraform 또는 직접 | 실행 전 |
| 배포 파일 | ③에서 만든 것을 그대로 쓴다 | 완료 | 로컬에서 검증함 |

배포 파일(`gitops/apps/vet/`)은 ③에서 만든 그대로 쓰는 것이 목표다. 이 단계에서 배포 파일을 고쳐야 했다면 그 이유를 "발견한 문제와 조치"에 적는다.

## 올리기 전에 확인할 것

①~③에서 알게 된 것들이다. 하나라도 빠지면 Pod 가 뜨지 않거나 접속이 안 된다.

| # | 확인할 것 | 왜 | 확인 |
|---|---|---|---|
| 1 | 이미지 6개가 ghcr.io 에 올라가 있고 공개다 | 로컬에서는 이미지를 노드에 직접 넣었다. EKS 의 노드는 레지스트리에서 받는다 | ☐ |
| 2 | 이미지 태그와 `--build-arg VERSION` 이 같은 값이다 | 다르면 화면의 버전과 실제 태그가 어긋난다 | ☐ |
| 3 | overlay 의 `images` 태그가 올린 태그와 같다 | 없는 태그면 `ImagePullBackOff` | ☐ |
| 4 | 노드가 2대 이상이다 | prod 의 복제본은 서로 다른 노드에 강제로 나뉜다 | ☐ |
| 5 | 노드의 보안 그룹에서 RDS 의 3306 으로 갈 수 있다 | 초기화 Job 과 서비스 3개가 접속한다 | ☐ |
| 6 | dev 와 prod 네임스페이스에 Secret 을 만들었다 | Secret 은 Git 에 없다. 없으면 Pod 가 대기한다 | ☐ |
| 7 | prod 의 `vet-db-external` 에 RDS 주소와 관리자 계정이 들어 있다 | 초기화 Job 이 이 값으로 접속한다 | ☐ |
| 8 | 지표 서버가 떠 있다 (`kubectl top nodes` 가 값을 낸다) | 없으면 자동 확장이 `<unknown>` 이다 | ☐ |
| 9 | Argo CD 가 prod 의 reservation 복제본 수 차이를 무시한다 | 배포 파일(2개)과 HPA 가 함께 정한다. 무시하지 않으면 둘이 다툰다 | ☐ |

## 올리는 순서

```powershell
# 1) 클러스터에 접속 (Terraform 으로 만든 뒤)
aws eks update-kubeconfig --name <클러스터 이름> --region ap-northeast-2
kubectl get nodes -L topology.kubernetes.io/zone

# 2) Secret — dev
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\new-k8s-secrets.ps1 -Namespace dev

# 3) Secret — prod (RDS 관리자 비밀번호는 환경 변수 VET_DB_ADMIN_PASSWORD 로 준다)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\new-k8s-secrets.ps1 -Namespace prod -ExternalDbHost <RDS 주소> -ExternalDbAdminUser <관리자 계정>

# 4) 배포 — Argo CD 를 쓰면 동기화, 직접 하면 아래
kubectl apply -k gitops\apps\vet\overlays\dev
kubectl apply -k gitops\apps\vet\overlays\prod

# 5) 주소 확인 (EXTERNAL-IP 에 AWS 로드밸런서의 주소가 나온다)
kubectl -n dev get svc web
kubectl -n prod get svc web
```

RDS 가 준비되지 않았으면 `overlays\prod\kustomization.yaml` 의 `components` 한 줄을 `db-in-cluster` 로 바꿔 prod 도 MySQL Pod 로 띄울 수 있다. 그 경우 3)에서 `-ExternalDbHost` 를 빼고 실행한다.

## 어떻게 테스트하나

### A. ③과 같은 테스트를 AWS 주소로

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\smoke.ps1 -BaseUrl http://<dev 주소> -Isolation k8s -Namespace dev
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-k8s-ops.ps1 -Namespace dev -BaseUrl http://<dev 주소>

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\smoke.ps1 -BaseUrl http://<prod 주소> -Isolation k8s -Namespace prod -NoDbCheck
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-k8s-ops.ps1 -Namespace prod -BaseUrl http://<prod 주소> -SkipDb
```

| 테스트 | 로컬 (③) | EKS |
|---|---|---|
| dev smoke | 54개 통과 | |
| dev 운영 동작 | 12개 통과, 배포 중 실패 0 / 20,928건 | |
| prod smoke | 44개 통과 | |
| prod 운영 동작 | 7개 통과, 배포 중 실패 0 / 28,050건 | |

### B. EKS 에서만 볼 수 있는 것

③의 "로컬에서 확인하지 못한 것"을 여기서 확인한다.

| # | 확인할 것 | 방법 | 기대 | 결과 |
|---|---|---|---|---|
| 1 | 이미지를 레지스트리에서 받는다 | `kubectl -n dev describe pod -l app=auth` 의 Events | `Pulled … ghcr.io/9mkpark9/vet-auth:…` | |
| 2 | AWS 로드밸런서가 만들어진다 | `kubectl -n prod get svc web`, 그 주소로 `/health` | 주소가 나오고 200 | |
| 3 | 복제본이 서로 다른 노드에 놓인다 | `kubectl -n prod get pods -o wide` | 같은 앱의 두 Pod 의 NODE 가 다르다 | |
| 4 | 가용 영역에도 나뉜다 | `kubectl get nodes -L topology.kubernetes.io/zone` 과 3번을 맞춰 본다 | 영역이 2곳 이상이면 나뉜다 | |
| 5 | RDS 초기화 Job 이 성공한다 | `kubectl -n prod logs job/db-provision` | `[vet] slots=576 … users=305` | |
| 6 | Job 을 다시 돌려도 데이터가 남는다 | 예약을 하나 만든 뒤 Job 을 지우고 다시 적용 | "이미 초기화되어 있어 건너뜁니다", 예약이 남아 있다 | |
| 7 | 노드를 비워도 서비스가 유지된다 | 요청을 보내는 동안 `kubectl drain <노드> --ignore-daemonsets --delete-emptydir-data` | PDB 때문에 한 서비스의 Pod 가 한꺼번에 내려가지 않는다. 실패한 요청 수를 적는다 | |
| 8 | 노드가 죽으면 다른 노드에서 다시 뜬다 | EC2 콘솔에서 dev 의 mysql 이 있는 노드를 종료 | redis 와 mysql 이 약 1 ~ 2분 안에 다른 노드에서 뜬다(30초 뒤 옮기도록 설정). dev 의 데이터는 시드로 돌아간다 | |
| 9 | 자동 확장이 늘린다 | prod 에 부하를 건다. `kubectl -n prod get hpa reservation -w` | CPU 가 70% 를 넘으면 2 → 3 → 4, 부하가 멎으면 5분 뒤 줄어든다 | |
| 10 | RDS 가 장애 조치돼도 다시 붙는다 | RDS 를 "장애 조치와 함께 재부팅" | 서비스가 재시작 없이 다시 붙는다 (JVM 의 DNS 캐시는 60초다) | |

9번의 부하는 원본의 Locust 시나리오(`loadtest/locustfile.py`)를 prod 주소로 돌리면 된다. 기존 API 를 바꾸지 않았으므로 시나리오를 고칠 필요가 없다. 실행하지 않았다.

### C. 프로젝트의 주제 두 가지

| # | 주제 | 방법 | 기대 | 결과 |
|---|---|---|---|---|
| 1 | 클러스터를 지워도 명령 한 번으로 복원된다 | 클러스터를 지우고 다시 만든다. Secret 을 넣고 Argo CD 가 동기화하게 둔다 | dev 는 같은 시드 상태로, prod 는 RDS 의 데이터 그대로 돌아온다. smoke 가 통과한다. 걸린 시간을 적는다 | |
| 2 | dev 는 main 을 따라가고 prod 는 태그에 고정된다 | dev overlay 의 태그만 바꿔 커밋한다 | 상태 쪽지에서 dev 의 버전만 바뀌고 prod 는 그대로다 | |
| 3 | prod 는 승인된 버전만 반영한다 | prod overlay 의 태그를 바꿔 커밋한다 | 그 커밋 뒤에만 prod 의 버전이 바뀐다. 배포 중 실패한 요청 수를 적는다 | |
| 4 | 웹 서버를 태그 한 줄로 바꾼다 | web 의 태그 끝을 `-apache` 에서 `-nginx` 로 | `X-Web-Version` 이 바뀌고 smoke 가 그대로 통과한다 | |

상태 쪽지(`/status`)를 열어 두면 버전과 Pod 이름이 5초마다 갱신되므로, 위 변화를 화면으로 보여 줄 수 있다.

## 결과

(실행 전. 위 표의 "결과" 칸과 아래를 채운다.)

- 클러스터를 만드는 데 걸린 시간:
- 배포 뒤 전부 준비되기까지:
- dev 와 prod 의 주소:
- 노드별 Pod 배치 (`kubectl get pods -A -o wide` 요약):
- 노드별 사용량 (`kubectl top nodes`):

## 발견한 문제와 조치

(실행 전. 문제가 생기면 [문제와-해결.md](문제와-해결.md) 에 20번부터 이어서 적는다. 증상의 실제 출력 → 원인을 찾은 과정 → 원인 → 해결 → 확인 → 배운 점 순서다.)

## 미리 알아 둘 위험

실행하면서 걸릴 가능성이 있는 것들이다. 이 중 실제로 일어난 것은 위 "발견한 문제와 조치"로 옮긴다.

| 위험 | 근거 | 대비 |
|---|---|---|
| 노드 하나에 Pod 를 더 못 올린다 | t3.medium 의 Pod 한도는 17개다. 전체 30개 안팎이라 2대로는 빠듯하다 | 3대로 한다 |
| 서비스가 뜨는 데 오래 걸린다 | 뜰 때 CPU 10초를 쓴다. t3 는 2코어이고 버스트형이다. 측정은 14코어 PC 에서 했다 | startup 프로브가 120초까지 기다린다. 넘으면 `failureThreshold` 를 늘린다 |
| DB 연결 수가 모자란다 | RDS 의 `max_connections` 는 인스턴스 크기에 따라 정해진다. 로컬은 151 이었다 | 가장 많을 때 Pod 8개 x 5 = 40 이다. RDS 의 값을 확인하고 `DB_POOL_MAX` 로 맞춘다 |
| RDS 의 관리자 계정으로 초기화가 안 된다 | RDS 의 관리자는 일부 권한이 제한된다. 로컬에서는 root 로 시험했다 | Job 의 로그를 본다. 뷰 생성이나 권한 부여에서 막히면 문제 기록에 적는다 |
| 로드밸런서가 남아 VPC 가 지워지지 않는다 | Service 가 만든 로드밸런서는 Terraform 이 모른다 | 클러스터를 지우기 전에 `kubectl delete svc web` 을 dev 와 prod 에서 먼저 한다 |
| 누구나 접속할 수 있다 | 로드밸런서가 공개이고 테스트 계정이 README 에 있다 | 발표 전까지 Service 에 `loadBalancerSourceRanges` 로 접속 대역을 제한할 수 있다. 대역은 Git 에 넣지 않는다 |
| 비용이 계속 나간다 | 노드, 컨트롤 플레인, 로드밸런서 2개, NAT, RDS | 쓰지 않을 때는 지운다. 지운 뒤 다시 만드는 것이 주제 1의 시연이기도 하다 |

## 한계

(실행 뒤에 채운다. 지금 알고 있는 것만 적는다.)

- HTTP 만 쓴다. 인증서와 도메인은 이번 범위가 아니다.
- dev 의 DB 는 Pod 가 다시 뜨면 초기화된다. 의도한 동작이다.
- Redis 는 dev 와 prod 모두 Pod 하나다. 다시 뜨면 모두 로그아웃된다.
- Terraform, Argo CD 설정, GitHub Actions 는 이 저장소의 `gitops/apps/vet/` 밖의 일이다. 이 문서는 그 위에 올리는 앱의 배포와 확인만 다룬다.

## 근거 문서

- 배포 파일과 로컬 검증: `3-쿠버네티스.md`
- 노드 대수와 종류를 정한 근거, RDS 를 고른 이유: `검토한-대안.md` 3, 4번
- 바깥 DB 초기화 도구: `결정기록.md` D-3, D-4
- 실행 명령: `로컬실행.md` 의 "쿠버네티스"
