#!/usr/bin/env bash
# ② 이미지 빌드·컨테이너 테스트를 WSL 2 Ubuntu 의 Docker Engine 에서 다시 한다. 단계마다 기록한다.
#   wsl -d Ubuntu -- bash /mnt/c/.../v2/wsl/stage2.sh
set -u
# WSL 의 배포판들은 네트워크를 함께 쓴다. Docker Desktop 의 로컬 쿠버네티스가 28080 을 쓰고 있어 28090 으로 연다 (②의 문제 장면)
export WEB_PORT=28090
SRC=/mnt/c/Users/junseo/Desktop/webserver/eks-rebuild-lab
W="$HOME/vet2-lab"
export CAP_DIR="$SRC/v2/_run/capture"
rsync -a --delete --exclude '_run/' "$SRC/v2/" "$W/v2/"
cd "$W"
. v2/tests/cap.sh
export DOCKER_BUILDKIT=1
C="docker compose -f v2/docker/compose.yaml --env-file v2/_run/secrets.env"

cap w2-01-ignore "② 빌드에서 빼는 파일 (.dockerignore)" bash -c 'for f in v2/docker/*.dockerignore; do echo "== $f"; grep -v "^#" "$f"; done'
cap w2-02-up "② 이미지 빌드와 컨테이너 6개 실행 (compose up --build --wait)" bash -c "$C up -d --build --wait 2>&1 | grep -vE '^ *#[0-9]+ (sha256|extracting|[0-9.]+ ?[kMG]?B)' | tail -40"
cap w2-03-images "② 만든 이미지: 크기와 플랫폼 (linux/amd64)" bash -c 'docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep -E "REPOSITORY|^vet2-(auth|clinic|reservation|web|db):"; echo; for i in vet2-auth:1.0.0 vet2-clinic:1.0.0 vet2-reservation:1.0.0 vet2-web:1.0.0 vet2-db:1.1.0; do docker image inspect $i --format "{{index .RepoTags 0}}  {{.Os}}/{{.Architecture}}"; done'
cap w2-04-ps "② 상태: docker compose ps (healthy)" $C ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
cap w2-05-user "② 컨테이너 안의 실행 사용자 (root 가 아님)" bash -c "for s in web auth clinic reservation mysql redis; do printf '%-12s ' \$s; $C exec -T \$s sh -c 'id'; done"
cap w2-06-env "② 설정은 환경 변수로 (값은 가림)" bash -c "$C exec -T clinic sh -c 'env | grep -E \"^(SPRING_|DB_|REDIS_|SERVER_|APP_)\" | sort'"
cap w2-07-logs "② 로그: docker compose logs (서비스 기동, web 접근 기록)" bash -c "$C logs --no-log-prefix --tail 4 clinic 2>&1 | cut -c1-170; echo ---; $C logs --tail 4 web 2>&1 | cut -c1-170"
set -a; . v2/_run/secrets.env; set +a
cap w2-08-scenario "② 시나리오 테스트 (웹 서버 :28090 을 거쳐)" node v2/tests/scenario.mjs --base-url http://localhost:$WEB_PORT --db-container v2-mysql-1
