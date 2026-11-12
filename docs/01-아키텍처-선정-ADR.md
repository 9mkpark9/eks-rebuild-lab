# 아키텍처 선정 문서 (ADR)

- 프로젝트: 동물병원 예약 시스템 부하분산 설계와 AWS 배포 (고객사 코드 `vet01`, 가상 병원 「보듬 동물병원」)
- 작성일: 2026-10-19
- 근거 문서: 「동물병원 예약 시스템 부하분산 설계와 AWS 배포」(36쪽, 3차 개정)
- 이 문서의 범위: 오늘 내린 아키텍처 결정 전부와 그 이유, 검토한 대안, 결과와 한계. 계층별 세부 설정은 02~05 문서에 있다.

> 모든 데이터는 임시(가짜) 데이터다. 병원명·주소·전화번호·의료진·보호자 300명(연락처 010-0000-XXXX)·반려동물·예약·공지는 `db/gen-seed.mjs`가 만든 값이며 실제 개인정보는 없다. 테스트 계정은 owner001~owner300(보호자), admin1·admin2(간호사), vet1~vet3(원장)이다.

---

## 0. 오늘 진행한 작업 (시간 순)

| 순서 | 작업 | 결과 |
|---|---|---|
| 1 | 설계 PDF(36쪽) 분석 | 웹 계층 범위 확정: 정적 소개 페이지 + 예약·관리 SPA + `/api` 프록시 |
| 2 | 소개 페이지 5종 구현 (홈, 병원 소개, 의료진, 진료 안내, 공지사항) | 정적 HTML. 국내 대형 동물병원 홈페이지 구성 참고 |
| 3 | 예약·관리자 화면 구현 (TypeScript + React + Vite) | 로그인, 예약, 내 예약(변경·취소), 반려동물, 관리자 |
| 4 | 로컬 모의 서버 구현 (Node, 의존성 없음) | nginx 라우팅 + 6장 API 규칙 흉내. 브라우저로 전 흐름 검증 |
| 5 | S3 정적 웹사이트 미리보기 배포 | `bodeum-vet-web-f72cb1` (소개 페이지만 공개) |
| 6 | 관리자 화면을 간호사 전용 / 원장 전용으로 분리 | 화면과 API 모두 상호 접근 차단 |
| 7 | 직원 화면 디자인을 ChartNote EMR 스타일로 재작성, 글자 크기 상향 | ChartNote 스타일시트의 색 토큰·부품을 그대로 사용 |
| 8 | AWS 계정 점검 | AdministratorAccess, EC2 vCPU 할당량 384, 서울 리전 VPC 없음 |
| 9 | CloudFormation 스택 5개 작성 (network, security, data, app, loadgen) | 템플릿 검증 통과 |
| 10 | network → security 배포 | 완료 |
| 11 | data 1차 배포 실패 → 원인 수정 → 재배포 | ElastiCache 자동 장애 조치 설정 오류. 수정 후 완료 |
| 12 | WAS 구현 (Java 21 + Spring Boot 4.1.1) 및 빌드 | `vet-api-1.0.0.jar` 첫 빌드 성공, 로컬 기동 시험 통과 |
| 13 | loadgen 배포 | Locust EC2 + 탄력적 IP 완료 |
| 14 | DB 초기화 (관리 EC2, Session Manager) | 슬롯 576, 예약 171, 사용자 305, 공지 5. `max_connections` 144 |
| 15 | app 스택 배포 (ALB 2개, ASG 2개) | 완료. WEB 2대·WAS 2대 모두 healthy(2a·2c 각 1대). `/health`·`/about`·`/api/notices`·`/api/slots` 정상 |

| 16 | 콘솔 실습을 위해 5개 스택 전체 삭제 | RDS 최종 스냅샷과 배포 버킷만 남김 |
| 17 | app 스택을 `was`·`web` 두 스택으로 분리, 콘솔 구축 가이드(docs/07) 작성 | WAS 계층과 WEB 계층을 하나씩 배포. 템플릿 검증 통과(배포는 아직 안 함) |

