#!/usr/bin/env bash
# ② 선택 과제 "빌드 최적화": 방법을 하나씩 더하며(A → E) 같은 조건에서 잰다. WSL 2 Ubuntu 의 Docker Engine.
#   wsl -d Ubuntu -- bash /mnt/c/.../v2/wsl/stage2-bench.sh
# 단계마다:
#   1) 처음 빌드: --no-cache (레이어 캐시를 쓰지 않는다)
#   2) 소스 한 줄(주석)을 바꾸고 다시 빌드: 무엇이 재사용(CACHED)되고 몇 초 걸리는지
#   3) 이미지 크기, 보낸 빌드 컨텍스트 크기
# 빌드 캐시 전체를 지우는 명령(docker builder prune)은 쓰지 않는다. 이 PC 의 다른 캐시까지 지운다 (② 9장).
set -u
SRC=/mnt/c/Users/junseo/Desktop/webserver/eks-rebuild-lab
W="$HOME/vet2-lab"
export CAP_DIR="$SRC/v2/_run/capture"
rsync -a --delete --exclude '_run/' "$SRC/v2/" "$W/v2/"
cd "$W"
. v2/tests/cap.sh
export DOCKER_BUILDKIT=1
F=$(find msa/auth-service/src/main/java -name 'AuthServiceApplication.java' | head -1)
SUM="$CAP_DIR/opt-build-bench-summary.raw"; : > "$SUM"

desc() { case "$1" in A) echo "v0 그대로";; B) echo "+ .dockerignore";; C) echo "+ 멀티스테이지 (JRE)";; D) echo "+ JRE alpine";; E) echo "+ Gradle 캐시 마운트";; esac; }
build() { # build <단계> <로그 파일> [추가 인자...]
    local x="$1" log="$2"; shift 2
    local t0=$(date +%s.%N)
    docker build --progress=plain "$@" -f "v2/docker/bench/$x.Dockerfile" --build-arg SERVICE=auth -t "vet2-bench:$x" msa > "$log" 2>&1
    local rc=$?
    echo "$(echo "$(date +%s.%N) - $t0" | bc | xargs printf '%.1f')"; return $rc
}

for x in A B C D E; do
    echo "■ $x $(desc $x)"
    git checkout -q -- "$F"
    cold=$(build $x /tmp/bench-$x-cold.log --no-cache) || { echo "빌드 실패 $x"; tail -20 /tmp/bench-$x-cold.log; exit 1; }
    ctx=$(grep -o 'transferring context: [0-9.]*[kMG]*B' /tmp/bench-$x-cold.log | tail -1 | awk '{print $3}')
    size=$(docker image inspect "vet2-bench:$x" --format '{{.Size}}' | awk '{printf "%.0fMB", $1/1000/1000}')
    echo "    // bench $(date +%s)" >> "$F"          # 소스 한 줄 변경
    re=$(build $x /tmp/bench-$x-re.log)
    cached=$(grep -c ' CACHED' /tmp/bench-$x-re.log)
    git checkout -q -- "$F"
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$x" "$(desc $x)" "$ctx" "$size" "$cold" "$re" "$cached" >> "$SUM"
    # 재빌드 기록: 단계 이름과 CACHED 줄만 남긴다 (나머지는 원본 로그)
    { echo "#title: ② 빌드 최적화 $x ($(desc $x)): 소스 한 줄 수정 뒤 재빌드"; echo "#env: $CAP_ENV · $(date '+%Y-%m-%d %H:%M')";
      echo "\$ echo '// 주석 한 줄' >> AuthServiceApplication.java && docker build --progress=plain -f v2/docker/bench/$x.Dockerfile --build-arg SERVICE=auth msa";
      grep -E '^#[0-9]+ \[|CACHED|DONE [0-9.]+s$|transferring context' /tmp/bench-$x-re.log | grep -vE '^#[0-9]+ \[internal\] load (metadata|\.dockerignore)' | sed 's/^#[0-9]* //' | uniq | head -40
      echo "재빌드 ${re}초, 재사용된 단계(CACHED) ${cached}개"; } | _cap_mask > "$CAP_DIR/opt-build-$x-rebuild.txt"
    echo "    컨텍스트 $ctx, 이미지 $size, 처음 빌드 ${cold}초, 재빌드 ${re}초, CACHED $cached"
done

{ echo "#title: ② 선택 과제 빌드 최적화: 방법을 하나씩 더했을 때 (auth 서비스)"; echo "#env: $CAP_ENV · $(date '+%Y-%m-%d %H:%M') · 처음 빌드는 --no-cache"
  printf '%-3s %-22s %12s %10s %14s %18s %8s\n' "단계" "더한 방법" "보낸 컨텍스트" "이미지" "처음 빌드(초)" "소스 수정 뒤(초)" "CACHED"
  while IFS='|' read -r a b c d e f g; do printf '%-3s %-22s %12s %10s %14s %18s %8s\n' "$a" "$b" "$c" "$d" "$e" "$f" "$g"; done < "$SUM"; } > "$CAP_DIR/opt-build-bench.txt"
cat "$CAP_DIR/opt-build-bench.txt"
