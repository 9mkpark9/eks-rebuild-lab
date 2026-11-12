# ALB 및 Web Server Instance 설정

- 대상: 외부 ALB 뒤의 WEB 계층(nginx) 인스턴스
- 작성일: 2026-10-19
- 정의 위치: `cfn/web.yaml`(스택 `vet01-web`)의 `WebLaunchTemplate`·`WebAsg`·`WebScaling`, nginx 설정 `deploy/nginx.conf`
- ALB 자체의 선정과 설정은 02 문서에 있다.

> 이 환경의 데이터는 모두 임시(가짜) 데이터다. WEB 인스턴스는 빌드된 정적 파일만 서비스하며 개인정보를 저장하지 않는다.

---

### 구축 전 공통 네트워크

| 항목 | 공통 값 |
| --- | --- |
| 리전 | 서울 `ap-northeast-2` |
| 가용 영역 | `ap-northeast-2a`(apne2-az1), `ap-northeast-2c`(apne2-az3) |
| VPC | `vet01-vpc` · `vpc-0810702125c92e6bc` · `10.0.0.0/16` |
| 퍼블릭 라우팅 테이블 | `vet01-rt-public` · `rtb-0668ca32225e242d6` · `0.0.0.0/0 → igw-09169e5dfa842346d` (public 서브넷: 외부 ALB, NAT) |
| 사설 라우팅 테이블 | `vet01-rt-private` · `rtb-091b8e6f7fd97cb3d` · `0.0.0.0/0 → nat-0842c77cdb5029a0e` (web·app·db 서브넷) |
| S3 게이트웨이 엔드포인트 | `vpce-00392c049e7095320` · 두 라우팅 테이블에 연결 (배포 파일 다운로드가 NAT를 거치지 않음) |
| 1차 공통 NACL | 기본 NACL `acl-0cec1e02da387e656` · 양방향 전체 허용 (접근 통제는 보안 그룹 체인이 담당) |
| WEB 서브넷 | `vet01-web-a` `subnet-06f0ac5c62c263e29` (10.0.10.0/24, 2a), `vet01-web-c` `subnet-06e5401b62b4207d5` (10.0.11.0/24, 2c) · 공인 IP 자동 할당 끔 · 호스트 이름 유형 = 리소스 이름 |
| 공통 태그 | 현재 `Name`만 적용. `Project = mp`, `Owner = [담당자 이름]`은 다음 배포 때 `--tags`로 일괄 적용 예정 |

WEB 인스턴스는 사설 서브넷(web)에 둔다. 인터넷에서 직접 닿지 않고, 외부 ALB를 통해서만 요청을 받는다. 패키지 설치처럼 밖으로 나가는 트래픽은 NAT Gateway를, S3는 게이트웨이 엔드포인트를 쓴다.

---

### WEB Server Instance 선정

WEB 계층이 하는 일은 두 가지뿐이다.
1. 미리 빌드한 정적 파일 응답: 소개 페이지 HTML, SPA의 JS·CSS, SVG 이미지
2. `/api/*` 요청을 내부 ALB로 넘기는 리버스 프록시

CPU를 쓰는 연산(로그인 해시, 예약 판정)은 모두 WAS에서 일어난다. 그래서 WEB은 작은 범용 사양으로 충분하다고 보고 시작했다.

**1. 인스턴스 유형별 특성 비교**

| 유형 | 주요 특성 | WEB 계층 초기 검토 결과 |
| --- | --- | --- |
| 범용 버스터블 - T 계열 | 기준 CPU 성능을 제공하고, 크레딧을 써서 기준을 넘는 순간 부하를 처리 | 우선 후보. 평균 부하가 낮고 공지 직후에만 일시적으로 늘어나는 조건에 맞다 |
| 범용 - M 계열 | CPU와 메모리를 균형 있게 제공, 버스트 없이 일정한 성능 | 지속적인 처리와 메모리 여유가 필요할 때의 후보 |
| 컴퓨팅 최적화 - C 계열 | CPU 중심 자원 구성 | 실제 측정에서 CPU 병목이 확인될 때의 후보 |
| 메모리 최적화 - R 계열 | CPU 대비 큰 메모리 | 대용량 메모리 요구가 없어 우선순위를 낮춤 |
| 스토리지 최적화 - I, D 계열 등 | 높은 로컬 저장소 처리 성능 또는 대용량 저장 | 로컬 디스크 중심 처리가 없어 초기 후보에서 제외 |
| 가속 컴퓨팅, HPC 계열 | GPU 등 전용 가속기 또는 고성능 병렬 연산 | WEB 요구사항에 해당 자원이 필요 없어 제외 |

