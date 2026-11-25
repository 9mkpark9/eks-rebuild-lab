# [실습] lab01: 워크로드 직접 실행

| 속성 | 값 |
|---|---|
| 상위 항목 | ① 워크로드 테스트 |
| 선행 작업 | 없음 |
| 후속 작업 | [lab02: 이미지와 compose](lab02-이미지와-compose.md) |

컨테이너 없이 소스를 빌드해 서비스 3개를 jar 로 직접 실행한다. MySQL 과 Redis 만 공식 이미지로 띄우고, 빈 MySQL 에 스키마·시드·서비스 계정을 넣는다. 서비스의 설정이 모두 환경 변수로 들어가는 것을 확인하고, 세션이 Redis 에 저장되는 것과 Redis·MySQL 이 멈췄을 때의 동작을 확인한다.

## 실습 목표

- 서비스 3개를 빌드하고, 환경 변수만으로 DB·Redis 주소와 계정을 지정해 실행한다
- 빈 MySQL 에 스키마 4개, 시드, 서비스별 계정을 넣고 서비스마다 다른 스키마를 쓰는 것을 확인한다
- 로그인 세션이 Redis 에 저장되고, 다른 서비스에서도 같은 세션으로 요청이 처리되는 것을 확인한다
- 시나리오 테스트(60개 항목)를 통과시킨다
- Redis 를 멈추면 세션이 필요한 요청이 8초 뒤 500 으로 끝나는 것을 확인한다

## 사전 준비

| 항목 | 내용 | 비고 |
|---|---|---|
| 실행 위치 | WSL 2 Ubuntu | |
| 도구 | OpenJDK 21, Node.js 22, Docker Engine, curl | `sudo apt install -y openjdk-21-jdk nodejs npm docker.io curl` |
| 이미지 | `mysql:8.4`, `redis:7-alpine` | 처음 다운로드할 때 시간이 소요된다 |
| 포트 | MySQL 23306, Redis 26379, 서비스 28081 ~ 28083 | 모두 `127.0.0.1` 에만 연다 |
| 작업 디렉터리 | `~/vet2-lab` (저장소) | |

```bash
$ git clone <저장소 주소> ~/vet2-lab && cd ~/vet2-lab
```

## 1. 빌드

### 1. 서비스 3개 빌드

```bash
$ (cd msa && ./gradlew clean build)
# 출력 예
...(생략)...
> Task :reservation-service:check
> Task :reservation-service:build

BUILD SUCCESSFUL in 44s
27 actionable tasks: 27 executed

$ ls msa/*-service/build/libs/
# 출력 예
msa/auth-service/build/libs/:
vet-auth-1.0.0.jar

msa/clinic-service/build/libs/:
vet-clinic-1.0.0.jar

msa/reservation-service/build/libs/:
vet-reservation-1.0.0.jar
```

Gradle 이 서비스 3개와 공용 라이브러리를 컴파일하고 자동 테스트까지 실행했다. 실행할 jar 는 서비스마다 하나다.

`Failed to exec spawn helper` 로 실패하면 JDK 가 업데이트된 뒤 예전 Gradle 데몬이 남은 것이다. `(cd msa && ./gradlew --stop)` 뒤 다시 빌드한다.

### 2. 결과 확인

| 항목 | 내용 |
|---|---|
| 빌드 | `BUILD SUCCESSFUL`, 자동 테스트 포함 |
| 산출물 | `vet-auth-1.0.0.jar`, `vet-clinic-1.0.0.jar`, `vet-reservation-1.0.0.jar` |

## 2. 비밀번호와 저장소

### 1. 비밀번호 파일

비밀번호 5개를 `v2/_run/secrets.env` 한 파일에 둔다. `v2/_run/` 은 `.gitignore` 에 있어 Git 에 올라가지 않는다. 파일이 없을 때만 무작위 값으로 만든다.

```bash
$ [ -f v2/_run/secrets.env ] || ( mkdir -p v2/_run && umask 077 && \
    for k in DB_ROOT_PASSWORD DB_AUTH_PASSWORD DB_CLINIC_PASSWORD DB_RESERVATION_PASSWORD REDIS_PASSWORD; do \
      echo "$k=$(head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n')"; done > v2/_run/secrets.env )

$ cut -d= -f1 v2/_run/secrets.env
# 출력 예
DB_ROOT_PASSWORD
DB_AUTH_PASSWORD
DB_CLINIC_PASSWORD
DB_RESERVATION_PASSWORD
REDIS_PASSWORD

$ set -a; . v2/_run/secrets.env; set +a
```

