# [실습] lab02: 이미지와 compose

| 속성 | 값 |
|---|---|
| 상위 항목 | ② 이미지 빌드·컨테이너 테스트 |
| 선행 작업 | [lab01: 워크로드 직접 실행](lab01-워크로드-직접-실행.md) |
| 후속 작업 | [lab03: AWS 준비와 ECR](lab03-AWS-준비와-ECR.md) |

서비스 3개, web, DB 의 이미지 5개를 만들고 compose 로 컨테이너 6개를 띄운다. 이미지가 두 단계 빌드로 JRE 와 jar 만 담는 것, 모든 프로세스가 root 가 아닌 것, 메모리 한도에 맞춰 힙이 정해지는 것을 확인한다. 요청을 보내는 중에 컨테이너를 내려 정상 종료(SIGTERM)와 강제 종료(SIGKILL)의 차이를 확인한다.

## 실습 목표

- 서비스 이미지가 두 단계 빌드로 만들어지고, 실행 이미지에 JRE 와 jar 만 들어가는 것을 확인한다
- compose 로 6개를 띄우고 healthcheck 가 모두 통과할 때까지 기다린다
- 모든 프로세스가 root 가 아닌 사용자로 실행되는 것을 확인한다
- 메모리 한도 384MiB 에서 자바 힙 상한이 그 50% 로 정해지는 것을 확인한다
- web 을 거쳐 시나리오 테스트(65개 항목)를 통과시킨다
- 정상 종료에서는 처리 중인 요청이 끊기지 않고, 강제 종료에서는 끊기는 것을 확인한다

## 사전 준비

| 항목 | 내용 | 비고 |
|---|---|---|
| 실행 위치 | WSL 2 Ubuntu, Docker Engine (BuildKit) | |
| 비밀번호 | `v2/_run/secrets.env` | lab01 에서 만든 파일 |
| 이미지 | `eclipse-temurin:21-jdk`, `eclipse-temurin:21-jre-alpine`, `node:22-alpine`, `httpd:2.4-alpine`, `mysql:8.4`, `redis:7-alpine` | 처음 빌드할 때 다운로드에 시간이 소요된다 |
| 포트 | 28090 (web) | 28080 을 다른 것이 쓰고 있어 바꿨다 |
| 작업 디렉터리 | `~/vet2-lab` | |

```bash
$ cd ~/vet2-lab
$ export WEB_PORT=28090
$ C="docker compose -f v2/docker/compose.yaml --env-file v2/_run/secrets.env"
```

`C` 는 compose 명령을 줄이려고 만든 변수다. 비밀번호는 `--env-file` 로만 넘긴다. compose 파일과 이미지에는 값이 없다.

## 1. 이미지 빌드

### 1. 서비스 Dockerfile

① `v2/docker/service.Dockerfile` (auth, clinic, reservation 공용)

