#!/usr/bin/env bash
# 3-Tier 동작 확인 — 외부 ALB 주소 하나로 WEB · 내부 ALB · WAS · RDS · ElastiCache 를 차례로 확인한다.
#
#   bash deploy/smoke-3tier.sh <외부 ALB DNS> [반복 횟수, 기본 20]
#   예) bash deploy/smoke-3tier.sh vet01-alb-ext-123456789.ap-northeast-2.elb.amazonaws.com
#
# 내 PC(Git Bash)에서 실행한다. 외부 ALB 보안 그룹을 내 IP/32 로 좁혀 두었다면 내 PC에서만 된다.
# 테스트 계정은 임시 데이터 계정이다: LOGIN_ID(기본 admin1) / LOGIN_PW(기본 test-only)
# 로그인은 딱 1번만 시도한다 (5번 실패하면 1분 잠금).
set -uo pipefail

HOST=${1:?사용법: bash deploy/smoke-3tier.sh <외부 ALB DNS> [반복 횟수]}
N=${2:-20}
BASE="http://${HOST#http://}"; BASE=${BASE%/}
LOGIN_ID=${LOGIN_ID:-admin1}
LOGIN_PW=${LOGIN_PW:-test-only}
TMP=$(mktemp); JAR="$TMP.jar"
trap 'rm -f "$TMP" "$TMP".*' EXIT
pass=0; fail=0; warn=0
ok() { printf '  [통과] %s\n' "$*"; pass=$((pass+1)); }
ng() { printf '  [실패] %s\n' "$*"; fail=$((fail+1)); }
wn() { printf '  [주의] %s\n' "$*"; warn=$((warn+1)); }
title() { printf '\n%s\n' "$*"; }

