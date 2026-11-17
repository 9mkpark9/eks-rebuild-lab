#!/usr/bin/env bash
# ② ④ — 빌드해 둔 이미지에 태그를 붙여 레지스트리에 올린다(push).
# 이미지는 먼저 docker compose build 로 만들어 둔다 (web 의 nginx 판은 WEB_SERVER=nginx docker compose build web).
#
#   레지스트리에 (Docker Hub, ghcr.io 등. 먼저 docker login 을 직접 해 둔다)
#     scripts/push-images.sh --registry docker.io/<내 아이디>
#     scripts/push-images.sh --registry ghcr.io/9mkpark9
#
#   ECR 에 (저장소가 없으면 만들고, 로그인하고, 올린다. aws CLI 가 필요하다)
#     scripts/push-images.sh --ecr
#
#   scripts/push-images.sh --ecr --list      ECR 에 올라가 있는 것을 본다
#   scripts/push-images.sh --ecr --delete    ECR 저장소를 지운다 (자원 정리)
#
# --version V   올릴 버전 (기본: .env 의 VERSION, 없으면 1.0.0)
# --dry-run     올리지 않고 무엇을 올릴지만 보여 준다
#
# 올리기 전에 이미지가 linux/amd64 인지 확인한다. EKS 의 노드가 받을 수 있어야 한다.
# ECR 주소에는 AWS 계정 번호가 들어 있다. 화면에는 가려서 출력한다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="ghcr.io/9mkpark9"       # compose.yaml 이 붙이는 이미지 이름의 앞부분
REGISTRY=""
ECR=0
MODE="push"
DRY=0
VERSION=""

while [ $# -gt 0 ]; do
    case "$1" in
        --registry) REGISTRY="${2%/}"; shift 2 ;;
        --ecr)      ECR=1; shift ;;
        --version)  VERSION="$2"; shift 2 ;;
        --dry-run)  DRY=1; shift ;;
        --list)     MODE="list"; shift ;;
        --delete)   MODE="delete"; shift ;;
        -h|--help)  sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "모르는 옵션: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$VERSION" ]; then
    VERSION=1.0.0
    if [ -f "$ROOT/.env" ]; then
        v=$(grep -E '^VERSION=' "$ROOT/.env" | head -1 | cut -d= -f2 | tr -d '\r')
        [ -n "$v" ] && VERSION="$v"
    fi
fi

REPOS="vet-web vet-auth vet-clinic vet-reservation vet-db"
# 이름:태그 목록. web 은 웹 서버별로 태그가 다르다.
IMAGES="vet-auth:$VERSION vet-clinic:$VERSION vet-reservation:$VERSION vet-db:$VERSION vet-web:$VERSION-apache vet-web:$VERSION-nginx"

# 계정 번호(숫자 12자리)를 가린다
mask() { sed -E 's/[0-9]{12}(\.dkr\.ecr\.)/************\1/g'; }

if [ "$ECR" = 1 ]; then
    region="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
    [ -n "$region" ] || { echo '리전을 알 수 없습니다. AWS_REGION 을 지정하세요.' >&2; exit 1; }
    account="$(aws sts get-caller-identity --query Account --output text | tr -d '\r')"
    [ -n "$account" ] || { echo 'AWS 계정을 읽지 못했습니다. aws configure 를 확인하세요.' >&2; exit 1; }
    REGISTRY="$account.dkr.ecr.$region.amazonaws.com"

    if [ "$MODE" = list ]; then
        for repo in $REPOS; do
            tags=$(aws ecr describe-images --region "$region" --repository-name "$repo" \
                     --query 'imageDetails[].imageTags[]' --output text 2>/dev/null | tr -d '\r' || true)
            echo "$repo: ${tags:-(없음)}"
        done
        exit 0
    fi
    if [ "$MODE" = delete ]; then
        for repo in $REPOS; do
            if aws ecr delete-repository --region "$region" --repository-name "$repo" --force >/dev/null 2>&1; then echo "지웠다: $repo"
            else echo "없거나 지우지 못했다: $repo"; fi
        done
        exit 0
    fi
fi

[ "$MODE" = push ] || { echo '--list 와 --delete 는 --ecr 와 함께 쓴다.' >&2; exit 2; }
[ -n "$REGISTRY" ] || { echo '--registry <주소> 또는 --ecr 를 준다. (--help)' >&2; exit 2; }

echo "올릴 곳: $(printf '%s' "$REGISTRY" | mask)   버전: $VERSION"

# 1) 올릴 이미지가 있는지, linux/amd64 인지 확인한다
todo=""
for image in $IMAGES; do
    src="$SOURCE/$image"
    if ! docker image inspect "$src" >/dev/null 2>&1; then
        case "$image" in
            vet-web:*-nginx) echo "건너뜀: $src (만들지 않았다. nginx 판이 필요하면 WEB_SERVER=nginx docker compose build web)"; continue ;;
            *) echo "이미지가 없다: $src — 먼저 docker compose build 를 실행한다." >&2; exit 1 ;;
        esac
    fi
    platform=$(docker image inspect "$src" --format '{{.Os}}/{{.Architecture}}')
    size=$(docker image inspect "$src" --format '{{.Size}}' | awk '{ printf "%.0fMB", $1 / 1000000 }')
    echo "  $image  $platform  $size"
    [ "$platform" = linux/amd64 ] || { echo "linux/amd64 가 아니다: $src ($platform). --platform linux/amd64 로 다시 빌드한다." >&2; exit 1; }
    todo="$todo $image"
done

if [ "$DRY" = 1 ]; then echo '(--dry-run: 올리지 않았다)'; exit 0; fi

# 2) ECR 이면 저장소를 만들고 로그인한다
if [ "$ECR" = 1 ]; then
    for repo in $REPOS; do
        if ! aws ecr describe-repositories --region "$region" --repository-names "$repo" >/dev/null 2>&1; then
            aws ecr create-repository --region "$region" --repository-name "$repo" >/dev/null
            echo "ECR 저장소를 만들었다: $repo"
        fi
    done
    # 로그인 토큰은 화면에 나오지 않고 docker 로 바로 넘어간다
    aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null
    echo 'ECR 에 로그인했다.'
fi

# 3) 태그를 붙이고 올린다
for image in $todo; do
    src="$SOURCE/$image"; dst="$REGISTRY/$image"
    [ "$src" = "$dst" ] || docker tag "$src" "$dst"
    if out=$(docker push "$dst" 2>&1); then
        digest=$(printf '%s\n' "$out" | grep -oE 'sha256:[0-9a-f]{64}' | tail -1)
        echo "[올림] $(printf '%s' "$dst" | mask)  ${digest:0:19}…"
    else
        printf '%s\n' "$out" | tail -5 | mask >&2
        echo "[실패] $(printf '%s' "$dst" | mask) — 로그인(docker login)과 저장소 이름을 확인한다" >&2
        exit 1
    fi
done
echo '끝.'