접속 주소였던 `http://vet01-alb-ext-72802186.ap-northeast-2.elb.amazonaws.com`는 16번에서 삭제되어 지금은 열리지 않는다.

---

## ADR-001. 3-Tier 구조: 외부 ALB → WEB → 내부 ALB → WAS → 데이터

- 상태: 채택
- 맥락: 평상시 동시 40명, 공지 직후 30초 안에 140명. 같은 시간대 중복 예약 0건이 필수. 이 구성을 고객사 50곳에 재사용해야 한다.
- 결정: 요청은 외부 ALB → WEB(nginx) Auto Scaling 그룹 → 내부 ALB → WAS(Spring Boot) Auto Scaling 그룹 → RDS MySQL / ElastiCache 순서로 흐른다. AWS 3-Tier 웹 아키텍처 워크숍과 같은 배치다.
- 검토한 대안
  - 2-Tier(ALB → WAS 직접): 구성은 단순하지만 정적 페이지 요청(평소 접속의 약 60%)까지 WAS가 받는다. 계층별 독립 확장도 안 된다.
  - 단일 EC2(모의 서버 그대로): 비용은 가장 낮다. 하지만 부하분산·장애 조치를 검증할 수 없고, 메모리 저장이라 서버를 여러 대로 늘리면 데이터가 갈라진다.
  - 서버리스(API Gateway + Lambda): 과제의 검증 대상(ALB 분산, ASG, 연결 풀)과 맞지 않는다.
- 결과: WEB과 WAS를 따로 늘리고 줄일 수 있다. 정적 요청은 WEB에서 끝나 WAS·DB 부담이 준다. 대신 ALB 2개와 NAT 비용이 든다.

## ADR-002. 리전과 가용 영역: 서울 `ap-northeast-2`, `2a`(apne2-az1)·`2c`(apne2-az3)

- 상태: 채택
- 맥락: ALB는 서로 다른 AZ의 서브넷이 최소 2개 필요하다. RDS Multi-AZ와 ElastiCache 서브넷 그룹도 2개 AZ가 필요하다.
- 결정: 리전은 서울, AZ는 `ap-northeast-2a`와 `ap-northeast-2c` 두 곳.
- 이유
  1. 보호자·병원이 국내라 지연 시간이 가장 짧다. 의료 데이터의 국외 이전 우려도 없다.
  2. 2개 AZ는 ALB·RDS Multi-AZ·서브넷 그룹의 최소 요건을 채운다. AZ 하나가 장애 나도 나머지 AZ로 서비스가 계속된다(TC-06).
  3. 3~4개 AZ로 늘리면 서브넷·NAT·AZ 간 전송 비용이 늘지만, 동시 140명 규모에서는 가용성 이득이 크지 않다.
  4. 설계 문서(5장)가 2a·2c를 가정했다. 과정 실습도 같은 조합이라 팀 공통 기준을 유지한다.
  5. 사용할 인스턴스 유형(t3.micro·t3.small·t3.medium·m7i.large)이 2a·2c 모두에서 제공되는 것을 `describe-instance-type-offerings`로 확인했다.
- AZ 이름과 ID: 2a=`apne2-az1`, 2b=`apne2-az2`, 2c=`apne2-az3`, 2d=`apne2-az4`(이 계정 기준). 다른 계정과 물리 AZ를 맞춰야 할 때는 이름이 아니라 ID로 비교한다.
- 2b·2d를 쓰지 않은 이유: 두 AZ로 요건을 모두 채우므로 추가할 필요가 없다. 운영에서 AZ 하나 장애 시 남은 한 곳에 몰리는 위험이 크다고 판단되면 3번째 AZ로 2b를 추가한다.

## ADR-003. 네트워크: VPC `10.0.0.0/16`, AZ 2개 × 계층 4개 = 서브넷 8개, NAT Gateway 1개

