# v0 — 가장 단순한 형태. 빌드 위치: 저장소 루트
#   docker build -f v2/docker/v0/web.Dockerfile -t vet2-web:v0 .
FROM node:22 AS build
WORKDIR /web
COPY web/ .
RUN npm ci && npm run build

FROM httpd:2.4-alpine
COPY --from=build /web/dist/site /usr/local/apache2/htdocs
COPY --from=build /web/dist/app  /usr/local/apache2/htdocs/app
COPY v2/docker/v0/vet.conf /usr/local/apache2/conf/extra/vet.conf
# 기본 설정에서 꺼져 있는 모듈 세 개를 켜고, 우리 설정을 끝에 붙인다
RUN sed -i -e 's/^#\(LoadModule proxy_module \)/\1/' -e 's/^#\(LoadModule proxy_http_module \)/\1/' \
           -e 's/^#\(LoadModule rewrite_module \)/\1/' conf/httpd.conf \
 && echo 'Include conf/extra/vet.conf' >> conf/httpd.conf \
 && printf 'ok' > htdocs/health
