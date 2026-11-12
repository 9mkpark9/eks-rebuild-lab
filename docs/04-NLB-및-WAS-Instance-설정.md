# NLB 및 WAS Instance 설정

- 대상: WEB → WAS 사이의 내부 로드 밸런서(NLB 검토 → 내부 ALB 채택)와 WAS 계층(Spring Boot) 인스턴스
- 작성일: 2026-10-19
- 정의 위치: `cfn/was.yaml`(스택 `vet01-was`)의 `InternalAlb`·`WasTg`·`WasLaunchTemplate`·`WasAsg`·`WasScaling`, WAS 코드 `was/`
- 부하 생성기(Locust) 인스턴스 선정도 이 문서 끝에 함께 적었다.

> 이 환경의 데이터는 모두 임시(가짜) 데이터다. 테스트 계정(owner001~300, admin1·2, vet1~3)과 가상 병원 정보만 있다.

---

## A. 내부 로드 밸런서 선정: NLB 검토 결과

### A-1. WEB → WAS 구간의 요구사항

| 요구 | 근거 |
| --- | --- |
| HTTP 8080, 경로 `/health`로 앱 상태 확인 | 5장 헬스 체크 설정 |
| 요청 단위로 고르게 분산, WAS별 처리 건수가 평균의 ±20% 이내 | 8장 성공 기준 |
| WAS 응답 시간·5xx를 대상 그룹 단위로 측정 | 8장 지표 (`TargetResponseTime`, `HTTPCode_Target_5XX_Count`) |
| WAS 1대 중지 시 약 10초 안에 대상에서 제외 | 8장 장애 조치 기준 |
| ASG와 연동해 인스턴스 자동 등록·해제 | 5장 |
| 인터넷에서 닿지 않음 (사설) | 보안 그룹 체인 |

### A-2. NLB와 ALB 비교 (내부용)

| 항목 | NLB (Network Load Balancer) | ALB (Application Load Balancer) |
| --- | --- | --- |
| 동작 계층 | L4 (TCP/UDP/TLS) | L7 (HTTP/HTTPS) |
| 분산 단위 | TCP 연결(흐름 해시). 한 연결로 여러 요청이 가면 같은 대상에 붙는다 | HTTP 요청 단위 라운드 로빈 |
| 헬스 체크 | TCP, HTTP, HTTPS 모두 가능 | HTTP, HTTPS (경로·성공 코드 지정) |
| HTTP 지표 | 없음 (흐름·바이트·TCP 리셋 지표) | `TargetResponseTime`, `HTTPCode_Target_5XX_Count`, `RequestCount` |
| 액세스 로그 | TLS 리스너에서만 | HTTP 요청마다 대상·처리 시간 기록 |
| 교차 영역 부하분산 | 기본 꺼짐 (켜면 AZ 간 전송 요금) | 항상 켜짐 |
| 고정 IP | AZ마다 고정 IP·탄력적 IP 가능 | 없음 (DNS 이름, IP는 바뀜) |
| PrivateLink(VPC 엔드포인트 서비스) | 가능 | 불가 (NLB를 앞에 둬야 함) |
| 지연·처리량 | 매우 낮은 지연, 초당 수백만 요청 | 충분히 낮음, 이 규모에 과분 |
| 요금(서울) | 시간당 0.0225달러 + LCU 시간당 0.006달러 | 시간당 0.0225달러 + LCU 시간당 0.008달러 |

### A-3. 결정: 내부 ALB 채택, NLB 미채택

이유
1. **분산 검증이 요청 단위여야 한다.** 지금 nginx 설정은 업스트림 연결을 재사용하지 않아 요청마다 새 TCP 연결을 연다. 그래서 NLB여도 지금은 고르게 퍼진다. 하지만 성능을 위해 nginx 업스트림 keepalive를 켜는 순간, NLB는 연결이 붙은 WAS로만 요청을 보낸다. 그러면 WAS별 처리 건수(±20% 기준)가 치우친다. ALB는 설정과 무관하게 요청 단위로 나눈다.
2. **8장의 WAS 지표가 ALB 지표다.** 내부 ALB의 `TargetResponseTime` p95와 대상 그룹 5xx로 WAS 지연과 오류를 WEB 지연과 분리해 본다. NLB에는 HTTP 수준 지표가 없다.
3. **교차 영역 분산.** WAS가 AZ마다 1대씩인 구성에서 NLB는 기본으로 같은 AZ의 대상에게만 보낸다. 켜면 AZ 간 전송 요금이 붙는다. ALB는 항상 두 AZ의 대상에 고르게 보낸다.
4. **고정 IP가 필요 없다.** nginx는 내부 ALB의 DNS 이름을 10초마다 다시 조회한다(`resolver ... valid=10s`). 고정 IP가 필요한 경우가 아니다.
5. **비용 차이가 없다.** 시간당 고정 요금이 같고, LCU 차이(0.002달러)는 이 규모에서 무시할 수준이다.
6. 근거 문서(5장)와 AWS 3-Tier 워크숍이 내부 ALB를 쓴다.

