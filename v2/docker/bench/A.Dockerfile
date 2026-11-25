# 빌드 최적화 사다리 A: v0 그대로 (JDK 한 단계, .dockerignore 없음)
# v0 — 가장 단순한 형태. 빌드 위치: msa/
#   docker build -f v2/docker/v0/service.Dockerfile --build-arg SERVICE=auth -t vet2-auth:v0 msa
FROM eclipse-temurin:21-jdk
WORKDIR /src
COPY . .
ARG SERVICE
ENV SERVICE=${SERVICE}
RUN ./gradlew :${SERVICE}-service:bootJar
CMD java -jar ${SERVICE}-service/build/libs/vet-${SERVICE}-1.0.0.jar
