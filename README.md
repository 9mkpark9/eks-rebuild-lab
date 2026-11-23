# 보듬 동물병원 예약 시스템 — 컨테이너에서 EKS 까지

동물병원 예약 서비스(서비스 3개 + 웹 + MySQL + Redis)를 소스에서 시작해
도커, 쿠버네티스(kubeadm), Amazon EKS 로 옮긴 기록이다.
단계마다 가장 단순한 형태로 먼저 만들어 돌리고, 미리 정한 점검 기준에 걸린 것을 문제로 기록하고 고쳤다.

모든 데이터는 테스트용 가짜 데이터다.

## 문서

| 문서 | 내용 |
|---|---|
| [① 워크로드 테스트](v2/docs/1-워크로드-테스트.md) | 소스를 빌드해 직접 실행하고 기능과 자원 사용량을 확인 |
| [② 이미지 빌드·컨테이너 테스트](v2/docs/2-이미지-빌드-컨테이너-테스트.md) | 이미지 5종, docker compose 로 컨테이너 6개 |
| [③ 쿠버네티스 전환](v2/docs/3-쿠버네티스-전환.md) | 로컬 클러스터에서 미리 돌려 보고, EC2 3대의 kubeadm 클러스터로 |
| [④ EKS 전환](v2/docs/4-EKS-전환.md) | EKS Auto Mode, ALB, EBS |
| [⑤ 최종 문서](v2/docs/5-최종문서.md) | 전체 정리, 문제 29건 총람, CloudFormation 스택, 지금 상태 |

## 폴더

```
msa/      서비스 3개(auth, clinic, reservation)와 공용 라이브러리 — Spring Boot 4, Java 21
web/      예약 화면(React)과 소개 페이지
db/       스키마와 시드 생성기 (msa/db/ 에 서비스별 스키마 분리와 권한)
v2/
├── docs/       문서 5개
├── workload/   ① 서비스를 직접 실행하는 스크립트
├── docker/     ② Dockerfile, Apache 설정, compose
├── k8s/        ③④ Kustomize (base, overlays: local / kubeadm / eks)
├── infra/      AWS 자원: CloudFormation 템플릿 4개와 실행 스크립트
└── tests/      시나리오 테스트(모든 단계 공통), 운영 동작 측정
```

## 빠르게 실행해 보기 (이 PC 에서, docker compose)

```bash
cp v2/docker/env.example v2/_run/secrets.env      # 비밀번호 5개를 채운다
docker compose -f v2/docker/compose.yaml --env-file v2/_run/secrets.env up -d --build --wait
node v2/tests/scenario.mjs --base-url http://localhost:28080
```

브라우저: http://localhost:28080/ (소개 페이지), http://localhost:28080/app/ (예약 화면, 테스트 계정 `owner001`).

쿠버네티스와 AWS 는 ③④ 문서와 [⑤ 6장](v2/docs/5-최종문서.md)을 본다.