- 상태: 채택 (NAT 1개는 비용 때문에 받아들인 한계)
- 결정
  - public(10.0.0.0/24, 10.0.1.0/24): 외부 ALB, NAT Gateway
  - web(10.0.10.0/24, 10.0.11.0/24): WEB 인스턴스
  - app(10.0.20.0/24, 10.0.21.0/24): 내부 ALB, WAS, 관리 EC2
  - db(10.0.30.0/24, 10.0.31.0/24): RDS, ElastiCache
  - 세 번째 옥텟을 계층별로 10 단위로 나눴다. 사설 IP만 보고도 계층을 알 수 있다.
- 이유
  - 계층마다 서브넷을 나눠야 라우팅과 보안 그룹을 계층 단위로 관리할 수 있다.
  - /24(가용 IP 251개)는 ASG 최대 대수와 ALB 노드를 넉넉히 수용한다.
  - web·app 서브넷은 호스트 이름 유형을 리소스 이름(인스턴스 ID)으로 바꿨다. 분산 확인 헤더(X-Web-Node, X-Served-By)에 사설 IP가 드러나지 않는다.
  - S3 게이트웨이 엔드포인트를 두어 배포 파일 다운로드가 NAT를 거치지 않는다(추가 요금 없음).
- 한계: NAT Gateway가 2a 한 곳에만 있어 2a 장애 시 2c의 사설 서브넷도 외부로 나가지 못한다. 운영 구성은 AZ마다 NAT 1개(시간당 0.059달러 추가).

## ADR-004. WEB 계층: nginx가 정적 페이지를 직접 응답하고 `/api`만 WAS로 프록시

- 상태: 채택
- 결정: 소개 페이지는 빌드 때 완성된 정적 HTML(`dist/site`), 예약·직원 화면은 React SPA 빌드 결과(`dist/app`)다. nginx는 `location /`, `location /app/`, `location /api/`(내부 ALB로 프록시), `location = /health`만 가진다.
- 이유: 검색 엔진이 그대로 읽고 첫 화면이 빠르다. 방문자 요청이 WAS·DB에 닿지 않는다. 고객사마다 `clinic.config.json`과 사진만 바꿔 다시 빌드할 수 있다.
- 대안: CloudFront 캐시는 이번 과제에서 부하가 반드시 ALB를 거치는지 재야 하므로 제외했다(문서 2.4장). 운영 단계에서 다시 검토한다.

## ADR-005. WAS 언어: Java 21 + Spring Boot 4.1.1

- 상태: 채택
- 이유: 문서 3.2장의 7가지 근거를 따른다. `@Transactional`이 실패 시 전체 롤백을 보장하고, Spring Session으로 무상태가 쉽다. HikariCP 연결 풀이 기본 포함되고, jar 하나라 배포가 단순하다. 팀 경험이 있고 지원 기간이 길다(4.1 OSS 지원 2027-07-31, Java 21 LTS).
- 버전 확인: Maven Central에서 Spring Boot 4.1.1이 배포되어 있음을 확인했다. Gradle은 9.8.1이다. Spring Boot 4의 모듈 분리에 맞춰 `spring-boot-starter-webmvc`, `spring-boot-starter-session-data-redis`를 쓴다.
- 대가: JVM 기동과 메모리 비용이 크다. 그래서 WAS는 메모리 4 GiB(t3.medium)를 쓰고, 스파이크는 최소 2대로 버틴다.

## ADR-006. 무상태 서버: 로그인 세션은 ElastiCache(Redis 7.1), 예약 상태는 RDS에만

- 상태: 채택
- 이유: ALB 고정 세션 없이 어느 WAS로 가도 같은 결과가 나온다. 관리자 계정 정지 시 세션을 즉시 지울 수 있다. JWT는 저장소가 필요 없지만 즉시 무효화가 어렵다.
- 오늘 고친 점: 컨트롤러가 `HttpSession`을 인자로 받으면 로그인하지 않은 요청에도 세션이 새로 생겨 ElastiCache에 쌓인다. 그래서 `@SessionAttribute(required = false)`로 바꿨다. 이제 기존 세션만 읽는다.

