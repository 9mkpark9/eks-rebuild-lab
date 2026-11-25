# syntax=docker/dockerfile:1
# 빌드 최적화 사다리 E: D + Gradle 캐시 마운트 (최종 service.Dockerfile 과 같은 빌드 방식)
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY . .
ARG SERVICE
RUN --mount=type=cache,id=bench-gradle,target=/root/.gradle \
    ./gradlew --no-daemon :${SERVICE}-service:bootJar && cp ${SERVICE}-service/build/libs/vet-${SERVICE}-1.0.0.jar /app.jar

FROM eclipse-temurin:21-jre-alpine
COPY --from=build /app.jar /app/app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
