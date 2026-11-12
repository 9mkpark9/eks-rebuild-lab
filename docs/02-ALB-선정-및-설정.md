# ALB 선정 및 설정

- 대상: 인터넷 → WEB 계층 앞의 외부 로드 밸런서 `vet01-alb-ext`
- 작성일: 2026-10-19
- 정의 위치: 외부 ALB는 `cfn/web.yaml` (스택 `vet01-web`), 내부 ALB는 `cfn/was.yaml` (스택 `vet01-was`). 처음에는 `cfn/app.yaml` 한 스택이었다가 같은 날 나눴다, 보안 그룹은 `cfn/security.yaml` (스택 `vet01-security`)
- WEB → WAS 사이의 내부 로드 밸런서는 04 문서에서 다룬다.

> 이 환경의 데이터는 모두 임시(가짜) 데이터이며, 외부 ALB는 HTTP 80만 연다. 실제 개인정보를 넣지 않는다.

---

## 1. 로드 밸런서 유형별 특성 비교

| 유형 | 계층 | 주요 특성 | 외부 진입점 검토 결과 |
|---|---|---|---|
| ALB (Application Load Balancer) | L7 (HTTP/HTTPS) | 경로·호스트 기반 라우팅, HTTP 헬스 체크(경로·응답 코드), 요청 단위 라운드 로빈, 액세스 로그에 대상·응답 시간 기록, HTTP 지표(5xx, TargetResponseTime) 제공 | 채택. 웹 서비스이고 문서 8장의 측정 지표가 HTTP 기준이다 |
| NLB (Network Load Balancer) | L4 (TCP/UDP/TLS) | 고정 IP·탄력적 IP, 매우 높은 처리량, 출발지 IP 보존, 연결(흐름) 단위 분산 | 제외. HTTP 경로 헬스 체크·5xx 지표·요청 단위 분산이 약하다. 고정 IP가 필요 없다 |
| GWLB (Gateway Load Balancer) | L3 | 방화벽·IDS 같은 보안 어플라이언스로 트래픽을 넘김 | 제외. 해당 장비가 없다 |
| CLB (Classic Load Balancer) | L4/L7 | 이전 세대. 기능이 적고 신규 사용 비권장 | 제외 |
| CloudFront (CDN) | 엣지 캐시 | 정적 파일 캐시, HTTPS 기본 제공 | 이번에는 제외(문서 2.4장). 부하가 반드시 ALB로 분산되는지 재야 해서 경로를 단순하게 둔다. 운영 단계에서 소개 페이지 캐시로 검토 |
| API Gateway | 관리형 API 진입점 | 요청 제한·인증 통합 | 제외. 정적 페이지 + SPA + API를 한 도메인으로 서비스하는 구조와 맞지 않는다 |

## 2. ALB를 고른 이유

1. 서비스가 HTTP 웹이다. nginx 앞에서 요청 단위로 고르게 나눠야 X-Web-Node 집계로 분산 비율(평균 ±20%, 8장)을 검증할 수 있다.
2. `/health` 경로로 HTTP 200을 확인하는 헬스 체크가 필요하다. nginx 프로세스가 살아 있어도 설정 오류로 응답하지 못하면 대상에서 빼야 한다.
3. 문서 8장의 측정 지표(`RequestCount`, `TargetResponseTime` p95, `HTTPCode_ELB_5XX_Count`, `HTTPCode_Target_5XX_Count`, `HealthyHostCount`)가 ALB 지표다.
4. 액세스 로그에 대상 인스턴스(`target:port`)와 처리 시간이 남아, 짧은 구간 분산을 Locust 기록과 대조할 수 있다.
5. 나중에 도메인과 ACM 인증서로 HTTPS 리스너를 붙이고, 가중치 대상 그룹으로 Blue/Green·카나리 배포를 할 수 있다(12장).

## 3. 비용 비교 (서울 리전, 2026-10-19 Pricing API 조회)

| 유형 | 시간당 고정 요금 | 사용량 요금 | 이 과제 기준 판단 |
|---|---|---|---|
| ALB | 0.0225달러 | LCU 시간당 0.008달러 | 동시 140명(초당 20~30건 추정)은 LCU 1 안팎이라 사용량 요금은 작다 |
| NLB | 0.0225달러 | LCU 시간당 0.006달러 | 고정 요금이 같아 비용 이점이 없다 |

- 계산식: 시간당 고정 요금 × 실행 시간 + LCU(신규 연결, 활성 연결, 처리 바이트, 규칙 평가 중 가장 큰 값) × 0.008달러.
- 외부 ALB 1개를 한 달(730시간) 켜 두면 고정 요금만 약 16.4달러다. 인터넷 연결형이라 AZ마다 공인 IPv4가 붙어 개당 시간당 0.005달러가 더해진다.

