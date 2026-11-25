#!/usr/bin/env bash
set -u
SRC=/mnt/c/Users/junseo/Desktop/webserver/eks-rebuild-lab
export CAP_DIR="$SRC/v2/_run/capture" WEB_PORT=28090
cd "$HOME/vet2-lab"; . v2/tests/cap.sh
C="docker compose -f v2/docker/compose.yaml --env-file v2/_run/secrets.env"
cap w2-03-images "② 만든 이미지: 크기와 플랫폼 (linux/amd64)" bash -c 'docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep -E "REPOSITORY|^vet2-(auth|clinic|reservation|web|db):1.0.0"; echo; for i in vet2-auth:1.0.0 vet2-clinic:1.0.0 vet2-reservation:1.0.0 vet2-web:1.0.0 vet2-db:1.0.0; do docker image inspect $i --format "{{index .RepoTags 0}}  {{.Os}}/{{.Architecture}}"; done'
# docker exec 는 기본이 root 다. 실제로 서비스를 돌리는 1번 프로세스의 사용자를 본다
cap w2-05-user "② 컨테이너의 실행 사용자 (1번 프로세스, root 가 아님)" bash -c "for s in web auth clinic reservation mysql redis; do id=\$(docker inspect -f '{{.State.Pid}}' v2-\$s-1); printf '%-12s 프로세스 %-10s uid=%s\n' \$s \"\$(cat /proc/\$id/comm 2>/dev/null || sudo -n cat /proc/\$id/comm)\" \"\$(ps -o uid= -p \$id | tr -d ' ')\"; done; echo; echo '(참고) mysql 컨테이너의 1번 프로세스:'; $C exec -T mysql sh -c 'ps -o user,pid,comm 2>/dev/null || cat /proc/1/status | grep -E \"^(Name|Uid)\"'"