NLB를 다시 검토할 조건
- WAS 앞에 HTTP가 아닌 프로토콜(TCP 소켓, gRPC 직접 노출 등)이 필요할 때
- 다른 고객사 VPC에 PrivateLink로 API를 제공할 때 (엔드포인트 서비스는 NLB가 필요)
- 방화벽 허용 목록 때문에 고정 IP가 필요할 때
- 초당 수만 건 이상에서 L7 처리 지연이 문제가 될 때

### A-4. 내부 ALB 설정값과 이유

| 설정 | 값 | 이유 |
| --- | --- | --- |
| 이름 | `vet01-alb-int` | |
| DNS | `internal-vet01-alb-int-518182130.ap-northeast-2.elb.amazonaws.com` | nginx 사용자 데이터가 치환해 넣는다 |
| 체계 | `internal` | 인터넷에서 닿지 않음 |
| 서브넷 | `vet01-app-a` `subnet-03ebd4f17001ff5f3` (10.0.20.0/24, 2a), `vet01-app-c` `subnet-052165fdd8339bff8` (10.0.21.0/24, 2c) | AZ 2개 요건, WAS와 같은 계층 |
| 보안 그룹 | `vet01-sg-alb-int` · `sg-0ad572cb9251a16d0` · 인바운드 TCP 8080, 출발지 `vet01-sg-web`만 | 보안 그룹 체인 |
| 리스너 | HTTP 8080 → `vet01-tg-was` | 내부 구간은 VPC 안이라 HTTP |
| 액세스 로그 | `s3://vet01-alb-logs-<계정>/int/` | WAS별 처리 건수 대조 |

대상 그룹 `vet01-tg-was`

| 설정 | 값 | 이유 |
| --- | --- | --- |
| 프로토콜·포트 | HTTP 8080 | Spring Boot `server.port` |
| 헬스 체크 | `/health`, 간격 5초, 시간 제한 4초, 정상 2회, 비정상 2회, 200 | 기본값(30초, 정상 5회)은 장애 판정이 느리다 |
| `/health`가 DB를 확인하지 않는 이유 | 프로세스 상태만 | DB 장애 때 모든 WAS가 비정상이 되면 ASG가 멀쩡한 인스턴스까지 교체하고, ALB는 fail open이 된다(부록 B) |
| 등록 취소 지연 | 30초 | Spring Boot `server.shutdown: graceful`과 함께 진행 중 요청 마무리 |
| 고정 세션 | 끔 | 세션은 ElastiCache. 어느 WAS로 가도 같은 결과 |
| 알고리즘 | 라운드 로빈 | |

---

## B. WAS Server Instance 선정

WAS 계층이 하는 일
- 예약 판정(조건부 UPDATE, 유니크 제약, 트랜잭션 롤백, 교착 상태 재시도)
- 로그인 비밀번호 BCrypt 검증(강도 10). 의도적으로 CPU를 많이 쓰는 연산이다.
- 세션 읽기·쓰기(ElastiCache), DB 연결 풀(HikariCP 10개)
- 실행 환경: Java 21 JVM (힙 `-Xms1g -Xmx2g`)

### 1. 인스턴스 유형별 특성 비교

| 유형 | 주요 특성 | WAS 계층 검토 결과 |
| --- | --- | --- |
| 범용 버스터블 - T 계열 | 기준 CPU + 크레딧 버스트, unlimited 모드에서 묶이지 않음 | 우선 후보. 평소 40명은 낮은 부하, 공지 직후 로그인이 몰릴 때만 CPU가 오른다 |
| 범용 - M 계열 | 버스트 없이 일정한 CPU, 넉넉한 메모리 | 140명 지속 부하에서 크레딧 비용이 커질 때의 후보 |
| 컴퓨팅 최적화 - C 계열 | CPU 중심 | 로그인 해시가 병목으로 확인될 때의 후보 |
| 메모리 최적화 - R 계열 | CPU 대비 큰 메모리 | JVM 힙 2 GiB면 충분해 제외 |
| 스토리지 최적화 | 로컬 디스크 성능 | 상태는 RDS·ElastiCache에만 있어 제외 |
| 가속 컴퓨팅 | GPU 등 | 해당 없음 |

