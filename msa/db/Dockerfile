# vet-db 이미지: MySQL 8.4 + 스키마 + "뜨는 날 기준" 시드 + 서비스별 스키마·계정·뷰
# 빌드 위치는 저장소 루트다 (db/ 와 web/clinic.config.json 이 필요하다):
#   docker build -f msa/db/Dockerfile -t ghcr.io/9mkpark9/vet-db:1.0.0 .
#
# 두 가지로 쓴다.
#   1) DB 서버로 (compose, dev): 데이터 폴더가 비어 있으면 초기화 절차가 vet-provision 을 실행한다.
#      볼륨을 붙이지 않으므로 컨테이너(Pod)가 다시 뜰 때마다 초기 상태로 돌아간다. 의도한 동작이다.
#   2) 초기화 도구로 (prod 의 RDS): 같은 이미지를 `vet-provision` 명령으로 실행해 바깥 DB 를 초기화한다.

# 시드 생성기(db/gen-seed.mjs)는 Node 로 돈다. 실행 파일 하나만 가져온다.
FROM node:22-slim AS node

FROM mysql:8.4
COPY --from=node /usr/local/bin/node /usr/local/bin/node
RUN node --version

# gen-seed.mjs 는 자기 위치의 ../web/clinic.config.json 을 읽는다. 저장소와 같은 배치로 둔다.
COPY db/schema.sql db/gen-seed.mjs msa/db/split.sql msa/db/grants.sql /opt/vet/db/
COPY web/clinic.config.json /opt/vet/web/
COPY msa/db/vet.cnf /etc/mysql/conf.d/vet.cnf
COPY msa/db/vet-provision.sh /usr/local/bin/vet-provision
COPY msa/db/vet-sql.sh /usr/local/bin/vet-sql
COPY msa/db/10-vet-init.sh /docker-entrypoint-initdb.d/10-vet-init.sh
# Windows 에서 체크아웃하면 CRLF 일 수 있다. 설정 파일이 누구나 쓸 수 있으면 MySQL 이 무시하므로 권한도 맞춘다.
RUN sed -i 's/\r$//' /docker-entrypoint-initdb.d/10-vet-init.sh /etc/mysql/conf.d/vet.cnf \
      /usr/local/bin/vet-provision /usr/local/bin/vet-sql /opt/vet/db/split.sql /opt/vet/db/grants.sql \
 && chmod 0644 /etc/mysql/conf.d/vet.cnf /docker-entrypoint-initdb.d/10-vet-init.sh \
 && chmod 0755 /usr/local/bin/vet-provision /usr/local/bin/vet-sql

# 시드의 "오늘"과 서버의 NOW() 를 병원 현지 시각으로 맞춘다
ENV TZ=Asia/Seoul