## 4. 구축 전 공통 네트워크 (외부 ALB 관련)

| 항목 | 값 |
|---|---|
| 리전 | 서울 `ap-northeast-2` |
| 가용 영역 | `ap-northeast-2a`(apne2-az1), `ap-northeast-2c`(apne2-az3) |
| VPC | `vet01-vpc` · `vpc-0810702125c92e6bc` · `10.0.0.0/16` |
| ALB 서브넷 | `vet01-public-a` `subnet-05ded1a5d43b4cd76` (10.0.0.0/24, 2a), `vet01-public-c` `subnet-055d33f36b5a3544a` (10.0.1.0/24, 2c) |
| 퍼블릭 라우팅 테이블 | `vet01-rt-public` · `rtb-0668ca32225e242d6` · `0.0.0.0/0 → igw-09169e5dfa842346d`, S3 프리픽스 목록 → `vpce-00392c049e7095320` |
| 인터넷 게이트웨이 | `vet01-igw` · `igw-09169e5dfa842346d` |
| NACL | 기본 NACL `acl-0cec1e02da387e656` · 양방향 전체 허용 (차단은 보안 그룹이 담당) |
| 태그 | `Name`만 적용. `Project`, `Owner` 공통 태그는 아직 없다. 다음 배포 때 `aws cloudformation deploy --tags Project=mp Owner=<담당자>`로 일괄 적용한다 |

ALB는 서로 다른 AZ의 서브넷이 최소 2개 필요하다. 그래서 퍼블릭 서브넷을 2a와 2c에 하나씩 두었다. 교차 영역 부하분산은 ALB 기본값(켜짐)이라, 한 AZ의 대상 수가 달라도 모든 대상에 고르게 나눈다.

## 5. 외부 ALB 설정값과 이유

### 5.1 로드 밸런서

| 설정 | 값 | 이유 |
|---|---|---|
| 이름 | `vet01-alb-ext` | 고객사 코드 + 역할. 고객사 50곳에 같은 규칙으로 붙인다 |
| 체계 | `internet-facing` | 보호자·방문자가 인터넷에서 접속 |
| IP 주소 유형 | IPv4 | 현재 IPv6 요구 없음 |
| 서브넷 | public-a, public-c | AZ 2개 요건 |
| 보안 그룹 | `vet01-sg-alb-ext` · `sg-059a7c7bfa53c539a` | 아래 5.4 |
| 유휴 제한 시간 | 60초 | 기본값. nginx `keepalive_timeout 75s`가 이보다 길어야 ALB가 끊기 전에 nginx가 먼저 끊는 일이 없다(부록 E.3) |
| 액세스 로그 | 켬 → `s3://vet01-alb-logs-<계정>/ext/` | 기본은 꺼짐(9장). 분산·지연을 대상 단위로 확인. 버킷은 30일 뒤 자동 삭제 |
| 교차 영역 부하분산 | 켬(ALB 기본) | AZ별 대상 수가 달라도 고르게 분산 |
| 삭제 보호 | 끔 | 테스트 후 스택 삭제로 한 번에 정리(10.9) |

### 5.2 리스너

| 설정 | 값 | 이유 |
|---|---|---|
| 프로토콜·포트 | HTTP 80 | ALB 기본 DNS 이름으로는 공인 인증서를 받을 수 없다(11장). 테스트 계정만 쓰는 조건에서 HTTP로 둔다 |
| 기본 동작 | `vet01-tg-web`으로 전달(forward) | 정적·SPA·API 요청 모두 WEB(nginx)이 받는다. 경로 분기는 nginx가 한다 |
| 운영 전환 계획 | 도메인 + ACM 인증서 → HTTPS 443 리스너, 80은 443으로 리디렉션 | 로그인 비밀번호 평문 전송 방지 |

### 5.3 대상 그룹 `vet01-tg-web`

| 설정 | 값 | 이유 |
|---|---|---|
| 대상 유형 | instance | ASG가 인스턴스를 자동 등록·해제 |
| 프로토콜·포트 | HTTP 80 | nginx `listen 80 default_server` |
| 헬스 체크 경로 | `/health` | nginx가 `return 200 'ok'`로 즉시 응답(액세스 로그 제외) |
| 간격 / 시간 제한 | 5초 / 4초 | 기본값(간격 30초, 정상 5회)은 장애 판정이 느리다(5장) |
| 정상 / 비정상 임계값 | 2회 / 2회 | 중지 후 약 10초(5초 × 2회) 안에 대상에서 빠진다(8장 장애 조치 기준) |
| 성공 코드 | 200 | |
| 등록 취소 지연 | 30초 | 기본 300초. 축소·교체 때 빨리 빠지게 하되 진행 중 요청은 마무리 |
| 고정 세션 | 끔 | 세션은 ElastiCache에 있으므로 고정할 필요가 없다. 켜면 분산이 치우친다 |
| 알고리즘 | 라운드 로빈 | 요청 단위로 고르게. 대상 그룹 기본값을 명시 |