### 2. 인스턴스 사양 후보 (1대 기준)

| 후보 | CPU 아키텍처 | vCPU | 메모리 | 시간당 요금(서울) | 검토 목적 |
| --- | --- | --- | --- | --- | --- |
| t3.small | x86_64 | 2 | 2 GiB | 0.026달러 | 최소 비용 비교. 힙 2 GiB를 둘 수 없어 힙을 줄여야 함 |
| t3.medium | x86_64 | 2 | 4 GiB | 0.052달러 | 초기 기준 환경 (문서 5장 선정값) |
| t4g.medium | Arm64 | 2 | 4 GiB | 0.0416달러 | Corretto 21 Arm 빌드로 같은 jar 실행. 비용 20% 절감 비교 |
| c7i.large | x86_64 | 2 | 4 GiB | 0.1008달러 | 로그인 해시 CPU 병목 시 비교 |
| m7i.large | x86_64 | 2 | 8 GiB | 0.1239달러 | 지속 부하·메모리 여유 비교 |

### 3. 비용 효율성 검토

| 후보 | 2대 × 730시간 | 최대 4대 × 730시간 | 검토 사항 |
| --- | --- | --- | --- |
| t3.small | 약 38.0달러 | 약 75.9달러 | 메모리 2 GiB에서 힙 2 GiB + 메타스페이스 + OS가 들어가지 않는다. 힙을 1 GiB로 줄이면 GC 부담이 늘어난다 |
| t3.medium | 약 75.9달러 | 약 151.8달러 | 기준. 24시간 평균 CPU가 기준선(20%)을 넘으면 vCPU 시간당 0.05달러의 추가 크레딧 요금을 포함해 비교한다 |
| t4g.medium | 약 60.7달러 | 약 121.5달러 | jar는 그대로 실행된다. AMI와 Corretto 패키지만 Arm용으로 바꾸면 된다 |
| c7i.large | 약 147.2달러 | 약 294.3달러 | t3.medium의 약 1.9배. 해시 병목 개선이 이를 정당화하는지 확인 |
| m7i.large | 약 180.9달러 | 약 361.8달러 | t3.medium의 약 2.4배. 8 GiB를 실제로 쓰지 않으면 낭비 |

### 4. 초기 선정

선정 결과: **t3.medium (인스턴스당 2 vCPU · 4 GiB), 최소 2대 · 최대 4대**

선정 이유
- **메모리:** JVM 힙 최대 2 GiB에 메타스페이스, 스레드 스택(Tomcat 기본 최대 200), 코드 캐시, OS, CloudWatch 에이전트를 더하면 3 GiB 안팎이다. 4 GiB가 여유 있게 담는 가장 작은 범용 사양이다.
- **CPU:** 스파이크 때 몰리는 로그인 해시가 2 vCPU를 나눠 쓴다. 서블릿 방식이라 해시 계산이 다른 요청을 막지 않는다. T3 unlimited 모드라 시험 중 CPU가 묶이지 않는다.
- **최소 2대:** JVM은 기동에 수십 초가 걸린다. 30초 만에 오는 스파이크에는 자동 확장이 늦다. 그래서 스파이크의 첫 몇 분과 AZ 하나의 장애를 기존 2대(2a·2c 각 1대)로 버틴다.
- **최대 4대:** DB 연결 수 계산에서 나온 상한이다. WAS 4대 × 풀 10 = 40, 관리·모니터링 여유 5를 더해 최대 45. 최대 사용량이 한도의 80% 이하라는 조건(45 ÷ 0.8 ≈ 57)을 db.t3.small의 실측 `max_connections` 144가 넉넉히 만족한다.
- **x86_64:** WEB과 같은 AMI 매개변수를 쓴다. t4g.medium은 TC-02 이후 비교 후보다.
- **헬스 체크 유예 300초:** 문서는 120초다. 첫 부팅에 JDK 설치(dnf)와 jar 다운로드가 들어가 여유를 두었다. JDK를 구운 AMI를 쓰면 120초로 줄인다.

### 5. 확장 가능성 검토 및 최종 사양 검증 계획