`cut -d= -f1` 로 이름만 확인한다. 값은 화면에 출력하지 않는다. `set -a` 는 읽어 들인 값을 이 셸의 환경 변수로 내보낸다. 이후 단계의 명령은 이 셸에서 실행한다.

### 2. MySQL 과 Redis 실행

```bash
$ docker run -d --name v2-mysql -p 127.0.0.1:23306:3306 -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PASSWORD" mysql:8.4
# 출력 예
27b5c8b2d396597ca8c4b0aa3b89a63fdf27fc73a640ac59d2ee163b16c85e78

$ docker run -d --name v2-redis -p 127.0.0.1:26379:6379 redis:7-alpine redis-server --requirepass "$REDIS_PASSWORD"
# 출력 예
7412320d6ef823e8b54f09c6d54948a5e2fd2fa2353496ff3a2d29d81e09582d

$ docker ps --filter name=v2- --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
# 출력 예
NAMES      IMAGE            STATUS                  PORTS
v2-redis   redis:7-alpine   Up Less than a second   127.0.0.1:26379->6379/tcp
v2-mysql   mysql:8.4        Up Less than a second   33060/tcp, 127.0.0.1:23306->3306/tcp
```

`-p 127.0.0.1:23306:3306` 은 컨테이너의 3306 을 이 PC 의 `127.0.0.1:23306` 에만 연다. 다른 PC 에서는 닿지 않는다.

### 3. MySQL 준비 대기

```bash
$ t0=$(date +%s); until docker exec -e MYSQL_PWD="$DB_ROOT_PASSWORD" v2-mysql \
    mysql -h127.0.0.1 -P3306 --protocol=tcp -uroot -e "SELECT 1" >/dev/null 2>&1; do sleep 1; done; \
  echo "준비됨: $(( $(date +%s) - t0 ))초"
# 출력 예
준비됨: 11초
```

**TCP 로** 묻는 것이 중요하다. 공식 이미지는 처음 뜰 때 초기화용 임시 서버를 소켓으로만 띄운다(포트 0). 소켓으로 물으면 이 임시 서버가 답해 준비되지 않았는데도 준비된 것처럼 보이고, 바로 이어지는 초기화가 실패한다.

### 4. 결과 확인

| 항목 | 내용 |
|---|---|
| 비밀번호 | `v2/_run/secrets.env` 한 곳. 화면·Git 에 없다 |
| MySQL, Redis | `127.0.0.1` 의 23306, 26379 에서 실행 중 |
| 준비 판정 | TCP 로 `SELECT 1` 이 성공할 때 |

## 3. DB 초기화

### 1. SQL 실행 함수

```bash
$ sql() { docker exec -i -e MYSQL_PWD="$DB_ROOT_PASSWORD" v2-mysql mysql -uroot --default-character-set=utf8mb4 "$@"; }
```

root 로 SQL 을 실행한다. 비밀번호를 `-p<값>` 으로 명령줄에 쓰면 프로세스 목록에 보인다. 컨테이너의 환경 변수 `MYSQL_PWD` 로 넘긴다.

### 2. 스키마 4개

```bash
$ sql -e "CREATE DATABASE vet_load CHARACTER SET utf8mb4; CREATE DATABASE vet_auth CHARACTER SET utf8mb4;
          CREATE DATABASE vet_clinic CHARACTER SET utf8mb4; CREATE DATABASE vet_reservation CHARACTER SET utf8mb4;"
$ sql -e "SHOW DATABASES LIKE 'vet%'"
# 출력 예
Database (vet%)
vet_auth
vet_clinic
vet_load
vet_reservation
```

`vet_load` 에 원본 테이블과 시드를 먼저 넣고, 5단계에서 서비스별 스키마 3개로 나눈다.

### 3. 테이블과 시드

```bash
$ sql vet_load < db/schema.sql
$ sql -e "SELECT COUNT(*) AS tables_in_vet_load FROM information_schema.tables WHERE table_schema='vet_load'"
# 출력 예
tables_in_vet_load
6

$ node db/gen-seed.mjs > v2/_run/seed.sql && tail -1 v2/_run/seed.sql
# 출력 예
-- 슬롯 576개, 예약 166건, 사용자 305명, 반려동물 422마리, 이벤트 날 2026-11-30, 2026-12-01, 2026-12-02

$ sql vet_load < v2/_run/seed.sql
$ sql -e "SELECT (SELECT COUNT(*) FROM vet_load.users) users, (SELECT COUNT(*) FROM vet_load.pets) pets,
                 (SELECT COUNT(*) FROM vet_load.slots) slots, (SELECT COUNT(*) FROM vet_load.reservations) reservations"
# 출력 예
users	pets	slots	reservations
305	422	576	166
```

