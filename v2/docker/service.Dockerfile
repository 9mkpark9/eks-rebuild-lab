# syntax=docker/dockerfile:1
# 서비스 이미지 (auth, clinic, reservation 공용). 빌드 위치: msa/
#   docker build -f v2/docker/service.Dockerfile --build-arg SERVICE=auth -t vet2-auth:1.0.0 msa
# 무엇을 빼고 보내는지는 옆의 service.Dockerfile.dockerignore 에 있다.

# ── 1) 빌드: JDK 와 Gradle 로 jar 를 만든다 ──────────────────────────
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY . .
ARG SERVICE
ARG VERSION=1.0.0
# - sed: Windows 에서 받은 gradlew 는 줄 끝이 CRLF 라 리눅스에서 실행되지 않는다 (문제 C-1)
# - cache: Gradle 배포판과 라이브러리를 빌드 사이에 남겨 둔다. 세 서비스가 같은 캐시를 쓴다 (문제 C-7)
RUN --mount=type=cache,target=/root/.gradle \
    sed -i 's/\r$//' gradlew \
 && ./gradlew --no-daemon :${SERVICE}-service:bootJar -Pversion=${VERSION} \
 && cp ${SERVICE}-service/build/libs/vet-${SERVICE}-${VERSION}.jar /app.jar

# ── 2) 실행: JRE 와 jar 하나만 넣는다 ────────────────────────────────
FROM eclipse-temurin:21-jre-alpine
COPY --from=build /app.jar /app/app.jar
ARG VERSION=1.0.0
# 힙은 컨테이너 메모리 한도의 50% 까지 쓴다 (기본값은 25%). 한도는 compose 가 정한다 (문제 C-6)
ENV APP_VERSION=${VERSION} \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=50"
# root 가 아닌 사용자 (문제 C-5)
USER 10001:10001
EXPOSE 8080
# 대괄호 형식: java 가 1번 프로세스가 되어 종료 신호를 직접 받는다 (문제 C-4)
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