```dockerfile
# syntax=docker/dockerfile:1
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY . .
ARG SERVICE
ARG VERSION=1.0.0
RUN --mount=type=cache,target=/root/.gradle \
    sed -i 's/\r$//' gradlew \
 && ./gradlew --no-daemon :${SERVICE}-service:bootJar -Pversion=${VERSION} \
 && cp ${SERVICE}-service/build/libs/vet-${SERVICE}-${VERSION}.jar /app.jar

FROM eclipse-temurin:21-jre-alpine
COPY --from=build /app.jar /app/app.jar
ARG VERSION=1.0.0
ENV APP_VERSION=${VERSION} \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=50"
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

| 줄 | 왜 |
|---|---|
| `FROM ...-jdk AS build` → `FROM ...-jre-alpine` | 두 단계. 첫 단계에서 jar 를 만들고, 실행 이미지에는 JRE 와 jar 만 옮긴다 |
| `--mount=type=cache,target=/root/.gradle` | Gradle 과 라이브러리를 빌드 사이에 남긴다. 소스 한 줄을 고친 뒤 다시 빌드가 54.8초 → 12.1초 |
| `sed -i 's/\r$//' gradlew` | Windows 에서 받은 `gradlew` 의 줄 끝(CRLF) 때문에 `./gradlew: not found` 가 났다 |
| `JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=50` | 힙 상한을 컨테이너 메모리 한도의 50% 로 (기본은 25%) |
| `USER 10001:10001` | root 가 아닌 사용자. 숫자로 적어 쿠버네티스가 `runAsNonRoot` 로 확인할 수 있다 |
| `ENTRYPOINT ["java", ...]` | 대괄호 형식이라 셸 없이 java 가 1번 프로세스가 된다. 종료 신호를 java 가 직접 받는다 |

② `v2/docker/service.Dockerfile.dockerignore`

```
**/build
.gradle
```

이 PC 에서 만든 빌드 결과와 캐시를 빌드 컨텍스트에 보내지 않는다. 보내는 양이 112.66MB 에서 6.88kB 로 줄었다.

### 2. 서비스 이미지 하나 빌드

```bash
$ docker build -f v2/docker/service.Dockerfile --build-arg SERVICE=auth -t vet2-auth:1.0.0 msa
# 출력 예
...(생략)...
#11 [build 3/4] COPY . .
#11 CACHED
#12 [build 2/4] WORKDIR /src
#12 CACHED
#13 [build 4/4] RUN --mount=type=cache,target=/root/.gradle     sed -i 's/\r$//' gradlew  && ./gradlew --no-daemon :auth-service:bootJar -Pversion=1.0.0  && cp auth-service/build/libs/vet-auth-1.0.0.jar /app.jar
#13 CACHED
#14 [stage-1 2/2] COPY --from=build /app.jar /app/app.jar
#14 CACHED
#15 naming to docker.io/library/vet2-auth:1.0.0 done
#15 DONE 0.3s
```

빌드 위치(마지막 인자)는 `msa` 다. 소스가 바뀌지 않았으므로 모든 단계가 `CACHED` 로 끝났다. 처음 빌드하면 각 단계가 실제로 실행되고 1 ~ 2분이 걸린다.

### 3. 나머지 이미지

```bash
$ $C build
# 출력 예
...(생략)...
 Image vet2-db:1.0.0 Built
 Image vet2-reservation:1.0.0 Built
 Image vet2-web:1.0.0 Built
 Image vet2-auth:1.0.0 Built
 Image vet2-clinic:1.0.0 Built

$ docker image ls --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep -E "REPOSITORY|^vet2-(auth|clinic|reservation|web|db):1.0.0"
# 출력 예
REPOSITORY:TAG                                                                 SIZE
vet2-db:1.0.0                                                                  1.27GB
vet2-clinic:1.0.0                                                              366MB
vet2-reservation:1.0.0                                                         366MB
vet2-web:1.0.0                                                                 115MB
vet2-auth:1.0.0                                                                366MB
```

compose 파일의 `build:` 항목대로 5개를 만든다. web 은 화면을 Node 로 빌드한 뒤 Apache httpd 에 담고, db 는 MySQL 8.4 에 초기화 스크립트와 시드 생성기를 담는다.

### 4. 이미지 확인

```bash
$ for i in auth clinic reservation web db; do docker image inspect vet2-$i:1.0.0 \
    --format "vet2-$i  {{.Os}}/{{.Architecture}}  user={{.Config.User}}  entrypoint={{json .Config.Entrypoint}}"; done
# 출력 예
vet2-auth  linux/amd64  user=10001:10001  entrypoint=["java","-jar","/app/app.jar"]
vet2-clinic  linux/amd64  user=10001:10001  entrypoint=["java","-jar","/app/app.jar"]
vet2-reservation  linux/amd64  user=10001:10001  entrypoint=["java","-jar","/app/app.jar"]
vet2-web  linux/amd64  user=82:82  entrypoint=null
vet2-db  linux/amd64  user=  entrypoint=["docker-entrypoint.sh"]

$ docker history vet2-auth:1.0.0 --format "{{.Size}}\t{{.CreatedBy}}" | head -6
# 출력 예
0B	ENTRYPOINT ["java" "-jar" "/app/app.jar"]
0B	EXPOSE 8080/tcp
0B	USER 10001:10001
0B	ENV APP_VERSION=1.0.0 JAVA_TOOL_OPTIONS=-XX:…
0B	ARG VERSION=1.0.0
37.1MB	COPY /app.jar /app/app.jar # buildkit
```

모두 `linux/amd64` 이다. 이후 실습의 EC2·EKS 노드(x86_64)에서 그대로 실행된다. `docker history` 의 위쪽에는 실행 단계만 있고 JDK·Gradle·소스가 없다. 첫 단계는 실행 이미지에 남지 않는다.

db 이미지의 `user=` 가 비어 있다. MySQL 공식 이미지는 root 로 시작해 진입 스크립트가 mysqld 를 `mysql` 사용자(999)로 바꿔 띄운다. 3단계에서 확인한다.

### 5. 결과 확인

| 항목 | 내용 |
|---|---|
| 이미지 | 서비스 366MB × 3, web 115MB, db 1.27GB |
| 플랫폼 | 모두 `linux/amd64` |
| 실행 이미지 | JRE + jar 만. JDK·소스는 첫 단계에만 있다 |

## 2. compose 로 실행

### 1. compose 파일의 핵심

`v2/docker/compose.yaml` 에서 서비스 하나(auth)와 공통 설정:

```yaml
name: v2
x-service: &service
  environment: &service-env
    SPRING_DATA_REDIS_HOST: redis
    SPRING_DATA_REDIS_PASSWORD: ${REDIS_PASSWORD:?REDIS_PASSWORD 가 필요합니다}
    REDIS_TLS: "false"
    DB_POOL_MAX: "5"
  mem_limit: 384m
  restart: unless-stopped
  stop_grace_period: 40s
  healthcheck:
    test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/health"]
    interval: 5s
    timeout: 3s
    retries: 12
    start_period: 30s

