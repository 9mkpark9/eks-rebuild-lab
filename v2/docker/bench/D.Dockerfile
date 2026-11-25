# 빌드 최적화 사다리 D: C + 실행 베이스를 JRE alpine 으로
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY . .
ARG SERVICE
RUN ./gradlew --no-daemon :${SERVICE}-service:bootJar && cp ${SERVICE}-service/build/libs/vet-${SERVICE}-1.0.0.jar /app.jar

FROM eclipse-temurin:21-jre-alpine
COPY --from=build /app.jar /app/app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