시드는 **실행하는 날**을 기준으로 앞으로 14일의 진료 시간표를 만든다. 오래전에 만든 시드를 쓰면 예약할 수 있는 시간이 모두 지난 날짜가 된다. 데이터는 모두 시험용이다.

### 4. 서비스 계정 3개

```bash
$ sql -e "CREATE USER 'vet_auth'@'%' IDENTIFIED BY '$DB_AUTH_PASSWORD';
          CREATE USER 'vet_clinic'@'%' IDENTIFIED BY '$DB_CLINIC_PASSWORD';
          CREATE USER 'vet_reservation'@'%' IDENTIFIED BY '$DB_RESERVATION_PASSWORD';"
$ sql -e "SELECT user, host FROM mysql.user WHERE user LIKE 'vet%'"
# 출력 예
user	host
vet_auth	%
vet_clinic	%
vet_reservation	%
```

서비스마다 다른 계정, 다른 비밀번호다. 한 서비스의 비밀번호가 새어도 다른 서비스의 데이터는 읽을 수 없다.

### 5. 서비스별 스키마로 나누기와 권한

```bash
$ sql < msa/db/split.sql && sql < msa/db/grants.sql && echo 완료
# 출력 예
완료

$ sql -t -e "SELECT table_schema, table_name, table_type FROM information_schema.tables
             WHERE table_schema LIKE 'vet\_%' ORDER BY 1,3,2"
# 출력 예
+-----------------+--------------+------------+
| TABLE_SCHEMA    | TABLE_NAME   | TABLE_TYPE |
+-----------------+--------------+------------+
| vet_auth        | users        | BASE TABLE |
| vet_clinic      | notices      | BASE TABLE |
| vet_clinic      | pets         | BASE TABLE |
| vet_clinic      | slots        | BASE TABLE |
| vet_clinic      | vets         | BASE TABLE |
| vet_reservation | reservations | BASE TABLE |
| vet_reservation | pets         | VIEW       |
| vet_reservation | slots        | VIEW       |
| vet_reservation | users        | VIEW       |
| vet_reservation | vets         | VIEW       |
+-----------------+--------------+------------+
```

`split.sql` 은 테이블을 각 서비스의 스키마로 옮긴다. reservation 은 다른 서비스의 테이블을 **뷰**로만 읽는다. 뷰에는 필요한 열만 있어서, 예를 들어 `vet_reservation.users` 에는 비밀번호 해시가 없다. `grants.sql` 은 계정마다 자기 스키마에만 권한을 준다.

### 6. 결과 확인

| 항목 | 내용 |
|---|---|
| 스키마 | `vet_load`(원본), `vet_auth`, `vet_clinic`, `vet_reservation` |
| 시드 | 사용자 305, 반려동물 422, 진료 시간 576, 예약 166 |
| 계정 | 서비스마다 하나, 자기 스키마에만 권한 |

## 4. 서비스 실행

### 1. auth 실행

서비스가 읽는 설정은 모두 환경 변수다 (`msa/common/src/main/resources/vet-common.yml`).

```bash
$ mkdir -p v2/_run/1-workload
$ SERVER_PORT=28081 \
  SPRING_DATASOURCE_URL="jdbc:mysql://127.0.0.1:23306/vet_auth?connectionTimeZone=LOCAL&characterEncoding=UTF-8" \
  SPRING_DATASOURCE_USERNAME=vet_auth \
  SPRING_DATASOURCE_PASSWORD="$DB_AUTH_PASSWORD" \
  SPRING_DATA_REDIS_HOST=127.0.0.1 SPRING_DATA_REDIS_PORT=26379 SPRING_DATA_REDIS_PASSWORD="$REDIS_PASSWORD" \
  REDIS_TLS=false \
  nohup java -jar msa/auth-service/build/libs/vet-auth-1.0.0.jar > v2/_run/1-workload/auth.log 2>&1 &
```

