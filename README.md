# 보듬 동물병원 — 예약 시스템 WEB 계층

「동물병원 예약 시스템 부하분산 설계와 AWS 배포」 문서의 **WEB 계층 산출물**입니다.
문서 10.1의 `vet-web-<버전>.tar.gz`(= `web/dist/site` + `web/dist/app`)를 만드는 소스와,
로컬에서 WAS 없이 돌려 볼 수 있는 모의 서버가 들어 있습니다.

| 문서의 요구 | 구현 위치 |
|---|---|
| 병원 소개·진료 시간·위치·의료진 — 정적 HTML을 nginx가 바로 응답 (2.2, 3.1) | `web/site` → `dist/site` |
| 예약·관리자 화면 — TypeScript + React, Vite 빌드 (3.1) | `web/app` → `dist/app` |
| `/api`만 WAS로 넘기는 라우팅 (6장, 부록 E.3) | `deploy/nginx.conf` |
| 고객사마다 문구·사진만 바꿔 재사용 (3.1, 12장) | `web/clinic.config.json` |

> 병원명·주소·전화번호·의료진은 모두 가짜 값입니다(4장 「가짜 값만 사용」).

## 실행

> 새 PC에서 처음 셋팅할 때는 [docs/06-배포-환경-셋팅-가이드.md](docs/06-배포-환경-셋팅-가이드.md)를 먼저 보세요. 내려받을 도구(Git, Node.js, Corretto 21, AWS CLI), AWS 로그인, 배포·업데이트·삭제 순서가 있습니다.
> CLI 없이 AWS 콘솔에서 직접 만들어 보려면 [docs/07-콘솔로-직접-구축하기.md](docs/07-콘솔로-직접-구축하기.md)를 따르세요. 붙여 넣을 사용자 데이터와 IAM 정책은 `deploy/console/`에 있습니다.

```bash
cd web
npm install
npm run build     # tsc 검사 → dist/app(React) → dist/site(정적 HTML)
npm start         # http://localhost:8090  (nginx 라우팅 + 모의 예약 API)
```

화면 개발 중에는 `npm start`를 켠 채로 `npm run dev`를 실행하면 Vite(5173)가 `/api`와 `/assets`를 모의 서버로 넘깁니다.
모의 서버 옵션: `PORT`(기본 8090), `LATENCY_MS`(응답 지연, 기본 120), `TEST_PASSWORD`.

### 테스트 계정

- 보호자: `owner001` ~ `owner300` (owner001은 반려동물 2마리와 예약 3건이 미리 들어 있음)
- 간호사: `admin1`(정하나), `admin2`(윤소미) — 부록 A의 Locust 관리자 계정 이름을 그대로 씀
- 원장: `vet1`(김하늘 대표원장), `vet2`(이도윤 원장), `vet3`(박서연 원장) — 수의사와 1:1로 연결
- 비밀번호: 모두 `test-only` (모의 서버의 `TEST_PASSWORD`)

### 직원 화면 권한

간호사와 원장은 업무별로 화면이 나뉘고, 서로의 화면에는 들어갈 수 없습니다(화면은 「○○ 전용 화면입니다」 안내, API는 403).

| 기능 | 간호사 | 원장 |
|---|:-:|:-:|
| 전체 예약 현황 · 승인 | O | – |
| 공지 등록·삭제 | O | – |
| 내 진료 일정 (내가 맡은 예약만) | – | O |
| 진료 시간 열기·닫기 (본인 진료만) | – | O |
| 병원 현황 (14일 통계, WAS 분산) | – | O |

로컬(localhost)에서는 로그인 화면에 계정을 채워 주는 버튼이 보입니다. 운영 도메인에서는 보이지 않습니다.

## 화면