services:
  auth:
    <<: *service
    image: vet2-auth:${VERSION:-1.0.0}
    build: { context: ../../msa, dockerfile: ../v2/docker/service.Dockerfile, args: { SERVICE: auth, VERSION: "${VERSION:-1.0.0}" } }
    environment:
      <<: *service-env
      SPRING_DATASOURCE_URL: jdbc:mysql://mysql:3306/vet_auth?connectionTimeZone=LOCAL&characterEncoding=UTF-8
      SPRING_DATASOURCE_USERNAME: vet_auth
      SPRING_DATASOURCE_PASSWORD: ${DB_AUTH_PASSWORD:?DB_AUTH_PASSWORD 가 필요합니다}
```

| 설정 | 값 | 왜 |
|---|---|---|
| 호스트 이름 | `mysql`, `redis` | compose 네트워크 안에서는 서비스 이름이 곧 주소다 (lab01 의 `127.0.0.1:23306` 대신) |
| `${...:?...}` | 비밀번호 | `--env-file` 에 값이 없으면 시작하지 않고 그 메시지를 보여 준다 |
| `mem_limit` | 384m | 실제 사용량(약 175MiB, 3단계)에 여유를 둔 값 |
| `healthcheck` | `/health` 를 5초마다 | `up --wait` 가 이것이 통과할 때까지 기다린다 |
| `stop_grace_period` | 40s | 종료 신호 뒤 강제 종료까지의 시간. 스프링은 처리 중인 요청을 최대 30초 기다린다 |
| `depends_on` | 쓰지 않음 | 어떤 순서로 떠도 정상이 되어야 한다. 쿠버네티스에는 시작 순서가 없다 |
| 포트 | web 의 `${WEB_PORT}:8080` 하나 | 밖에서 들어오는 길은 web 뿐이다. 서비스·DB 는 포트를 열지 않는다 |
| 볼륨 | `mysql-data` | `down` 해도 데이터가 남는다. `down -v` 로 지운다 |

### 2. 실행

```bash
$ t0=$(date +%s); $C up -d --wait; echo "모두 healthy 까지 $(( $(date +%s) - t0 ))초"
# 출력 예
...(생략)...
 Container v2-web-1 Healthy
 Container v2-clinic-1 Healthy
 Container v2-auth-1 Healthy
 Container v2-redis-1 Healthy
 Container v2-reservation-1 Healthy
 Container v2-mysql-1 Healthy
모두 healthy 까지 21초

$ $C ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
# 출력 예
NAME               STATUS                    PORTS
v2-auth-1          Up 20 seconds (healthy)   8080/tcp
v2-clinic-1        Up 20 seconds (healthy)   8080/tcp
v2-mysql-1         Up 20 seconds (healthy)   3306/tcp, 33060/tcp
v2-redis-1         Up 20 seconds (healthy)   6379/tcp
v2-reservation-1   Up 19 seconds (healthy)   8080/tcp
v2-web-1           Up 21 seconds (healthy)   80/tcp, 0.0.0.0:28090->8080/tcp, [::]:28090->8080/tcp
```

6개가 모두 `(healthy)` 다. 밖과 이어진 포트(`0.0.0.0:28090->8080`)는 web 하나뿐이다.

### 3. DB 초기화

```bash
$ $C logs mysql | grep "\[vet\]"
# 출력 예
mysql-1  | [vet] 1) 스키마 4개와 서비스 계정 3개
mysql-1  | [vet] 2) 테이블과 시드 (vet_load)
mysql-1  | [vet] 3) 서비스별 스키마로 옮기고 권한 주기
mysql-1  | [vet] 초기화 끝
```

lab01 에서 손으로 한 DB 초기화를 db 이미지가 처음 뜰 때 스스로 한다. MySQL 공식 이미지는 데이터 폴더가 비어 있을 때 `/docker-entrypoint-initdb.d/` 의 스크립트를 실행한다. 볼륨에 데이터가 있으면 초기화를 건너뛴다.

### 4. 결과 확인

| 항목 | 내용 |
|---|---|
| 컨테이너 | 6개 healthy, 21초 |
| 밖으로 연 포트 | web 28090 하나 |
| DB | 첫 실행 때 이미지가 스스로 초기화 |

## 3. 실행 사용자와 메모리

### 1. 프로세스의 사용자

```bash
$ for s in web auth clinic reservation; do printf "%-12s " $s; $C exec -T $s id; done
# 출력 예
web          uid=82(www-data) gid=82(www-data) groups=82(www-data)
auth         uid=10001 gid=10001 groups=10001
clinic       uid=10001 gid=10001 groups=10001
reservation  uid=10001 gid=10001 groups=10001

