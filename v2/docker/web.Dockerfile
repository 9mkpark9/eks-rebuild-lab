# web 이미지: 화면(정적 파일) + /api 를 세 서비스로 나눠 보내는 Apache httpd. 빌드 위치: 저장소 루트
#   docker build -f v2/docker/web.Dockerfile -t vet2-web:1.0.0 .

# ── 1) 화면 빌드 ──────────────────────────────────────────────────────
FROM node:22-alpine AS build
WORKDIR /web
# 의존성 목록만 먼저 복사한다. 화면 소스만 바뀌면 npm ci 를 다시 하지 않는다.
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY web/ .
RUN npm run build

# ── 2) 실행 ───────────────────────────────────────────────────────────
FROM httpd:2.4-alpine
COPY v2/docker/web/httpd.conf /usr/local/apache2/conf/httpd.conf
COPY --from=build /web/dist/site /usr/local/apache2/htdocs
COPY --from=build /web/dist/app  /usr/local/apache2/htdocs/app
RUN printf 'ok' > /usr/local/apache2/htdocs/health
ARG VERSION=1.0.0
ENV WEB_VERSION=${VERSION}
# www-data. 번호로 적는다. 기본 설정은 주 프로세스를 root 로 띄운다 (문제 C-5)
USER 82:82
EXPOSE 8080
# 종료 신호는 공식 이미지가 SIGWINCH 로 정해 두었다: 처리 중인 요청을 마치고 내려간다