**2. 인스턴스 사양 후보 (1대 기준)**

| 후보 | CPU 아키텍처 | vCPU | 메모리 | 시간당 요금(서울) | 검토 목적 |
| --- | --- | --- | --- | --- | --- |
| t3.micro | x86_64 | 2 | 1 GiB | 0.013달러 | 최소 비용 비교 (기준 CPU 10%) |
| t3.small | x86_64 | 2 | 2 GiB | 0.026달러 | 초기 기준 환경 (기준 CPU 20%) |
| t3.medium | x86_64 | 2 | 4 GiB | 0.052달러 | 메모리 부족 시 비교 |
| t4g.small | Arm64 | 2 | 2 GiB | 0.0208달러 | Arm 호환성 확인 후 비용·성능 비교 |
| m7i.large | x86_64 | 2 | 8 GiB | 0.1239달러 | 지속 CPU 부하와 메모리 여유가 필요한 경우 비교 |
| c7i.large | x86_64 | 2 | 4 GiB | 0.1008달러 | 지속 CPU 처리 중심 비교 |

요금은 AWS Pricing API로 2026-10-19에 조회한 서울 리전 Linux 온디맨드 값이다.

**3. 비용 효율성 검토**

| 후보 | 검토 사항 |
| --- | --- |
| T3 | 낮은 평균 CPU 사용 조건에서 효율적이다. 다만 기준(t3.small 20%)을 넘는 상태가 길어지면 unlimited 모드의 추가 크레딧 요금(Linux vCPU 시간당 0.05달러)이 붙으므로, 지속 부하 시 이 비용까지 포함해 비교한다 |
| T4g | 같은 조건에서 T3보다 약 20% 싸다(0.0208 대 0.026달러). nginx·정적 파일은 아키텍처와 무관하지만, Arm용 AMI·CloudWatch 에이전트 등 이미지와 패키지 준비 비용을 고려한다 |
| M7i | 시간당 t3.small의 약 4.8배다. 더 큰 자원을 실제로 쓰는지, 지속 부하에서 T 계열보다 유리한지 비교해야 정당화된다 |
| C7i | 시간당 t3.small의 약 3.9배다. CPU 병목 개선 효과가 추가 비용을 정당화하는지 확인한다 |

비용 비교 계산식은 다음과 같다.

- 인스턴스 시간당 요금 × 실행 시간 × 서버 대수
- T 계열의 추가 CPU 크레딧 비용 (unlimited 모드에서 24시간 평균이 기준선을 넘을 때)
- 시험 조건에서 발생하는 데이터 전송 비용 (NAT 처리 GB당 0.059달러. S3는 게이트웨이 엔드포인트로 무료)

월(730시간) 기준 2대 비용 비교:

| 후보 | 2대 × 730시간 | t3.small 대비 |
| --- | --- | --- |
| t3.micro | 약 19.0달러 | -50% |
| t3.small | 약 38.0달러 | 기준 |
| t4g.small | 약 30.4달러 | -20% |
| t3.medium | 약 75.9달러 | +100% |
| c7i.large | 약 147.2달러 | +288% |
| m7i.large | 약 180.9달러 | +377% |

**4. 초기 선정**

선정 결과: **t3.small (인스턴스당 2 vCPU · 2 GiB), 최소 2대 · 최대 3대**

선정 이유
- 처리 방식이 정적 응답 + 리버스 프록시로 확정되었다. nginx는 이 일을 아주 적은 CPU로 처리한다. 동시 140명은 초당 20~30건 수준으로 추정되어 2 vCPU의 처리량에 비해 매우 작다.
- t3.micro(1 GiB)도 nginx 자체에는 충분하다. 하지만 dnf 패키지 설치, CloudWatch 에이전트, OS 캐시를 함께 고려하면 여유가 작고 기준 CPU가 10%로 낮다. 그래서 2 GiB·기준 20%인 t3.small을 기준으로 두었다.
- x86_64를 초기 기준으로 두어 WAS(t3.medium)와 같은 AMI 매개변수(`al2023-ami-kernel-default-x86_64`)를 쓴다. Arm 후보(t4g.small)는 TC-02 결과를 본 뒤 호환성·성능을 비교한다.
- 기본 성능과 순간 부하 대응을 측정해 T 계열이 맞는지 판단한다. T3는 기본이 unlimited 모드라 시험 중 CPU가 묶이지 않아 측정이 유효하다.
- 최소 2대는 스파이크의 첫 몇 분과 AZ 하나의 장애를 함께 버티기 위한 값이다. 2a·2c에 한 대씩 둔다. 대상 추적 확장은 1분 단위 지표 → 경보 → 기동 → 헬스 체크를 거쳐야 해서, 30초 만에 오는 급증에는 늦기 때문이다.
- 최대 3대는 예상보다 큰 부하에 대한 보험이다.
- 부족한 자원이 확인되면 원인에 맞춰 후보를 바꾼다(아래 5번).

