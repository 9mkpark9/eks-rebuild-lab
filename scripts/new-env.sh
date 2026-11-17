#!/usr/bin/env bash
# .env.example 을 복사해 비밀번호를 무작위 값으로 채운 .env 를 만든다 (docker compose 가 읽는다).
# 이미 .env 가 있으면 건드리지 않는다. 만든 값은 화면에 출력하지 않는다.
#   scripts/new-env.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
example="$ROOT/.env.example"
target="$ROOT/.env"

if [ -f "$target" ]; then
    echo '.env 가 이미 있습니다. 바꾸지 않았습니다.'
    exit 0
fi

# 무작위 36자 (16진수)
new_secret() { head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

umask 077
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
        DB_ROOT_PASSWORD=|DB_AUTH_PASSWORD=|DB_CLINIC_PASSWORD=|DB_RESERVATION_PASSWORD=|REDIS_PASSWORD=)
            printf '%s%s\n' "$line" "$(new_secret)" ;;
        *)  printf '%s\n' "$line" ;;
    esac
done < "$example" > "$target"

echo '.env 를 만들었습니다 (비밀번호 5개를 무작위로 채움).'