| 검증 항목 | 수집 위치 | 판단 기준 | 기준을 넘으면 |
| --- | --- | --- | --- |
| 로그인 응답 시간 | Locust `/api/auth/login` p95 (TC-01에서 1건 처리 시간, TC-03에서 p95) | TC-03·04 모든 API p95 1초 미만 | 해시 병목이면 c7i.large 비교 또는 최소 대수 상향 |
| 예약 API 응답 시간 | Locust `/api/reservations` p95 | TC-02 500ms 미만(기준선 후 확정) | DB 쿼리·잠금 대기 조사 |
| 평균 CPU | ASG 평균 CPU | TC-04 동안 평균 70% 미만 | 최소 대수 3으로, 또는 사양 상향 |
| CPU 크레딧 | `CPUSurplusCreditsCharged` | 추가 요금 미미 | 지속 부하 → m7i.large 비교 |
| 메모리·GC | `mem_used_percent`, 앱 로그 | TC-04 20분 동안 계속 오르는 추세 없음 | 힙·누수 조사, 필요 시 사양 상향 |
| DB 연결 | 연결 획득 실패 로그(풀 대기 3초 초과 시 즉시 오류), RDS `DatabaseConnections` | 획득 실패 0건, 최대치가 한도의 80% 이하 | 풀 크기·최대 대수 재계산 |
| WAS 분산 | Locust `X-Served-By` 집계, 내부 ALB 액세스 로그, DB `served_by` 집계 | 평균의 ±20% 이내 | 고정 세션·대상 상태 확인 |
| 장애 조치 (TC-06 ①) | WAS 1대 앱 중지 → 재시작 | 약 10초 안에 대상 제외, 이후 오류 없음, ASG 교체 | 헬스 체크·유예 재검토 |
| DB 장애 조치 (TC-06 ③) | RDS 강제 장애 조치 | 전환 후 WAS 재시작 없이 2분 안에 오류 0 | JVM DNS TTL(60초) 확인 |
| 확장 (TC-08) | ASG 활동 기록 | CPU 50% 초과 시 확장, 새 인스턴스가 요청 수신 | 유예·웜업 조정 |
| Arm 비교 | t4g.medium으로 반복 | 위 기준 모두 만족 | 비용 20% 절감안 채택 |

TC-03 결과(140명에서 WAS CPU와 로그인 p95)가 최소 대수를 정하는 근거다. 여유가 있으면 다음 고객사부터 t3.small(힙 축소) 또는 t4g.medium으로 낮춘다(문서 5장).

---

## C. WAS 서버 구성

### 시작 템플릿 `vet01-lt-was`

| 설정 | 값 | 이유 |
| --- | --- | --- |
| AMI | `al2023-ami-kernel-default-x86_64` (SSM 공개 파라미터) | 최신 Amazon Linux 2023, SSM Agent 포함 |
| 인스턴스 유형 | t3.medium | 위 선정 결과 |
| IAM 인스턴스 프로필 | `vet01-profile-was` | SSM, CloudWatch 에이전트, `was/*` 읽기, 비밀 `vet01/db/app`·`vet01/redis/auth` 읽기만 (부록 E.4) |
| 보안 그룹 | `vet01-sg-was` · `sg-01510d7433cdfbcdd` · 인바운드 TCP 8080, 출발지 `vet01-sg-alb-int`만 | |
| 세부 모니터링 | 켬 | |
| 메타데이터 | IMDSv2 필수 | |

### 사용자 데이터 (부록 E.1)

1. `dnf install -y java-21-amazon-corretto-headless amazon-cloudwatch-agent jq`
2. 시스템 사용자 `vet`를 만들고, S3에서 `was/vet-api-1.0.0.jar`를 `/opt/vet/vet-api.jar`로 받는다.
3. 비밀이 아닌 설정만 `/opt/vet/app.conf`에 쓴다: DB 접속 URL(`jdbc:mysql://vet01-db...:3306/vet?connectionTimeZone=LOCAL`), Redis 주소, 비밀 ID.
4. `/opt/vet/start.sh`가 시작할 때마다 Secrets Manager에서 DB 계정과 AUTH 토큰을 읽는다. 이 값은 프로세스 환경 변수로만 넘기고 디스크에 남기지 않는다.
5. `exec java -Xms1g -Xmx2g -Duser.timezone=Asia/Seoul -jar /opt/vet/vet-api.jar`
6. systemd 서비스 `vet-api` (비정상 종료 시 5초 뒤 재시작)
7. CloudWatch 에이전트가 메모리와 앱 로그(`/vet01/was`)를 보낸다.

사용자 데이터는 콘솔·CLI로 다시 조회되므로 비밀번호를 넣지 않는다.

### 애플리케이션 핵심 설정 (`was/src/main/resources/application.yml`)