| 환경 변수 | 값 | 뜻 |
|---|---|---|
| `SERVER_PORT` | `28081` | 이 서비스가 듣는 포트. 이 실습에서만 서비스마다 다르게 한다 (컨테이너부터는 모두 8080) |
| `SPRING_DATASOURCE_URL` | `jdbc:mysql://127.0.0.1:23306/vet_auth?...` | DB 주소와 이 서비스의 스키마 |
| `SPRING_DATASOURCE_USERNAME` / `PASSWORD` | `vet_auth` / (secrets.env) | 이 서비스의 DB 계정 |
| `SPRING_DATA_REDIS_HOST` / `PORT` / `PASSWORD` | `127.0.0.1` / `26379` / (secrets.env) | 로그인 세션 저장소 |
| `REDIS_TLS` | `false` | 기본값은 `true`(관리형 Redis 용). 컨테이너 Redis 는 암호화하지 않는다 |
| `DB_POOL_MAX` | (지정하지 않음, 기본 10) | 서비스 하나가 여는 DB 연결 수 |

### 2. clinic, reservation 실행

같은 명령에서 아래만 바꾼다.

| 서비스 | `SERVER_PORT` | 스키마·계정 | 비밀번호 변수 | jar |
|---|---|---|---|---|
| clinic | 28082 | `vet_clinic` | `$DB_CLINIC_PASSWORD` | `msa/clinic-service/build/libs/vet-clinic-1.0.0.jar` |
| reservation | 28083 | `vet_reservation` | `$DB_RESERVATION_PASSWORD` | `msa/reservation-service/build/libs/vet-reservation-1.0.0.jar` |

### 3. 실행 확인

```bash
$ pgrep -af "vet-.*-1.0.0.jar"
# 출력 예
3877 java -jar msa/auth-service/build/libs/vet-auth-1.0.0.jar
3878 java -jar msa/clinic-service/build/libs/vet-clinic-1.0.0.jar
3879 java -jar msa/reservation-service/build/libs/vet-reservation-1.0.0.jar

$ for p in 28081 28082 28083; do curl -s -o /dev/null -w "$p /health %{http_code}\n" http://127.0.0.1:$p/health; done
# 출력 예
28081 /health 200
28082 /health 200
28083 /health 200

$ grep -h "Started .* seconds" v2/_run/1-workload/*.log
# 출력 예
Started AuthServiceApplication in 4.058 seconds (process running for 4.736)
Started ClinicServiceApplication in 3.993 seconds (process running for 4.688)
Started ReservationServiceApplication in 4.089 seconds (process running for 4.801)
```

세 서비스 모두 4초 안팎에 시작했다. `/health` 는 DB 를 확인하지 않고 프로세스가 요청을 받을 수 있는지만 답한다. 이후 쿠버네티스의 probe 가 이 경로를 쓴다.

### 4. 결과 확인

| 항목 | 내용 |
|---|---|
| 프로세스 | jar 3개가 각자의 포트에서 실행 |
| 설정 | 모두 환경 변수. 소스와 jar 에 주소·비밀번호가 없다 |
| 상태 | 세 서비스 `/health` 200 |

## 5. 요청과 세션

### 1. 로그인 없이 조회

```bash
$ curl -s http://127.0.0.1:28082/api/notices | head -c 300; echo
# 출력 예
[{"noticeId":5,"category":"EVENT","title":"예방접종 할인 예약 오픈 — 11월 30일(월) 09:00","pinned":true,"createdAt":"2026-11-24T10:00:00"},{"noticeId":4,"category":"NOTICE","title":"주차 안내 (건물 뒤편 전용 주차장)","pinned":false,"createdAt":"2026-11-20T10:00:00"},{"not
```

### 2. 로그인과 다른 서비스에서의 세션

시험 계정 `owner001` 로 auth 에 로그인하고, 받은 쿠키로 **clinic** 에 요청한다.

```bash
$ curl -s -c /tmp/lab01.cookie -H "Content-Type: application/json" \
    -d '{"loginId":"owner001","password":"test-only"}' http://127.0.0.1:28081/api/auth/login; echo
# 출력 예
{"userId":6,"loginId":"owner001","name":"안소율","role":"OWNER","vetId":null}

$ curl -s -b /tmp/lab01.cookie http://127.0.0.1:28082/api/pets; echo
# 출력 예
[{"petId":1,"name":"콩이","species":"DOG","age":3},{"petId":2,"name":"나비","species":"CAT","age":5}]

$ docker exec -e REDISCLI_AUTH="$REDIS_PASSWORD" v2-redis redis-cli --no-auth-warning KEYS "*"
# 출력 예
spring:session:sessions:bd21ec76-b4f6-43ed-81db-54cb403a098a
```

auth 에서 로그인했는데 clinic 이 같은 쿠키로 이 보호자의 반려동물을 돌려주었다. 세션이 각 서비스의 메모리가 아니라 **Redis** 에 저장되기 때문이다 (`spring:session:sessions:...`). 서비스를 여러 개 띄워도 어느 쪽이 요청을 받든 로그인이 유지된다.

