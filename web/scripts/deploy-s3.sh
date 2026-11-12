#!/usr/bin/env bash
# 소개 페이지 미리보기를 S3 정적 웹사이트로 배포한다.
# 사용: npm run build:s3 && bash scripts/deploy-s3.sh <버킷 이름> [리전]
# 버킷이 없으면 만들고, 객체 읽기만 공개한다(ACL은 계속 막아 둔다).
set -euo pipefail

BUCKET=${1:?버킷 이름을 넣어 주세요}
REGION=${2:-ap-northeast-2}
AWS=${AWS:-aws}
DIR="$(cd "$(dirname "$0")/.." && pwd)/dist/s3"
[ -d "$DIR" ] || { echo "dist/s3 가 없습니다. 먼저 npm run build:s3 를 실행하세요."; exit 1; }

# ── 1. 버킷 · 공개 읽기 · 웹사이트 설정 ─────────────────────────────
if ! "$AWS" s3api head-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null 2>&1; then
  "$AWS" s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
  echo "버킷 생성: $BUCKET"
fi
"$AWS" s3api put-public-access-block --bucket "$BUCKET" --region "$REGION" --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false"
"$AWS" s3api put-bucket-policy --bucket "$BUCKET" --region "$REGION" --policy \
  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"PublicRead\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::$BUCKET/*\"}]}"
# 없는 /app/* 주소는 미리보기 안내(/app/)로 보낸다. 목록 권한이 없으면 S3는 없는 키에 403을 주므로 둘 다 건다.
"$AWS" s3api put-bucket-website --bucket "$BUCKET" --region "$REGION" --website-configuration '{
  "IndexDocument": {"Suffix": "index.html"},
  "ErrorDocument": {"Key": "404.html"},
  "RoutingRules": [
    {"Condition": {"KeyPrefixEquals": "app/", "HttpErrorCodeReturnedEquals": "403"}, "Redirect": {"ReplaceKeyWith": "app/", "HttpRedirectCode": "302"}},
    {"Condition": {"KeyPrefixEquals": "app/", "HttpErrorCodeReturnedEquals": "404"}, "Redirect": {"ReplaceKeyWith": "app/", "HttpRedirectCode": "302"}}
  ]
}'

# ── 2. 업로드 (형식을 직접 지정: Windows에서 확장자 추측이 틀리는 경우가 있다) ──
up() { # up <포함 패턴> <Content-Type> <Cache-Control>
  "$AWS" s3 sync "$DIR" "s3://$BUCKET" --region "$REGION" --only-show-errors \
    --exclude "*" --include "$1" --exclude "api/*" --content-type "$2" --cache-control "$3"
}
up "*.html" "text/html; charset=utf-8" "no-cache"
up "*.css"  "text/css; charset=utf-8" "public, max-age=3600"
up "*.js"   "text/javascript; charset=utf-8" "public, max-age=3600"
up "*.svg"  "image/svg+xml" "public, max-age=86400"

# /about 처럼 확장자 없는 주소 (nginx의 try_files $uri.html 대신)
for page in about doctors services notices; do
  "$AWS" s3 cp "$DIR/$page" "s3://$BUCKET/$page" --region "$REGION" --only-show-errors \
    --content-type "text/html; charset=utf-8" --cache-control "no-cache"
done

# 공지 스냅숏: api/notices.json → /api/notices, api/notices/5.json → /api/notices/5
"$AWS" s3 cp "$DIR/api/notices.json" "s3://$BUCKET/api/notices" --region "$REGION" --only-show-errors \
  --content-type "application/json; charset=utf-8" --cache-control "no-cache"
for f in "$DIR"/api/notices/*.json; do
  id=$(basename "$f" .json)
  "$AWS" s3 cp "$f" "s3://$BUCKET/api/notices/$id" --region "$REGION" --only-show-errors \
    --content-type "application/json; charset=utf-8" --cache-control "no-cache"
done

echo "완료: http://$BUCKET.s3-website.$REGION.amazonaws.com"