# req <메서드> <경로> [curl 인자...] → "상태코드 걸린초" 출력, 헤더는 $TMP.head, 본문은 $TMP.body
req() {
  local m=$1 p=$2; shift 2
  : > "$TMP.head"; : > "$TMP.body"   # 연결 실패 때 이전 응답 헤더가 남지 않게
  curl -s -m 10 -o "$TMP.body" -D "$TMP.head" -w '%{http_code} %{time_total}' -X "$m" "$@" "$BASE$p" 2>/dev/null || echo "000 0"
}
hdr() { grep -i "^$1:" "$TMP.head" | head -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//'; }

# spread <이름> : 표준 입력의 값(한 줄에 하나)을 세어 대수와 ±20% 안에 드는지 판정
spread() {
  local what=$1 counts nodes
  counts=$(grep -v '^$' | sort | uniq -c | sort -rn)
  if [ -z "$counts" ]; then wn "$what 헤더가 하나도 없어 분산을 셀 수 없다"; return; fi
  echo "$counts" | sed 's/^/        /'
  nodes=$(echo "$counts" | wc -l | tr -d ' ')
  if [ "$nodes" -lt 2 ]; then ng "$what: 1대에만 몰림 (대상 그룹에서 healthy 대수 확인)"; return; fi
  if echo "$counts" | awk -v n="$nodes" '{c[NR]=$1; s+=$1} END {m=s/n; for(i=1;i<=NR;i++) if (c[i] < m*0.8 || c[i] > m*1.2) exit 1}'; then
    ok "$what: ${nodes}대에 고르게 분산 (모두 평균의 ±20% 이내)"
  else
    wn "$what: ${nodes}대에 나뉘었지만 ±20%를 벗어난 대상이 있다 (횟수가 적으면 흔들린다. 반복 횟수를 늘려 다시)"
  fi
}

echo "3-Tier 동작 확인: $BASE (반복 $N회)"

title "[1] 외부 ALB → WEB : /health"
read -r code t < <(req GET /health)
if [ "$code" = 200 ]; then ok "200 응답 (${t}s) — 외부 ALB 리스너, WEB 보안 그룹, WEB 서버가 정상"; else ng "/health 응답 $code (000이면 외부 ALB 보안 그룹·DNS 확인, 502/503이면 대상 그룹 healthy 확인)"; fi
node=$(hdr X-Web-Node)
if [ "$code" != 200 ]; then wn "응답이 없어 헤더 확인을 건너뜀"
elif [ -n "$node" ]; then ok "X-Web-Node: $node"; else wn "X-Web-Node 헤더 없음 — WEB 설정에 분산 확인 헤더가 빠졌다 (아래 [4] 분산 측정 불가)"; fi

title "[2] 정적 페이지는 WEB에서 끝나는가 : /"
read -r code t < <(req GET /)
if [ "$code" = 200 ]; then ok "200 응답 (${t}s)"; else ng "/ 응답 $code"; fi
if [ "$code" != 200 ]; then :
elif [ -z "$(hdr X-Served-By)" ]; then ok "X-Served-By 없음 — WAS를 거치지 않았다"; else ng "정적 페이지에 X-Served-By 가 붙음 — 정적 요청까지 WAS로 넘어가고 있다"; fi

title "[3] /api 는 내부 ALB → WAS → RDS 까지 가는가 : /api/notices"
read -r code t < <(req GET /api/notices)
was=$(hdr X-Served-By)
if [ "$code" = 200 ]; then ok "200 응답 (${t}s)"; else ng "/api/notices 응답 $code (502/504면 WEB→내부 ALB 연결: 프록시 주소·포트, 내부 ALB 보안 그룹 확인)"; fi
if [ "$code" != 200 ]; then :
elif [ -n "$was" ]; then ok "X-Served-By: $was — 내부 ALB를 거쳐 WAS가 처리"; else ng "X-Served-By 없음 — WAS까지 가지 않았다"; fi
if [ "$code" != 200 ]; then :
elif head -c 1 "$TMP.body" | grep -q '\['; then ok "공지 목록 JSON 수신 — WAS가 RDS(vet_app 계정)에서 읽었다"; else ng "응답 본문이 JSON 목록이 아니다: $(head -c 120 "$TMP.body")"; fi

title "[4] 외부 ALB의 WEB 분산 : / ${N}회"
spread "WEB" < <(for _ in $(seq 1 "$N"); do req GET / >/dev/null; hdr X-Web-Node; done)

title "[5] 내부 ALB의 WAS 분산 : /api/notices ${N}회"
spread "WAS" < <(for _ in $(seq 1 "$N"); do req GET /api/notices >/dev/null; hdr X-Served-By; done)

title "[6] 세션 공유 (ElastiCache) : 로그인 1번 → /api/auth/me ${N}회"
read -r code t < <(req POST /api/auth/login -c "$JAR" -H 'Content-Type: application/json' \
  --data "{\"loginId\":\"$LOGIN_ID\",\"password\":\"$LOGIN_PW\"}")
if [ "$code" = 200 ] && grep -q SESSION "$JAR" 2>/dev/null; then
  ok "로그인 200, SESSION 쿠키 받음 (${t}s, 처리 WAS $(hdr X-Served-By))"
  okcnt=0; : > "$TMP.me"
  for _ in $(seq 1 "$N"); do
    read -r c _ < <(req GET /api/auth/me -b "$JAR")
    [ "$c" = 200 ] && okcnt=$((okcnt+1))
    hdr X-Served-By >> "$TMP.me"
  done
  served=$(sort -u "$TMP.me" | grep -vc '^$')
  if [ "$okcnt" = "$N" ] && [ "$served" -ge 2 ]; then ok "${N}회 모두 로그인 유지, WAS ${served}대를 오갔다 — 고정 세션 없이 세션이 공유된다"
  elif [ "$okcnt" = "$N" ]; then wn "${N}회 모두 로그인 유지, 그러나 WAS 1대만 응답 — 세션 공유를 확인하려면 WAS 2대가 healthy 여야 한다"
  else ng "${N}회 중 $((N-okcnt))회 로그인 풀림 (401) — WAS가 ElastiCache에서 세션을 못 찾는다 (Redis 주소·AUTH·보안 그룹 6379 확인)"; fi
  req POST /api/auth/logout -b "$JAR" >/dev/null
elif [ "$code" = 401 ] || [ "$code" = 429 ]; then
  wn "로그인 $code — 계정·비밀번호를 확인 (LOGIN_ID, LOGIN_PW). 429면 1분 뒤 다시"
else
  ng "로그인 응답 $code — WAS가 ElastiCache에 세션을 쓰지 못하면 500이 난다 (Redis 연결 확인)"
fi

printf '\n결과: 통과 %d · 주의 %d · 실패 %d\n' "$pass" "$warn" "$fail"
[ "$fail" -eq 0 ]
