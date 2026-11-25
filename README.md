# 실습 — 보듬 동물병원 예약 시스템을 컨테이너에서 EKS 까지

동물병원 예약 서비스를 소스에서 시작해 직접 옮겨 보는 실습 저장소다. 서비스는 3개(auth, clinic, reservation)이고, 웹, MySQL, Redis 가 함께 돈다. 옮기는 순서는 다음과 같다.

```
WSL 2 에서 직접 실행 ─▶ 이미지와 docker compose ─▶ EC2 3대의 kubeadm 클러스터 ─▶ Amazon EKS Auto Mode ─▶ (선택) RDS
```

실습마다 **실습 목표 → 사전 준비 → 단계별 명령과 출력 예 → 결과 확인 → 자원 정리** 순서로 되어 있다. `# 출력 예` 는 모두 2026-11-25 에 실제로 실행해 받은 출력이다. 계정 번호, 공인 IP, 토큰은 가렸다.

모든 데이터는 테스트용 가짜 데이터다.

## 실습 목록

| 실습 | 하는 일 | 환경 | 시간 (대략) |
|---|---|---|---|
| [lab01: 워크로드 직접 실행](v2/docs/lab/lab01-워크로드-직접-실행.md) | jar 빌드, DB 초기화, 환경 변수로 서비스 실행, 세션이 Redis 에 저장되는 것 확인 | WSL 2 | 20분 |
| [lab02: 이미지와 compose](v2/docs/lab/lab02-이미지와-compose.md) | 두 단계 빌드, 컨테이너 6개 healthy, root 가 아닌 사용자, 힙 상한, 정상 종료와 강제 종료 비교 | WSL 2 | 20분 |
| [lab03: AWS 준비와 ECR](v2/docs/lab/lab03-AWS-준비와-ECR.md) | CloudFormation 으로 네트워크와 ECR 만들기, 이미지 push | AWS | 10분 |
| [lab04: kubeadm 클러스터 구축](v2/docs/lab/lab04-kubeadm-클러스터-구축.md) | EC2 3대, `kubeadm init`·`join`, Flannel, CoreDNS 분산, 볼륨 등록 | EC2 3대 | 25분 |
| [lab05: 앱 배포](v2/docs/lab/lab05-앱-배포.md) | Secret, ECR 로그인, Kustomize, Probe, NodePort | kubeadm | 20분 |
| [lab06: 배포 운영](v2/docs/lab/lab06-배포-운영.md) | Pod 자동 복구, 롤링 업데이트, 롤백, DB Pod 교체 뒤 데이터 유지 | kubeadm | 20분 |
| [lab07: EKS](v2/docs/lab/lab07-EKS.md) | gp2 문제 재현, Auto Mode 노드, EBS, ALB | EKS | 25분 |
| [lab08: 선택 과제 RDS](v2/docs/lab/lab08-선택-RDS.md) | 사설 서브넷, 초기화 Job, 두 클러스터가 함께 쓰는 RDS, 모두 지우기 | kubeadm + EKS | 30분 |

순서와 의존 관계는 [실습 목차](v2/docs/lab/README.md)에 있다. 명령만 한 장에 모은 요약본은 [실습 가이드](v2/docs/7-실습-가이드.md)다.

## 준비물

| 항목 | 내용 |
|---|---|
| PC | Windows + WSL 2 Ubuntu (lab01 ~ lab03). kubectl 은 WSL 이나 Windows 어느 쪽이든 된다 |
| 도구 | OpenJDK 21, Node.js 22, Docker Engine, curl, AWS CLI v2, kubectl |
| AWS | 서울 리전(ap-northeast-2) 계정. lab04 부터 요금이 나간다 |

```bash
git clone <저장소 주소> ~/vet2-lab && cd ~/vet2-lab
cp v2/docker/env.example v2/_run/secrets.env     # 비밀번호 5개를 채운다
```

`v2/_run/` 은 Git 에 올라가지 않는다. 비밀번호, kubeconfig, 실행 기록은 모두 여기에 둔다.

## 비용과 정리

lab03 까지는 거의 무료다. lab04 부터 EC2, EKS, ALB, RDS 요금이 시간 단위로 나가고, 모두 켜 두면 시간당 약 0.55달러다.

- 쉬는 동안: 각 실습 끝의 **자원 정리** 에 있는 멈추기를 한다.
- 다 끝나면: [lab08 의 모두 지우기](v2/docs/lab/lab08-선택-RDS.md) 순서대로 스택을 지운다. 지우는 순서를 지키지 않으면 스택이 지워지지 않는다.

## 빠르게 맛보기 (이 PC 에서 docker compose 만)

```bash
docker compose -f v2/docker/compose.yaml --env-file v2/_run/secrets.env up -d --build --wait
node v2/tests/scenario.mjs --base-url http://localhost:28080
```

브라우저에서 http://localhost:28080/ (소개 페이지)와 http://localhost:28080/app/ (예약 화면, 테스트 계정 `owner001`)을 연다.

## 폴더

```
msa/      서비스 3개(auth, clinic, reservation)와 공용 라이브러리 — Spring Boot 4, Java 21
web/      예약 화면(React)과 소개 페이지
db/       스키마와 시드 생성기
v2/
├── docs/lab/   실습 8개  ← 여기서 시작
├── docs/       단계별 설명 문서, 발표 자료, 시연 영상
├── workload/   lab01: 서비스를 직접 실행하는 스크립트
├── docker/     lab02: Dockerfile, Apache 설정, compose
├── infra/      lab03·04·07·08: CloudFormation 템플릿과 실행 스크립트
├── k8s/        lab05 ~ 08: Kustomize (base, overlays: local / kubeadm / eks / kubeadm-rds / eks-rds)
└── tests/      시나리오 테스트(모든 실습 공통), 운영 동작 측정
```

## 더 읽을거리

각 결정을 왜 그렇게 했는지, 어떤 문제가 생겼고 어떻게 고쳤는지는 단계 문서에 있다.

| 문서 | 내용 |
|---|---|
| [① 워크로드 테스트](v2/docs/1-워크로드-테스트.md) | 직접 실행과 자원 사용량 |
| [② 이미지 빌드·컨테이너 테스트](v2/docs/2-이미지-빌드-컨테이너-테스트.md) | 이미지 5종, compose |
| [③ 쿠버네티스 전환](v2/docs/3-쿠버네티스-전환.md) | 로컬 클러스터, kubeadm |
| [④ EKS 전환](v2/docs/4-EKS-전환.md) | Auto Mode, ALB, EBS |
| [⑤ 최종 문서](v2/docs/5-최종문서.md) | 전체 정리, 문제 총람, 스택 |
| [⑥ 선택 과제](v2/docs/6-선택과제.md) | RDS |
| [발표 자료 (PDF)](v2/docs/발표-보듬-EKS.pdf) · [시연 영상](v2/docs/video/시연-EKS.mp4) | |
