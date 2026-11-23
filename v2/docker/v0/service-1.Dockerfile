# v0-1 — v0 에 gradlew 줄바꿈 고치기만 더함. 빌드 위치: msa/
#   docker build -f v2/docker/v0/service-1.Dockerfile --build-arg SERVICE=auth -t vet2-auth:v0 msa
FROM eclipse-temurin:21-jdk
WORKDIR /src
COPY . .
ARG SERVICE
ENV SERVICE=${SERVICE}
RUN sed -i 's/\r$//' gradlew && ./gradlew :${SERVICE}-service:bootJar
CMD java -jar ${SERVICE}-service/build/libs/vet-${SERVICE}-1.0.0.jar
