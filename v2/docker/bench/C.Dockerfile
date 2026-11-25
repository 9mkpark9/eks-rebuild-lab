# 빌드 최적화 사다리 C: B + 멀티스테이지 (실행 단계는 JRE, alpine 아님)
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY . .
ARG SERVICE
RUN ./gradlew --no-daemon :${SERVICE}-service:bootJar && cp ${SERVICE}-service/build/libs/vet-${SERVICE}-1.0.0.jar /app.jar

FROM eclipse-temurin:21-jre
COPY --from=build /app.jar /app/app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