## ADR-007. 데이터베이스: RDS for MySQL 8.4.11, db.t3.small, Multi-AZ

- 상태: 채택 (세부는 05 문서)
- 요약: 조건부 UPDATE, 유니크 제약, 저장 생성 열이 모두 되는 관계형 DB다. 8.0은 RDS 표준 지원이 2026-07-31에 끝나 8.4를 썼다. db.t3.micro는 연결 한도 여유가 없어 db.t3.small을 골랐다(실측 `max_connections` 144). 장애 시 자동 전환을 위해 Multi-AZ(주 2c, 대기 2a)로 두었다.

## ADR-008. 중복 예약 방지: 슬롯 행 조건부 UPDATE + 유니크 제약 (판정은 DB 한 곳)

- 상태: 채택
- 결정: 슬롯마다 행 하나다. `UPDATE slots SET reservation_id=? WHERE slot_id=? AND reservation_id IS NULL AND is_open=1`이 0행이면 409 `SLOT_TAKEN`이다. 같은 반려동물·같은 날은 저장 생성 열 `active_pet_day`의 유니크 키로 막는다(409 `PET_SAME_DAY`). 변경은 기존 슬롯을 비운 뒤 새 슬롯을 잡고, 실패하면 전체 롤백한다. 교착 상태는 트랜잭션 밖에서 50~150ms 대기 후 최대 2회 재시도하고, 그래도 실패하면 409 `BUSY`다.
- 이유: WAS 대수와 무관하게 결과가 같다. Redis 분산 락이나 대기열 없이 DB만으로 검증 가능하다.

## ADR-009. 인프라 코드: CloudFormation 스택 6개 + 배포 스크립트 1개

- 상태: 채택
- 결정: `cfn/network.yaml`, `security.yaml`, `data.yaml`, `was.yaml`, `web.yaml`, `loadgen.yaml`. 앞 스택의 값은 Export/ImportValue로 넘긴다. 순서와 반복 작업은 `deploy/aws.sh`(build, upload, infra, dbinit, was, web, loadgen, verify, status, destroy)가 맡는다.
- 변경(같은 날): 처음에는 ALB 2개와 WEB·WAS를 `app.yaml` 한 스택에 두었다. 계층을 하나씩 배포·확인하고 따로 갱신할 수 있도록 `was.yaml`(내부 ALB·WAS)과 `web.yaml`(외부 ALB·WEB)로 나눴다. WEB이 내부 ALB 주소를 가져다 쓰므로 was → web 순서다.
- 이유: AWS 기본 도구라 상태 파일이 없다. 스택 삭제로 한꺼번에 정리되어 테스트 후 비용 관리가 쉽다. 고객사 이름과 VPC 대역만 매개변수로 바꿔 재사용한다.
- 대안: Terraform은 멀티 클라우드에 강하지만 이 과제는 AWS 하나라 이점이 적다.
- 오늘 겪은 문제와 해결
  - Windows용 AWS CLI가 한글이 든 템플릿을 CP949로 읽어 실패했다. `AWS_CLI_FILE_ENCODING=UTF-8`로 해결했다.
  - Git Bash 경로(`/c/...`)를 Windows용 `aws.exe`가 읽지 못했다. `cygpath -m`으로 `C:/...` 경로로 바꿨다.
  - 사용자 데이터 heredoc 안의 `${aws:AutoScalingGroupName}`이 bash 치환 오류로 부팅 스크립트를 멈출 수 있었다. `\${!aws:...}`로 이스케이프했다.

## ADR-010. 보안: 보안 그룹 체인, Secrets Manager, Session Manager, IMDSv2

