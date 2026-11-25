#!/usr/bin/env bash
# v2/_run/secrets.env 의 비밀번호를 환경 변수로 불러온 뒤 주어진 명령을 실행한다. 비밀번호는 화면에 나오지 않는다.
# (화면 캡처 때 bash -v 가 읽는 줄을 모두 보여 주므로, 비밀번호 파일을 명령 줄에서 직접 불러오지 않는다)
#   v2/tests/with-secrets.sh node v2/tests/scenario.mjs ...
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
set -a; . "$ROOT/v2/_run/secrets.env"; set +a
exec "$@"