**5. 확장 가능성 검토 및 최종 사양 검증 계획**

기술 스택과 처리 방식이 확정되었으므로, 아래 항목을 측정해 최종 사양을 정한다. 근거 문서의 부하 테스트(TC-02~TC-06)를 그대로 쓴다.

| 검증 항목 | 수집 위치 | 판단 기준 | 기준을 넘으면 |
| --- | --- | --- | --- |
| 평균 CPU | ASG 평균 CPU (1분 세부 모니터링) | TC-04(140명 20분) 동안 평균 70% 미만 | CPU 병목이면 c7i.large 비교, 또는 최대 대수 상향 |
| CPU 크레딧 | `CPUCreditBalance`, `CPUSurplusCreditsCharged` | 시험 후 잔액이 계속 줄지 않음, 추가 요금 미미 | 지속 부하로 판단 → m7i.large 비교 |
| 메모리 | CloudWatch 에이전트 `mem_used_percent` | TC-04 동안 계속 오르는 추세 없음, 80% 미만 | t3.medium 비교 |
| 응답 시간 | Locust p95, `TargetResponseTime` p95 | 정적 페이지 p95 300ms 미만(TC-02 기준선 후 확정), TC-03·04 모든 API p95 1초 미만 | WEB 지연이면 사양 상향, 아니면 WAS 쪽 조사 |
| 분산 | Locust `X-Web-Node` 집계, ALB 액세스 로그 | 인스턴스별 처리 건수가 평균의 ±20% 이내 | 고정 세션·대상 상태 확인 |
| 장애 조치 | `UnHealthyHostCount`, Locust 오류 시각 (TC-06 ②) | 중지 후 약 10초 안에 대상에서 빠지고 이후 오류 없음 | 헬스 체크 값 재검토 |
| 확장 동작 | ASG 활동 기록 (TC-08) | CPU 50% 초과 시 확장, 새 인스턴스가 요청 수신 | 웜업·유예 시간 조정 |
| Arm 비교 | t4g.small로 같은 시험 반복 | 위 기준을 모두 만족하면 비용 20% 절감안 채택 | — |

결과는 아키텍처 선정 문서(ADR, 01 문서)에 「WEB 최종 사양」으로 기록한다. 140명에서 CPU가 50%를 넘지 않아 확장이 일어나지 않는 것도 정상 결과다. 그 경우 다음 고객사부터는 같은 사양 또는 t4g.small로 시작한다.

---

### WEB 서버 구성

**시작 템플릿 `vet01-lt-web`**

| 설정 | 값 | 이유 |
| --- | --- | --- |
| AMI | SSM 공개 파라미터 `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64` | 항상 최신 Amazon Linux 2023. SSM Agent 기본 포함 |
| 인스턴스 유형 | t3.small | 위 선정 결과 |
| IAM 인스턴스 프로필 | `vet01-profile-web` | `AmazonSSMManagedInstanceCore`, `CloudWatchAgentServerPolicy`, 배포 버킷 `web/*` 읽기만 |
| 보안 그룹 | `vet01-sg-web` · `sg-04d8e6e58ef9f1208` | 인바운드 TCP 80, 출발지 = `vet01-sg-alb-ext`만 |
| 세부 모니터링 | 켬 (1분) | 대상 추적 정책과 시험 측정 정밀도 |
| 메타데이터 | IMDSv2 필수, 홉 제한 2 | 자격 증명 탈취 방지 |
| 키 페어 | 없음 | SSH 22번을 열지 않고 Session Manager로만 접속 |

**사용자 데이터 (부팅 때 자동 설치, 부록 E.2)**

1. `dnf install -y nginx amazon-cloudwatch-agent`
2. S3에서 `web/vet-web-1.0.0.tar.gz`를 받아 `/usr/share/nginx/vet`에 푼다. `site/`(소개 HTML)와 `app/`(예약·직원 SPA)가 들어 있다.
3. S3에서 `web/nginx.conf`를 받아 `/etc/nginx/nginx.conf`를 통째로 바꾼다. AL2023 기본 설정의 80번 기본 서버와 겹치지 않게 하기 위해서다.
4. `__INTERNAL_ALB_DNS__`를 실제 내부 ALB 이름(`internal-vet01-alb-int-518182130.ap-northeast-2.elb.amazonaws.com`)으로 치환하고 `nginx -t`로 문법을 검사한다.
5. CloudWatch 에이전트로 메모리(`mem_used_percent`)와 nginx access·error 로그를 보낸다(`/vet01/web-access`, `/vet01/web-error`).
6. `systemctl enable --now nginx`

