# db 이미지: MySQL 8.4 + 처음 뜰 때 스키마, 시드, 서비스 계정을 스스로 만든다. 빌드 위치: 저장소 루트
#   docker build -f v2/docker/db.Dockerfile -t vet2-db:1.0.0 .
# 초기화는 데이터 폴더가 비어 있을 때 한 번만 돈다. 볼륨을 붙이면 그 뒤로는 있는 데이터를 그대로 쓴다.

# 시드는 이미지를 만들 때가 아니라 DB 가 처음 뜨는 날을 기준으로 만든다 (문제 C-10).
# 시드 생성기가 Node 로 돌기 때문에 실행 파일 하나만 가져온다.
FROM node:22-slim AS node

FROM mysql:8.4
COPY --from=node /usr/local/bin/node /usr/local/bin/node
RUN node --version
# 시드 생성기는 자기 위치의 ../web/clinic.config.json 을 읽는다. 저장소와 같은 배치로 둔다.
COPY db/schema.sql db/gen-seed.mjs msa/db/split.sql msa/db/grants.sql /opt/vet/db/
COPY web/clinic.config.json /opt/vet/web/
# 공식 이미지는 이 폴더의 스크립트를 처음 뜰 때 실행한다
COPY v2/docker/db/10-init.sh /docker-entrypoint-initdb.d/10-init.sh