### 3. 시나리오 테스트

화면이 쓰는 API 를 순서대로 부르고 기대값과 비교한다 (60개 항목). 이후 모든 실습에서 같은 파일을 주소만 바꿔 쓴다.

```bash
$ v2/tests/with-secrets.sh node v2/tests/scenario.mjs \
    --auth-url http://127.0.0.1:28081 --clinic-url http://127.0.0.1:28082 \
    --reservation-url http://127.0.0.1:28083 --db-container v2-mysql
# 출력 예
시나리오 테스트  2026-11-25 11:10:25 KST
대상: 서비스 직접  auth http://127.0.0.1:28081  clinic http://127.0.0.1:28082  reservation http://127.0.0.1:28083
■ 1. 상태
■ 2. 로그인 없이 조회
...(생략)...
■ 11. DB 계정 경계
결과: 통과 60 / 실패 0
```

`with-secrets.sh` 는 DB 계정 경계(11번) 검사에 쓸 비밀번호를 환경 변수로만 넘긴다. 11번은 서비스 계정으로 MySQL 에 접속해 다른 서비스의 표를 읽지 못하는지 본다.

### 4. 결과 확인

| 항목 | 내용 |
|---|---|
| 세션 | Redis 에 저장. 다른 서비스에서도 같은 쿠키로 로그인 상태 |
| 시나리오 | 통과 60 / 실패 0 |

## 6. Redis 가 멈췄을 때

### 1. Redis 중지

```bash
$ docker stop v2-redis
# 출력 예
v2-redis

$ curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -b /tmp/lab01.cookie http://127.0.0.1:28081/api/auth/me
# 출력 예
500 8.015602s

$ curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://127.0.0.1:28082/api/notices
# 출력 예
200 0.010113s
```

세션이 필요한 요청은 8초 동안 응답이 없다가 **500** 으로 끝났다. 세션이 필요 없는 공지 조회는 그대로 200 이다. 늦게, 500 으로 실패하는 것은 소스의 동작이라 이 작업에서는 고치지 않았다 (① W-3).

### 2. Redis 다시 시작

```bash
$ docker start v2-redis
# 출력 예
v2-redis

$ curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -b /tmp/lab01.cookie http://127.0.0.1:28081/api/auth/me
# 출력 예
200 0.010557s

$ docker logs v2-redis 2>&1 | grep -E "Saving the final RDB|DB saved on disk|DB loaded from disk" | tail -3
# 출력 예
1:M 25 Nov 2026 02:11:44.435 * Saving the final RDB snapshot before exiting.
1:M 25 Nov 2026 02:11:44.451 * DB saved on disk
1:M 25 Nov 2026 02:11:53.037 * DB loaded from disk: 0.001 seconds
```

같은 쿠키로 다시 200 이다. `docker stop` 이 보낸 종료 신호를 받은 Redis 가 데이터를 파일(RDB)로 저장했고, 같은 컨테이너를 다시 시작하자 그 파일을 읽어 세션이 복구되었다. 컨테이너를 지우고 새로 만들면 파일도 사라져 모두 다시 로그인해야 한다.

### 3. 결과 확인

| 항목 | 내용 |
|---|---|
| Redis 중지 | 세션이 필요한 요청은 8초 뒤 500, 공지 조회는 200 |
| 다시 시작 | 종료 때 저장한 파일로 세션 복구 |

MySQL 을 멈췄을 때까지 한 번에 보려면 `v2/workload/fault-check.sh` 를 실행한다. MySQL 이 멈추면 DB 를 쓰는 요청이 3초 뒤 `503 DB_UNAVAILABLE` 로 답하고, 다시 시작하면 서비스를 재시작하지 않아도 7초 안에 회복된다.

## 자원 정리

```bash
$ pkill -f 'vet-(auth|clinic|reservation)-1.0.0.jar'
$ docker rm -f v2-mysql v2-redis
$ rm -f /tmp/lab01.cookie
```

| 항목 | 내용 |
|---|---|
| 서비스 | 프로세스 3개를 끝낸다 |
| MySQL, Redis | 컨테이너와 그 안의 데이터가 삭제된다 |
| 비밀번호 파일 | `v2/_run/secrets.env` 는 유지한다 (lab02 이후에 쓴다) |

**한 번에 하기:** 2 ~ 4단계는 `v2/workload/stores.sh up`, `v2/workload/db-init.sh`, `v2/workload/services.sh start` 가 같은 명령을 실행한다. 정리는 `services.sh stop`, `stores.sh down`.
