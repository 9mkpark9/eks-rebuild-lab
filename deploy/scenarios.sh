#!/usr/bin/env bash
# WEB 계층 부하 테스트 시나리오 실행 + 데이터 수집 (문서 03장 ALB·Web Server 기준). 오토스케일링 없음(고정 WEB 2대).
# 요청은 nginx가 직접 응답하는 정적 HTML·CSS·JS·SVG와 SPA 묶음뿐이다 (/api 없음 → WAS·DB를 거치지 않음).
# 결과: results/web-<시각>/  progress.log, 단계별 로그, report-<프로필>.md(부하·비용), locust-<프로필>.txt
#
#   W-1 web02     기준선 = TC-02        40명 15분          정적 p95 300ms 미만, 분산 ±20%
#   W-2 webspike  스파이크 = TC-03~05   40→140명(30초)·140명 20분 유지·40명   CPU 평균 70% 미만, 메모리 80% 미만
#   W-3 web06     장애 조치 = TC-06 ②   40명 15분, 5분에 WEB-a nginx 중지 → 7분에 재시작   약 10초 안에 대상 제외, 이후 오류 없음
#   W-4 webstress 과부하               100→1000명(3분마다 +100), 대기 시간 0.2배   고정 2대의 한계 지점
# 합계 약 1시간 40분. 일부만: SKIP="web02 webspike" bash deploy/scenarios.sh
set -uo pipefail
cd "$(dirname "$0")/.."
A="bash deploy/aws.sh"
OUT="results/web-$(date +%Y%m%d-%H%M)"; mkdir -p "$OUT"
P="$OUT/progress.log"
say()  { echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$P"; }
skip() { [[ " ${SKIP:-} " == *" $1 "* ]]; }
step() { local n=$1; shift; say "> $n"; "$@" > "$OUT/$n.log" 2>&1; local e=$?; say "  $n 끝 (exit $e)"; return $e; }

running() { $A loadstatus "$1" 2>/dev/null | grep -o 'running: [0-9]*' | head -1 | awk '{print $2}'; }
wait_end() { # wait_end <프로필> <남은 초> : Locust 가 끝날 때까지 1분마다 확인
  local p=$1 sec=$2 t0 el n; t0=$(date +%s)
  while :; do
    sleep 60
    el=$(( $(date +%s) - t0 ))
    n=$(running "$p"); say "  $p 경과 $((el / 60))/$((sec / 60))분, locust 프로세스 ${n:-?}"
    if [ "$el" -gt 90 ] && [ "${n:-1}" = 0 ]; then break; fi
    if [ "$el" -gt $((sec + 600)) ]; then say "  시간 초과 → Locust 중지"; $A loadstop >/dev/null 2>&1; break; fi
  done
}
collect() { # collect <프로필> : 보고서·Locust 요약을 결과 폴더로
  local p=$1 r
  step "$p-report" $A report "$p"
  r=$(ls -t build/report-"$p"-*.md 2>/dev/null | head -1)
  [ -n "$r" ] && cp "$r" "$OUT/report-$p.md"
  cp "build/loadtest-$p-summary.txt" "$OUT/locust-$p.txt" 2>/dev/null
  grep -E '^- (한계|외부 ALB|WEB 대상)' "$OUT/report-$p.md" 2>/dev/null | sed "s/^/  [$p] /" | tee -a "$P"
}
run_test() { # run_test <프로필> <초>
  step "$1-loadtest" $A loadtest "$1" || { say "  $1 시작 실패 — 건너뜀 ($OUT/$1-loadtest.log)"; return 1; }
  wait_end "$1" "$2"
  collect "$1"
}

say "WEB 시나리오 시작 → $OUT"
$A whoami 2>&1 | head -1 | tee -a "$P"
step status-before $A status
if ! step locustsetup $A locustsetup; then   # 설치가 안 되면 모든 시나리오가 실패하므로 여기서 멈춘다
  say "Locust 설치 실패 — 중단 ($OUT/locustsetup.log)"; exit 1
fi

skip web02    || run_test web02 900
skip webspike || run_test webspike 1860

if ! skip web06; then
  if step web06-loadtest $A loadtest web06; then
    sleep 300; step web06-1-web-a-stop  $A fault web-a stop;  grep TARGET_CHANGE "$OUT/web06-1-web-a-stop.log"  | tee -a "$P"
    sleep 100; step web06-2-web-a-start $A fault web-a start; grep TARGET_CHANGE "$OUT/web06-2-web-a-start.log" | tee -a "$P"
    wait_end web06 480
    collect web06
  else
    say "  web06 시작 실패 — 건너뜀"
  fi
fi

skip webstress || run_test webstress 1800

step status-after $A status
say "완료 → $OUT"