| 경로 | 화면 | 응답 위치 |
|---|---|---|
| `/` | 홈 — 진료 상태, 퀵 메뉴, 진료 과목, 의료진, 예약 방법, 진료시간·오시는 길·공지 | WEB(정적) |
| `/about` | 병원 소개 — 인사말, 진료 철학, 시설, 진료 시간, 오시는 길 | WEB(정적) |
| `/doctors` | 의료진 3명 상세 | WEB(정적) |
| `/services` | 진료 안내 — 진료 항목, 예약 규칙, FAQ | WEB(정적) |
| `/notices` | 공지사항 목록·상세 (`?id=`) | WEB + `/api/notices` |
| `/app/login` | 로그인 (보호자·직원 공통) | SPA |
| `/app/` | 보호자 홈 — 다음 예약, 반려동물, 병원 소식 | SPA |
| `/app/reserve` | 온라인 예약 — 반려동물 → 진료 항목 → 날짜(14일) → 시간·담당 수의사 | SPA |
| `/app/reservations` | 내 예약 — 변경(실패 시 기존 예약 유지)·취소 | SPA |
| `/app/pets` | 내 반려동물 등록·수정 | SPA |
| `/app/nurse` | **간호사 전용** 예약 현황 — 날짜별 전체 예약, 승인·일괄 승인, 처리 WAS(served_by) | SPA |
| `/app/nurse/notices` | **간호사 전용** 공지 등록·삭제 | SPA |
| `/app/director` | **원장 전용** 내 진료 일정 — 하루 타임라인, 다음 진료, 진료 중 표시 | SPA |
| `/app/director/slots` | **원장 전용** 내 진료 시간 열기·닫기(`is_open`), 하루 휴진 처리 | SPA |
| `/app/director/stats` | **원장 전용** 병원 현황 — 날짜별 예약 차트, 수의사·진료 항목별, WAS ±20% 기준(8장) | SPA |

예약 화면은 409 응답을 문서 6장의 규칙대로 안내합니다.
`SLOT_TAKEN`(이미 예약된 시간 → 시간 목록 새로고침), `PET_SAME_DAY`(같은 반려동물·같은 날),
`CANCELLED`, `NOT_REQUESTED`, 그리고 로그인 `429`(시도 제한)입니다.
화면 하단에는 마지막 응답의 `X-Web-Node` / `X-Served-By`가 보여 분산을 눈으로 확인할 수 있습니다.

## API 규약

문서 6장의 API 표를 그대로 따르고, 화면에 필요한 아래 항목을 더했습니다. **WAS(Spring Boot)에도 같은 형식으로 구현해야 합니다.**

| 추가 API | 용도 |
|---|---|
| `GET /api/auth/me` | 새로고침 시 세션의 사용자 확인 (401이면 로그아웃 상태). 응답에 `role`(`OWNER`·`NURSE`·`DIRECTOR`)과 원장의 `vetId` |
| `GET /api/admin/slots?date=` | 간호사: 그날 슬롯 조회(남은 시간 안내용, 바꾸기는 불가) |
| `POST /api/admin/notices` · `DELETE /api/admin/notices/{id}` | 간호사: 공지 등록·삭제 (2.2) |
| `GET /api/director/schedule?date=` | 원장: 내 슬롯과 거기 잡힌 예약(반려동물·보호자 포함) |
| `PUT /api/director/slots/{id}` `{isOpen}` | 원장: 내 슬롯 열기·닫기 (2.2의 `is_open`). 남의 슬롯이면 403 |
| `GET /api/director/stats` | 원장: 14일 집계 (날짜별, 수의사별, 진료 항목별, WAS별) |

문서 6장의 관리자 API(`/api/admin/reservations`, `.../approve`)는 경로를 그대로 두고 **간호사(NURSE) 권한**으로 바꿨습니다.
간호사 계정 이름도 `admin1`·`admin2`라서 부록 A의 Locust `AdminUser`는 고치지 않아도 됩니다.

JSON 키는 부록 A의 Locust와 맞췄습니다(`petId`, `slotId`, `reservationId`, `noticeId`, `status`).
전체 형식은 `web/app/src/types.ts`, 판정 규칙은 `web/server/mock-server.mjs`에 있습니다.

- `GET /api/slots`는 **비어 있고(`reservation_id IS NULL`), 열려 있고(`is_open = 1`), 지금 이후인 슬롯만** 돌려줍니다(Locust가 받은 목록에서 바로 고르기 때문).
- 시각은 병원 현지 시각 문자열 `YYYY-MM-DDTHH:mm:ss`로 주고받습니다.
- 공지에는 `category`(`NOTICE`·`EVENT`·`CLOSED`)와 `pinned`가 있습니다(회원·반려동물·공지 테이블은 문서에서 생략되어 여기서 정했습니다).
- 평소 슬롯의 진료 항목은 시각마다 수의사 3명이 세 항목을 하나씩 맡는 방식으로 시드했습니다. 할인 기간 3일은 모두 예방접종(4장)입니다.