- 상태: 채택
- 결정
  - 각 계층은 바로 앞 계층의 보안 그룹에서 오는 트래픽만 받는다: alb-ext(80, 허용 대역) → web(80) → alb-int(8080) → was(8080) → db(3306, was·ops), cache(6379, was).
  - SSH 22번은 열지 않는다. 관리 접속은 Session Manager로만 한다(ops·locust SG 인바운드 없음).
  - RDS 마스터 비밀번호는 RDS가 Secrets Manager로 관리한다. 앱 DB 계정(`vet_app`)과 ElastiCache AUTH 토큰도 Secrets Manager에 둔다. WAS는 시작할 때 읽어 환경 변수로만 넘긴다.
  - 인스턴스 메타데이터는 IMDSv2만 허용한다(`HttpTokens: required`).
  - IAM은 계층별 최소 권한이다. WEB은 `web/*` 읽기, WAS는 `was/*`와 비밀 2개 읽기, 관리 EC2는 `db/*`와 RDS 비밀 읽기만 한다.
- 문서와 다르게 둔 점: 외부 ALB 허용 대역 기본값이 `0.0.0.0/0`이다(다른 사람에게 보여 주기 위해). 문서 5장은 부하 테스트 기간에 Locust EIP(3.34.231.137)와 팀원 IP만 열라고 권장한다. 테스트 때는 `ALLOWED_CIDR=3.34.231.137/32`로 다시 배포한다.

## ADR-011. 인스턴스 유형 요약

| 용도 | 유형 | vCPU · 메모리 | 시간당(서울, 온디맨드) | 선정 이유 요약 | 상세 |
|---|---|---|---|---|---|
| WEB (nginx) | t3.small × 2~3 | 2 · 2 GiB | 0.026달러 | 정적 응답·프록시만. 평균 부하 낮고 순간 증가 | 03 문서 |
| WAS (Spring Boot) | t3.medium × 2~4 | 2 · 4 GiB | 0.052달러 | JVM 힙 2 GiB + 연결 풀 + BCrypt | 04 문서 |
| RDS MySQL | db.t3.small Multi-AZ | 2 · 2 GiB | 0.104달러 | 연결 한도 144 ≥ 필요 57 | 05 문서 |
| ElastiCache | cache.t3.micro × 1 | 2 · 0.5 GiB | 0.025달러 | 세션만 저장 | 05 문서 |
| 관리 EC2 | t3.micro × 1 | 2 · 1 GiB | 0.013달러 | DB 초기화·검증 SQL만 | 05 문서 |
| Locust | m7i.large × 1 | 2 · 8 GiB | 0.1239달러 | 버스트형이 아니라 일정한 부하 생성 | 04 문서 |

요금은 AWS Pricing API로 2026-10-19에 조회한 서울 리전 Linux 온디맨드 값이다. 공인 IPv4는 개당 시간당 0.005달러가 별도로 붙는다.

## ADR-012. 직원 권한: 간호사 전용 / 원장 전용으로 업무별 분리

- 상태: 채택
- 결정
  - 간호사(admin1·admin2): 전체 예약 현황, 승인, 공지 등록·삭제, 슬롯 조회만 가능하다. API는 `/api/admin/*`다.
  - 원장(vet1~vet3, 수의사와 1:1): 내 진료 일정, 내 진료 시간 열기·닫기, 병원 현황 통계. API는 `/api/director/*`다.
  - 서로의 화면은 「○○ 전용 화면입니다」로 막고, API는 403이다. 원장이 남의 슬롯을 바꾸면 403이다.
- 이유: 접수 데스크 업무와 진료 업무를 나눈다. 간호사 경로를 문서의 관리자 API 경로(`/api/admin`)로 유지해 부록 A의 Locust `AdminUser`가 바뀌지 않는다.

## ADR-013. 직원 화면 디자인: ChartNote EMR 디자인 시스템

- 상태: 채택
- 결정: 간호사·원장 화면은 홈페이지 틀 대신 EMR 화면 틀을 쓴다. 상단 남색 메뉴 막대, 폴더 탭, 패널+표, 하단 상태 막대로 구성한다. 색 토큰과 부품(.emr-panel, .emr-table, .emr-btn, .emr-pill 등)은 ChartNote의 공개 스타일시트 값을 그대로 옮겼다.
- 이유: 직원은 밀도 높은 표와 목록·상세 배치에 익숙하다. 보호자용 홈페이지와 시각적으로 구분된다.
- 조정: 처음 12.5px였던 글자를 사용자 요청으로 14.5px(표 14px)로 키웠다. 버튼·입력칸 높이도 30~32px로 키웠다.
- 상태 막대에 마지막 응답의 WEB·WAS 인스턴스 이름을 보여 분산을 눈으로 확인할 수 있다.