$ docker top v2-mysql-1 -o user,pid,comm
# 출력 예
USER                PID                 COMMAND
999                 6879                mysqld

$ docker top v2-redis-1 -o user,pid,comm
# 출력 예
USER                PID                 COMMAND
999                 7138                redis-server
```

MySQL 은 `docker top` 으로 본다. `$C exec mysql id` 는 `uid=0(root)` 를 보여 주는데, `exec` 가 이미지의 기본 사용자(지정 없음 = root)로 들어가기 때문이다. 실제로 일하는 mysqld 프로세스는 999 다.

### 2. 메모리 사용량과 힙 상한

```bash
$ docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}" | grep -E "NAME|v2-"
# 출력 예
NAME               MEM USAGE / LIMIT
v2-redis-1         8.664MiB / 64MiB
v2-mysql-1         478.5MiB / 1GiB
v2-web-1           7.656MiB / 64MiB
v2-reservation-1   170.6MiB / 384MiB
v2-clinic-1        173.5MiB / 384MiB
v2-auth-1          174.9MiB / 384MiB

$ $C exec -T auth java -XX:+PrintFlagsFinal -version 2>/dev/null | grep " MaxHeapSize "
# 출력 예
   size_t MaxHeapSize                              = 201326592                                 {product} {ergonomic}
```

`MaxHeapSize` 201326592 바이트 = 192MiB = 한도 384MiB 의 50% 다. 자바가 컨테이너의 메모리 한도를 읽어 힙을 정했다(`{ergonomic}`). 한도가 없으면 이 PC 전체 메모리의 25% 를 힙 상한으로 잡는다.

### 3. 결과 확인

| 항목 | 내용 |
|---|---|
| 사용자 | web 82, 서비스 10001, MySQL·Redis 999. root 로 도는 프로세스가 없다 |
| 메모리 | 서비스 약 175MiB / 한도 384MiB |
| 힙 상한 | 192MiB (한도의 50%) |

## 4. web 을 거친 요청

### 1. 응답 헤더

```bash
$ curl -s -o /dev/null -D - http://localhost:28090/api/notices | grep -iE "^HTTP|x-web-node|x-served-by"
# 출력 예
HTTP/1.1 200
X-Web-Node: fd2dd17f1462
X-Served-By: fe50c98d0301
```

`X-Web-Node` 는 응답한 web 컨테이너, `X-Served-By` 는 요청을 처리한 서비스 컨테이너의 호스트 이름이다(여기서는 컨테이너 ID 앞 12자리). 쿠버네티스에서는 Pod 이름이 된다.

web(Apache)은 경로를 보고 세 서비스로 나눠 보낸다. `v2/docker/web/httpd.conf` 의 해당 부분:

```apache
ProxyPass /api/auth/          http://auth:8080/api/auth/            connectiontimeout=2 retry=0
ProxyPass /api/status/auth    http://auth:8080/api/status/auth      connectiontimeout=2 retry=0
ProxyPass /api/admin/notices  http://clinic:8080/api/admin/notices  connectiontimeout=2 retry=0
ProxyPass /api/pets           http://clinic:8080/api/pets           connectiontimeout=2 retry=0
ProxyPass /api/notices        http://clinic:8080/api/notices        connectiontimeout=2 retry=0
ProxyPass /api/slots          http://clinic:8080/api/slots          connectiontimeout=2 retry=0
ProxyPass /api/status/clinic  http://clinic:8080/api/status/clinic  connectiontimeout=2 retry=0
# 나머지 /api 는 reservation (예약, 간호사, 원장)
ProxyPass /api/               http://reservation:8080/api/          connectiontimeout=2 retry=0
```

`connectiontimeout=2 retry=0` 은 멈춘 서비스로 가는 요청이 기본값(60초)만큼 매달리지 않고 2초 안에 실패하게 한다 (② C-9).

브라우저로 `http://localhost:28090/` (소개), `http://localhost:28090/app/` (예약 화면)을 열 수 있다. 시험 계정은 보호자 `owner001`, 간호사 `admin1`, 원장 `vet1`, 비밀번호 `test-only` 다.