## 고객사 바꾸기

`web/clinic.config.json`의 병원명·전화·주소·진료 시간·의료진을 바꾸고 `npm run build`를 다시 하면,
정적 페이지(`scripts/build-site.mjs`가 `{{값}}`을 채움), 예약 화면, 모의 서버가 함께 바뀝니다.
색상은 `web/site/assets/css/base.css`의 `:root` 토큰, 일러스트는 `web/site/assets/img/`에 있습니다.

## 배포 (문서 10.4 ①·②)

```bash
cd web && npm ci && npm run build && cd ..
tar -czf vet-web-$VER.tar.gz -C web/dist site app
aws s3 cp vet-web-$VER.tar.gz s3://$BUCKET/web/
aws s3 cp deploy/nginx.conf s3://$BUCKET/web/nginx.conf
```

WEB 사용자 데이터(부록 E.2)가 이 묶음을 `/usr/share/nginx/vet`에 풀면 `site/`는 `location /`, `app/`는 `location /app/`이 제공합니다.

## AWS 3-Tier 배포 (문서 10장)

> **베타 테스트 환경이다.** AWS에 올린 환경도 로컬과 같은 임시(가짜) 데이터와 테스트 계정만 쓴다. 실제 보호자·병원 데이터는 넣지 않는다. 처음 상태로 되돌리려면 `bash deploy/aws.sh dbinit`(DB를 지우고 오늘 날짜 기준 시드로 다시 채움).

외부 ALB → WEB(nginx, ASG 2~3) → 내부 ALB → WAS(Spring Boot, ASG 2~4) → RDS MySQL 8.4 Multi-AZ + ElastiCache.
CloudFormation 스택 6개(`cfn/`)와 배포 스크립트 하나(`deploy/aws.sh`)로 만든다. WAS 계층과 WEB 계층은 스택을 나눠 하나씩 올린다. 리전 ap-northeast-2, 고객사 이름 `vet01`.

```bash
bash deploy/aws.sh build     # web 빌드 → vet-web-1.0.0.tar.gz, WAS jar, db/seed.sql (오늘부터 14일)
bash deploy/aws.sh upload    # s3://vet01-artifacts-<계정>/{was,web,db,loadgen}/
bash deploy/aws.sh infra     # vet01-network → vet01-security → vet01-data (RDS Multi-AZ는 15~20분)
bash deploy/aws.sh dbinit    # 관리 EC2에서 schema.sql + seed.sql + 앱 계정(vet_app) 생성 (Session Manager)
bash deploy/aws.sh was       # vet01-was: 내부 ALB, WAS 시작 템플릿·ASG, 로그 버킷, WAS·DB 경보 (먼저)
bash deploy/aws.sh web       # vet01-web: 외부 ALB, WEB 시작 템플릿·ASG, 5xx 경보, 대시보드 (was 다음)
bash deploy/aws.sh loadgen   # vet01-loadgen: Locust EC2 + 탄력적 IP
bash deploy/aws.sh verify    # /health, /about, /api/notices 와 WEB·WAS 분산 확인
bash deploy/aws.sh status    # 스택 상태와 접속 주소
bash deploy/aws.sh destroy   # 전부 삭제 (RDS 최종 스냅샷과 배포 버킷은 남음)
```

| 폴더 | 내용 |
|---|---|
| `was/` | 예약 API — Java 21 + Spring Boot 4.1.1, JdbcTemplate, Spring Session(Redis), BCrypt. `./gradlew bootJar` |
| `db/` | `schema.sql`(6장 테이블 + 회원·수의사·반려동물·공지), `gen-seed.mjs`(시드 생성), `init.sh`(관리 EC2에서 실행) |
| `cfn/` | `network` · `security` · `data` · `was` · `web` · `loadgen` 템플릿 |
| `loadtest/` | 부록 A의 `locustfile.py` (Locust EC2의 `/opt/loadtest`) |