## ADR-014. 공개 미리보기: S3 정적 웹사이트

- 상태: 채택 (3-Tier와 별도)
- 결정: WAS 없이 소개 페이지만 공개하는 버킷 `bodeum-vet-web-f72cb1`을 둔다. 공지는 시드 데이터를 JSON 파일로 함께 올린다. `/app/*`는 「미리보기 안내」로 연결한다.
- 이유: 월 몇백 원으로 다른 사람에게 디자인을 보여 줄 수 있다. 3-Tier를 내려도 미리보기는 남는다.

## ADR-015. 로컬 검증: 의존성 없는 모의 서버

- 상태: 채택
- 결정: `web/server/mock-server.mjs`가 nginx 라우팅과 WAS API 규칙(409 코드, 권한, 세션, 로그인 시도 제한)을 메모리로 흉내 낸다.
- 이유: AWS 없이 화면 전 흐름을 검증한다. WAS 구현의 사실상 API 명세 역할도 한다. 실제 WAS는 같은 경로·JSON 키·오류 코드를 낸다.

---

## 문서와 다르게 둔 값 (변경 이력)

| 항목 | 문서 값 | 실제 값 | 이유 |
|---|---|---|---|
| WAS 헬스 체크 유예 | 120초 | 300초 | 첫 부팅에 JDK 설치(dnf)가 들어가 기동이 늦다. JDK를 구운 AMI를 쓰면 120초로 줄인다 |
| 외부 ALB 허용 대역 | Locust EIP·팀원 IP만 | 0.0.0.0/0 (매개변수) | 다른 사람에게 보여 주기 위해. 부하 테스트 때 좁힌다 |
| ElastiCache | 노드 기반 | 노드 1개, 자동 장애 조치 끔 | 노드 1개에서는 자동 장애 조치를 켤 수 없다(1차 배포 실패 원인) |
| 앱 DB 계정 권한 | SELECT·INSERT·UPDATE | + notices 테이블 DELETE | 간호사의 공지 삭제 기능 |
| 시드 예약의 served_by | (없음) | `seed` | 실제 WAS가 처리한 예약과 구분. 병원 현황의 WAS 분산 집계에서 뺀다 |
| 관리자 계정 | 관리자 2명 | 간호사 2명(admin1·admin2) + 원장 3명(vet1~vet3) | 직원 권한 분리 |

## 비용 요약 (전부 켜 둘 때)

| 항목 | 수량 | 시간당 | 월(730시간) |
|---|---|---|---|
| ALB | 2 | 0.045달러 + LCU | 약 33달러 + LCU |
| NAT Gateway | 1 | 0.059달러 + GB당 0.059달러 | 약 43달러 + 전송량 |
| WEB t3.small | 2 | 0.052달러 | 약 38달러 |
| WAS t3.medium | 2 | 0.104달러 | 약 76달러 |
| RDS db.t3.small Multi-AZ | 1 | 0.104달러 | 약 76달러 + 스토리지 |
| ElastiCache cache.t3.micro | 1 | 0.025달러 | 약 18달러 |
| 관리 EC2 t3.micro | 1 | 0.013달러 | 약 9.5달러 |
| Locust m7i.large | 1 | 0.1239달러 | 약 90달러 |
| 공인 IPv4 (NAT, Locust, 외부 ALB 2) | 약 4 | 0.02달러 | 약 15달러 |
| 합계 | | 약 0.55달러 | 약 400달러 |

테스트 당일만 켜고 `bash deploy/aws.sh destroy`로 지운다. 부하 테스트를 안 할 때는 `vet01-loadgen`만 지워도 약 4분의 1이 준다.