| 설정 | 값 | 이유 |
| --- | --- | --- |
| `spring.datasource.hikari.maximum-pool-size` | 10 | 8장 계산: 140명·RPS 30·DB 사용 절반·20ms → 평균 0.3개. 풀을 키워도 처리량은 늘지 않고 DB 부담만 커진다 |
| `hikari.connection-timeout` | 3000ms | 기본 30초. 연결 부족을 30초 지연이 아니라 바로 오류로 드러낸다 |
| `spring.data.redis.ssl.enabled` | true | ElastiCache 전송 중 암호화(AUTH 토큰 사용 조건) |
| 세션 만료 | 30분, 요청마다 연장 | 6장 |
| 세션 쿠키 | `SESSION`, HttpOnly, SameSite=Lax | |
| 시간대 | JVM 기본 Asia/Seoul | EC2 기본은 UTC. 슬롯 시각은 병원 현지 시각 |
| JVM DNS TTL | 60초 (`Security.setProperty`) | RDS 장애 조치 후 바뀐 주소를 따라간다(11장) |
| 응답 헤더 | `X-Served-By: <인스턴스 이름>` | 분산 확인 |

### Auto Scaling 그룹 `vet01-asg-was`

| 설정 | 값 | 이유 |
| --- | --- | --- |
| 서브넷 | app-a(2a), app-c(2c) | AZ마다 한 대 |
| 최소 / 원하는 / 최대 | 2 / 2 / 4 | 위 4번 |
| 대상 그룹 | `vet01-tg-was` | 내부 ALB에 자동 등록 |
| 헬스 체크 유형 / 유예 | ELB / 300초 | |
| 조정 정책 | 대상 추적, 평균 CPU 50% | |
| 새 버전 배포 | 인스턴스 새로 고침 (최소 정상 100%, 최대 200%, 자동 롤백) | 배포 중에도 서비스가 멈추지 않는다. 단, 4대인 상태에서 배포하면 8대 × 10 = 80연결이 되므로 부하가 큰 시간에는 배포하지 않는다(10.7) |

---

## D. 구축 결과 (2026-10-19 16시 기준)

| 인스턴스 | 유형 | 가용 영역 | 대상 상태 |
| --- | --- | --- | --- |
| `i-0a826a3dfe0d2e212` | t3.medium | ap-northeast-2a | healthy |
| `i-0746150c967f6380c` | t3.medium | ap-northeast-2c | healthy |

| 확인 (외부 ALB 경유) | 결과 |
| --- | --- |
| `GET /api/notices` | 200, `X-Served-By: i-0a826a3dfe0d2e212...` — RDS에서 공지 5건 조회 |
| `GET /api/slots?date=2026-10-20&type=GENERAL` | 200, `X-Served-By: i-0746150c967f6380c...` — 두 번의 요청이 서로 다른 WAS로 감 |
| 로그인 후 예약·승인 흐름 | 공개 서버라 테스트 계정 로그인은 담당자가 직접 확인한다. 같은 코드는 로컬 기동 시험(라우팅·오류 응답)을 통과했다 |

---

## E. 부하 생성기(Locust) 인스턴스 선정

| 후보 | vCPU · 메모리 | 시간당 | 검토 |
| --- | --- | --- | --- |
| t3.large 등 T 계열 | 버스트형 | — | 크레딧 상태에 따라 부하 생성 속도가 흔들릴 수 있어 제외 |
| c7i.large | 2 · 4 GiB | 0.1008달러 | 가능하지만 워커 여러 개와 결과 집계에 메모리 여유가 작다 |
| **m7i.large** | 2 · 8 GiB | 0.1239달러 | **채택.** 버스트형이 아니어서 CPU 크레딧과 무관하게 일정한 부하를 낸다. 마스터 1 + 워커 2(vCPU 수만큼) |

| 설정 | 값 | 이유 |
| --- | --- | --- |
| 위치 | 별도 VPC `10.20.0.0/16`, 퍼블릭 서브넷 `subnet-03e5600a29f1cbbb7` (2a) | 실제 사용자와 같은 경로(외부 ALB 공개 주소)로만 요청. AWS 테스트 정책상 같은 리전 |
| 인스턴스 | `i-0d3cd2698991edad2`, 탄력적 IP `3.34.231.137` | 외부 ALB 보안 그룹을 좁힐 때 이 IP/32를 넣는다 |
| 보안 그룹 | `vet01-sg-locust` · 인바운드 없음 | Session Manager로만 접속 |
| 스크립트 | `/opt/loadtest/locustfile.py` (부록 A) | 프로필 tc02 · spike(TC-03~05) · tc06 · tc08 |