- WAS는 모의 서버(`web/server/mock-server.mjs`)와 같은 경로·JSON·오류 코드를 낸다. 화면은 그대로 붙는다.
- 외부 ALB 보안 그룹은 기본 `0.0.0.0/0`(누구나 보기)이다. 부하 테스트 때는 문서 5장대로 좁힌다: `ALLOWED_CIDR=<Locust IP>/32 bash deploy/aws.sh infra`.
- WAS 헬스 체크 유예는 300초다(문서는 120초). 첫 부팅에 JDK 설치가 들어가서 늘렸다. JDK를 구운 AMI를 쓰면 120초로 줄인다.
- **비용:** NAT Gateway, ALB 2개, RDS Multi-AZ, ElastiCache, EC2 7대(WEB 2, WAS 2, 관리 1, Locust 1)가 켜 둔 시간만큼 과금된다. 대략 시간당 0.55달러(약 750원), 하루 1.8만 원 안팎이며 그중 Locust(m7i.large)가 약 4분의 1이다. 부하 테스트를 안 할 때는 `vet01-loadgen` 스택만 지워도 되고, 다 쓰면 `destroy` 하세요.

## S3 미리보기 배포 (소개 페이지만 공개)

WAS 없이 소개 페이지만 다른 사람에게 보여 줄 때 씁니다. 주소 형식:
http://<버킷 이름>.s3-website.ap-northeast-2.amazonaws.com

```bash
cd web
npm run build:s3                                        # → dist/s3
bash scripts/deploy-s3.sh <버킷 이름>         # 같은 버킷에 다시 올리기
```

- 공지사항은 빌드할 때의 시드 데이터를 JSON 파일(`/api/notices`)로 함께 올려 읽기 전용으로 보입니다.
- `/app/*`(로그인·예약·관리자)는 WAS가 필요하므로 「미리보기 안내」 페이지로 연결됩니다.
- S3 웹사이트 주소는 HTTP만 됩니다. HTTPS가 필요하면 CloudFront를 앞에 붙입니다.
- 내리려면 `aws s3 rb s3://<버킷 이름> --force` (버킷과 파일이 영구 삭제됩니다).

## 폴더 구조

```
deploy/nginx.conf            WEB 계층 nginx 설정 (부록 E.3)
deploy/console/              콘솔로 직접 구축할 때 붙여 넣는 사용자 데이터·IAM 정책·대시보드 (docs/07)
web/
  clinic.config.json         고객사별 값
  site/pages/*.html          정적 페이지 원본 (<!-- @include --> 와 {{값}} 사용)
  site/partials/             공통 머리말·헤더·푸터
  site/assets/               CSS(base: 공통 토큰·헤더 / site: 페이지), JS, SVG 일러스트·아이콘
  app/src/                   React 예약·관리자 화면
  server/mock-server.mjs     로컬 모의 서버 (nginx 라우팅 + WAS API 흉내, 메모리 저장)
  scripts/build-site.mjs     정적 페이지 빌드
```

## 디자인

국내 대형 동물병원 홈페이지에서 흔히 쓰는 구성을 따랐습니다.

- 상단 바: 지금 진료 중 여부, 대표전화, 진료 시간
- 큰 히어로와 예약 버튼, 그 아래에 겹쳐 놓은 퀵 메뉴 카드(예약·진료시간·오시는 길·의료진)
- 진료 과목 카드, 의료진 카드, 예약 절차 4단계, 진료시간·약도·공지 3단 정보
- 데스크톱은 오른쪽 떠 있는 빠른 메뉴, 모바일은 하단 고정 「전화 문의 / 온라인 예약」 바

신뢰감을 주는 짙은 청록과, 예약 버튼에만 쓰는 따뜻한 주황을 썼습니다. 글꼴은 Pretendard(CDN)입니다.
사진 대신 SVG 일러스트를 넣었으니, 운영할 때는 실제 병원 사진과 지도로 바꾸면 됩니다.

## 한계

- 모의 서버는 메모리에만 저장해, 다시 시작하면 시드 상태로 돌아갑니다. 부하 테스트는 실제 WAS와 RDS가 있는 AWS 환경에서 합니다(7장).
- 외부 ALB가 HTTP 80이라 테스트 계정만 써야 합니다(11장). 운영에서는 ACM 인증서로 HTTPS를 붙입니다.
