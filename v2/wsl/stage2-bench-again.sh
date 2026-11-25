#!/usr/bin/env bash
# 빌드 최적화 사다리의 "소스 수정 뒤 재빌드" 시간을 한 번 더 잰다 (측정값의 흔들림 확인용). 결과는 opt-build-bench-2.txt
set -u
SRC=/mnt/c/Users/junseo/Desktop/webserver/eks-rebuild-lab
cd "$HOME/vet2-lab"; export DOCKER_BUILDKIT=1
F=$(find msa/auth-service/src/main/java -name 'AuthServiceApplication.java' | head -1)
{ echo "#title: ② 빌드 최적화: 소스 한 줄 수정 뒤 재빌드 시간, 두 번째 측정"; echo "#env: WSL 2 Ubuntu · $(date '+%Y-%m-%d %H:%M')"
for x in A B C D E; do
    echo "    // bench2 $(date +%s)" >> "$F"
    t0=$(date +%s.%N)
    docker build -q -f "v2/docker/bench/$x.Dockerfile" --build-arg SERVICE=auth -t "vet2-bench:$x" msa > /dev/null 2>&1
    printf '%s  재빌드 %.1f초\n' "$x" "$(echo "$(date +%s.%N) - $t0" | bc)"
    git checkout -q -- "$F"
done; } | tee "$SRC/v2/_run/capture/opt-build-bench-2.txt"