### 2. 시나리오 테스트

```bash
$ v2/tests/with-secrets.sh node v2/tests/scenario.mjs --base-url http://localhost:28090 --db-container v2-mysql-1
# 출력 예
시나리오 테스트  2026-11-25 11:14:44 KST
대상: 웹 서버 경유  http://localhost:28090
...(생략)...
결과: 통과 65 / 실패 0
```

lab01 의 60개에 화면 항목이 더해졌다 (화면 파일과 응답 헤더). 서비스를 직접 부르던 것을 web 하나의 주소로 바꿨다.

### 3. 결과 확인

| 항목 | 내용 |
|---|---|
| 경로 | 브라우저 → web(28090) → 경로별 서비스 |
| 시나리오 | 통과 65 / 실패 0 |

## 5. 정상 종료와 강제 종료

### 1. 정상 종료 (SIGTERM)

같은 도커 네트워크 안의 컨테이너에서 auth 로 20초 동안 동시 20개씩 로그인 요청을 보낸다. 4초 뒤 auth 를 `docker stop` 으로 내린다.

```bash
$ (docker run --rm -i --network v2_default node:22-alpine node --input-type=module - http://auth:8080 20 \
     < v2/tests/shutdown-check.mjs) & sleep 4; docker stop v2-auth-1 >/dev/null; wait
# 출력 예
  내려간 뒤 접속 실패: 1064건
  응답 200: 564건
  → 처리 중 끊긴 요청 0건

$ docker start v2-auth-1
```

`docker stop` 은 SIGTERM 을 보내고 `stop_grace_period`(40초)까지 기다린다. java 가 1번 프로세스라 신호를 직접 받아, 새 연결을 받지 않고 처리 중이던 요청은 마친 뒤 내려갔다. "내려간 뒤 접속 실패" 는 이미 닫힌 뒤에 보낸 요청이다. 쿠버네티스에서는 이런 요청이 다른 Pod 로 가게 만든다 (lab06).

이번 실행에서는 끊긴 요청이 0건이었다. 같은 실험을 여러 번 했을 때 1 ~ 2건이 끊긴 실행도 있었다 (② 문서 C-4).

### 2. 강제 종료 (SIGKILL)

```bash
$ (docker run --rm -i --network v2_default node:22-alpine node --input-type=module - http://auth:8080 20 \
     < v2/tests/shutdown-check.mjs) & sleep 4; docker kill v2-auth-1 >/dev/null; wait
# 출력 예
  내려간 뒤 접속 실패: 2925건
  응답 200: 356건
  처리 중 끊김: 20건
  → 처리 중 끊긴 요청 20건

$ docker start v2-auth-1
```

`docker kill` 은 SIGKILL 로 프로세스를 바로 끝낸다. 그 순간 처리 중이던 20건(동시 요청 수)이 모두 응답 없이 끊겼다.

### 3. 결과 확인

| 항목 | 정상 종료 (`stop`) | 강제 종료 (`kill`) |
|---|---|---|
| 신호 | SIGTERM, 40초 유예 | SIGKILL |
| 처리 중 끊긴 요청 | 0건 (다른 실행에서 1 ~ 2건) | 20건 |

## 자원 정리

```bash
$ $C down            # 컨테이너와 네트워크 삭제. 볼륨(데이터)은 남는다
$ $C down -v         # 볼륨까지 삭제. 비밀번호를 바꿨다면 이것으로 지우고 다시 up 한다
```

| 항목 | 내용 |
|---|---|
| 컨테이너, 네트워크 | 삭제된다 |
| 볼륨 `v2_mysql-data` | `down` 은 유지, `down -v` 는 삭제 |
| 이미지 | 유지한다 (lab03 에서 ECR 에 올린다) |

볼륨이 남은 채로 `secrets.env` 의 비밀번호를 바꾸면, MySQL 은 예전 비밀번호로 초기화된 데이터를 그대로 쓰므로 서비스가 DB 에 접속하지 못한다(503). 이때는 `down -v` 뒤 다시 `up` 한다.