인스턴스에 직접 접속해 파일을 고치지 않는다. 그래서 ASG가 새로 띄운 인스턴스도 항상 같은 상태가 된다.

**nginx 핵심 설정과 이유**

| 설정 | 값 | 이유 |
| --- | --- | --- |
| `keepalive_timeout` | 75s | ALB 유휴 제한 시간(60초)보다 길게. ALB가 쓰려던 연결을 nginx가 먼저 닫아 502가 나는 것을 막는다 |
| `add_header X-Web-Node $hostname always` | 인스턴스 ID | 분산 확인. 호스트 이름 유형이 리소스 이름이라 사설 IP가 아닌 인스턴스 ID가 나온다 |
| `resolver 169.254.169.253 valid=10s` + `set $was_alb ...` | Amazon DNS, 10초 | 내부 ALB의 IP는 바뀐다. 변수로 프록시해야 nginx가 시작 때 한 번만 조회하지 않고 따라간다 |
| `location = /health` | `return 200 'ok'`, 로그 끔 | ALB 헬스 체크. WAS·DB 상태와 무관하게 nginx 자체만 판정 |
| `location /api/` | `proxy_pass $was_alb`, HTTP/1.1, 연결 5초, 읽기 30초 | 내부 ALB로 넘김. 원래 Host, X-Forwarded-For 전달 |
| `location /app/` | `try_files $uri /app/index.html` | SPA 경로 새로 고침 대응 |
| `location /` | `try_files $uri $uri.html $uri/ =404` | `/about` → `about.html` |
| `server_tokens off` | | 버전 노출 방지 |

**Auto Scaling 그룹 `vet01-asg-web`**

| 설정 | 값 | 이유 |
| --- | --- | --- |
| 서브넷 | web-a(2a), web-c(2c) | AZ마다 한 대씩 분산 |
| 최소 / 원하는 / 최대 | 2 / 2 / 3 | 위 4번 |
| 대상 그룹 | `vet01-tg-web` | 외부 ALB에 자동 등록 |
| 헬스 체크 유형 | ELB | nginx가 응답하지 않으면 ASG가 교체 |
| 헬스 체크 유예 | 120초 | 부팅 + nginx 설치 시간 |
| 조정 정책 | 대상 추적, ASG 평균 CPU 50% | 확장은 예상보다 큰 부하에 대한 보험 |
| 지표 수집 | 1분 | 대시보드·증빙 |

---

### ALB 연결

| 항목 | 값 |
| --- | --- |
| 외부 ALB | `vet01-alb-ext` · `http://vet01-alb-ext-72802186.ap-northeast-2.elb.amazonaws.com` (2026-10-19 삭제) |
| 리스너 | HTTP 80 → `vet01-tg-web` |
| 대상 그룹 헬스 체크 | `/health`, 간격 5초, 시간 제한 4초, 정상 2회, 비정상 2회, 성공 코드 200 |
| 고정 세션 | 끔 (세션은 ElastiCache) |
| 등록 취소 지연 | 30초 |

---

### 구축 결과 (2026-10-19 16시 기준)

| 인스턴스 | 유형 | 가용 영역 | 대상 상태 |
| --- | --- | --- | --- |
| `i-0f7d9ccda02d09c38` | t3.small | ap-northeast-2a | healthy |
| `i-07f6d35dd87225ee2` | t3.small | ap-northeast-2c | healthy |

| 확인 | 결과 |
| --- | --- |
| `GET /health` | 200, `X-Web-Node: i-0f7d9ccda02d09c38...` |
| `GET /about` | 200, 정적 HTML, `X-Served-By` 없음 (WAS를 거치지 않음) |
| `GET /api/notices` | 200, `X-Web-Node: i-07f6d35dd87225ee2...` + `X-Served-By`(WAS) |
| 스택 생성 직후 자동 확인 | 502. 인스턴스가 아직 부팅 중이었다. 몇 분 뒤 모든 대상이 healthy가 되고 정상 응답했다 |

남은 검증: Locust로 TC-02(40명 15분)와 TC-03~05 연속 실행을 돌려 위 5번 표의 기준으로 최종 사양을 확정한다.