### 5.4 보안 그룹 `vet01-sg-alb-ext`

| 방향 | 프로토콜·포트 | 출발지·대상 | 이유 |
|---|---|---|---|
| 인바운드 | TCP 80 | `AllowedCidr` 매개변수 (현재 `0.0.0.0/0`) | 다른 사람에게 보여 주기 위해 전체 공개 |
| 아웃바운드 | 전체 | 전체 (기본) | 대상 그룹으로 전달. WEB SG가 이 SG만 받으므로 실제 도달 범위는 WEB뿐이다 |

부하 테스트 기간에는 문서 5장대로 Locust 탄력적 IP와 팀원 공인 IP만 연다.

```
ALLOWED_CIDR=3.34.231.137/32 bash deploy/aws.sh infra
```

## 6. 요청 경로와 nginx 분기

| 경로 | nginx 처리 | WAS 경유 |
|---|---|---|
| `/health` | `return 200 'ok'` | 아니오 |
| `/`, `/about`, `/doctors`, `/services`, `/notices` | `/usr/share/nginx/vet/site`의 정적 HTML (`try_files $uri $uri.html $uri/`) | 아니오 |
| `/app/*` | `/usr/share/nginx/vet/app`의 SPA, 없는 경로는 `/app/index.html` | 아니오 |
| `/api/*` | 내부 ALB `:8080`으로 프록시 (04 문서) | 예 |

모든 응답에 `X-Web-Node: <WEB 인스턴스 이름>` 헤더가 붙는다. `/api` 응답에는 WAS가 `X-Served-By`를 더한다.

## 7. 모니터링·경보

| 대상 | 지표 | 조건 | 이유 |
|---|---|---|---|
| 경보 `vet01-target-5xx` | `HTTPCode_Target_5XX_Count` (외부 ALB) | 1분 합계 > 10 | 성공 기준: 5xx 1% 미만(8장) |
| 대시보드 `vet01-dashboard` | `RequestCount`, `HTTPCode_ELB_5XX_Count`, `HTTPCode_Target_5XX_Count`, `TargetResponseTime` p95, `HealthyHostCount` | 1분 간격 | TC-02~TC-06 증빙 캡처 |

CloudWatch ALB 지표는 60초 간격이고 헬스 체크 요청은 빠진다. 짧은 구간은 Locust 기록과 액세스 로그로 본다.

## 8. 검증 방법과 성공 기준

| 확인 | 명령·방법 | 기대 결과 |
|---|---|---|
| 헬스 | `curl -sI http://<외부 ALB DNS>/health` | 200, `X-Web-Node` 있음 |
| 정적 경로 | `curl -sI http://<외부 ALB DNS>/about` | 200, `X-Served-By` 없음 (WAS 미경유) |
| API 경로 | `curl -sI http://<외부 ALB DNS>/api/notices` | 200, `X-Web-Node` + `X-Served-By` |
| WEB 분산 | `/`를 20회 요청해 `X-Web-Node` 집계 (`bash deploy/aws.sh verify`) | WEB 2대에 고르게 |
| 장애 조치 (TC-06 ②) | WEB 1대의 nginx 중지 | 약 10초 안에 대상에서 빠지고 이후 오류 없음, ASG가 교체 |
| 분산 비율 (TC-02~05) | Locust `node_counts.csv` + 액세스 로그 | 인스턴스별 처리 건수가 평균의 ±20% 이내 |

외부 ALB의 DNS 이름은 배포 후 `bash deploy/aws.sh status`로 확인한다.

## 9. 확장 계획

| 단계 | 내용 |
|---|---|
| 운영 전환 | 도메인 + ACM 인증서로 HTTPS, AWS WAF 속도 기반 규칙으로 `/api/auth/login`만 제한(추가 비용) |
| 배포 전략 | 기본은 ASG 인스턴스 새로 고침. 위험한 변경은 대상 그룹 2개 + 리스너 가중치로 Blue/Green·카나리 |
| 고객사 확대 | 고객사별 독립 ALB(격리 강함, 비용 큼)와 공유 ALB의 호스트 기반 라우팅(비용 작음, 장애 영향 범위 큼) 중 비용 산정 후 결정(12장) |
| 정적 캐시 | 부하분산 검증이 끝나면 소개 페이지 앞에 CloudFront 검토 |
