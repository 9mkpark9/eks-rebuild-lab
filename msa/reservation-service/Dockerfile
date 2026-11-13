# reservation-service 이미지 (/api/reservations, 공지를 뺀 /api/admin, /api/director)
# 빌드 위치는 msa/ 다 (common 과 Gradle 래퍼가 필요하다):
#   docker build -f reservation-service/Dockerfile --build-arg VERSION=1.0.0 -t ghcr.io/9mkpark9/vet-reservation:1.0.0 .
# 세 서비스의 Dockerfile 은 서비스 이름만 다르다. 하나를 고치면 나머지 둘도 같이 고친다.

# ── 1) 빌드: JDK 로 jar 를 만들고 층별로 푼다 ─────────────────────────
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /src

# 래퍼와 빌드 스크립트만 먼저 복사한다. 소스만 바뀌면 아래 의존성 층을 다시 받지 않는다.
COPY gradlew settings.gradle build.gradle ./
COPY gradle gradle
COPY common/build.gradle common/
COPY auth-service/build.gradle auth-service/
COPY clinic-service/build.gradle clinic-service/
COPY reservation-service/build.gradle reservation-service/
# Windows 에서 체크아웃하면 gradlew 가 CRLF 일 수 있다
RUN sed -i 's/\r$//' gradlew && chmod +x gradlew \
 && ./gradlew --no-daemon -q :reservation-service:dependencies --configuration runtimeClasspath > /dev/null

COPY common/src common/src
COPY reservation-service/src reservation-service/src
ARG VERSION=dev
RUN ./gradlew --no-daemon -q :reservation-service:bootJar -Pversion=${VERSION} \
 && java -Djarmode=tools -jar reservation-service/build/libs/vet-reservation-${VERSION}.jar \
      extract --layers --destination /layers --application-filename app.jar

# ── 2) 실행: JRE 만 넣는다 ────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app -H -s /sbin/nologin app
WORKDIR /app

# 덜 바뀌는 층부터 복사한다. 코드만 고치면 마지막 application 층만 새로 올라간다.
COPY --from=build /layers/dependencies/ ./
COPY --from=build /layers/spring-boot-loader/ ./
COPY --from=build /layers/snapshot-dependencies/ ./
COPY --from=build /layers/application/ ./

ARG VERSION=dev
# 힙은 컨테이너 메모리 한도의 절반까지만 쓴다. 나머지는 메타스페이스·스레드 스택·코드 캐시 몫이다.
# 한도를 넘기 전에 JVM 이 스스로 죽어야 재시작 사유가 로그에 남는다.
ENV APP_VERSION=${VERSION} \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=50 -XX:+ExitOnOutOfMemoryError -Dfile.encoding=UTF-8"

USER 10001:10001
EXPOSE 8080
# exec 형식: java 가 1번 프로세스라 SIGTERM 을 직접 받아 graceful shutdown 을 한다
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
