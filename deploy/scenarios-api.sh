#!/usr/bin/env bash
# 코드(WAS 예약 API) 부하 테스트 시나리오 실행 + 데이터 수집 — 문서 7장 TC-02~07, 부록 A 의 locustfile 사용자 그대로.
# 방문자(소개·공지) · 보호자(로그인 → 슬롯 조회 → 예약 신청·30% 변경·10% 취소) · 이벤트 보호자(예방접종 앞 시간 경쟁) · 간호사(조회·승인)
# 결과: results/api-<시각>/  progress.log, report-<프로필>.md(부하·비용), locust-<프로필>.txt(API별 p95·409 코드별·WAS 노드별),
#       tc07-*.log(정합성), waslog-*.txt(구간별 WAS ERROR·Exception 요약, JVM 메모리)
#
#   C-1 tc02    기준선 TC-02            40명 15분                       API p95 (로그인·예약) 기준선, CPU·DB 연결
#   C-2 spike   TC-03~05                40→140명(30초)·30분 유지·40명   모든 API p95 1초 미만, WAS CPU 평균 70% 미만, 중복 예약 0
#   C-3 tc06    TC-06 ①③               40명 15분, 5분 WAS-a 앱 중지·7분 재시작 → 끝나고 RDS 강제 장애 조치
#   C-4 stress  과부하                   100→1000명(3분마다 +100), 대기 0.2배   WAS·DB 한계 지점
#   각 시나리오 전 DB 초기화, 후 TC-07 정합성 SQL.  합계 약 2시간 15분.  일부만: SKIP="spike tc06" bash deploy/scenarios-api.sh
set -uo pipefail
cd "$(dirname "$0")/.."
A="bash deploy/aws.sh"
OUT="results/api-$(date +%Y%m%d-%H%M)"; mkdir -p "$OUT"
P="$OUT/progress.log"
export MSYS_NO_PATHCONV=1 AWS_REGION=${AWS_REGION:-ap-northeast-2}
AWSCLI=${AWS:-aws}; command -v "$AWSCLI" >/dev/null 2>&1 || AWSCLI="/c/Program Files/Amazon/AWSCLIV2/aws.exe"
say()  { echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$P"; }
skip() { [[ " ${SKIP:-} " == *" $1 "* ]]; }
step() { local n=$1; shift; say "> $n"; "$@" > "$OUT/$n.log" 2>&1; local e=$?; say "  $n 끝 (exit $e)"; return $e; }
u8()   { iconv -f cp949 -t utf-8 "$1" > "$1.tmp" 2>/dev/null && mv "$1.tmp" "$1" || rm -f "$1.tmp"; }   # Windows aws.exe 의 CP949 출력 → UTF-8

running() { $A loadstatus "$1" 2>/dev/null | grep -o 'running: [0-9]*' | head -1 | awk '{print $2}'; }
wait_end() {
  local p=$1 sec=$2 t0 el n; t0=$(date +%s)
  while :; do
    sleep 60
    el=$(( $(date +%s) - t0 ))
    n=$(running "$p"); say "  $p 경과 $((el / 60))/$((sec / 60))분, locust 프로세스 ${n:-?}"
    if [ "$el" -gt 90 ] && [ "${n:-1}" = 0 ]; then break; fi
    if [ "$el" -gt $((sec + 600)) ]; then say "  시간 초과 → Locust 중지"; $A loadstop >/dev/null 2>&1; break; fi
  done
}
collect() {
  local p=$1 r
  step "$p-report" $A report "$p"
  r=$(ls -t build/report-"$p"-*.md 2>/dev/null | head -1)
  [ -n "$r" ] && cp "$r" "$OUT/report-$p.md"
  cp "build/loadtest-$p-summary.txt" "$OUT/locust-$p.txt" 2>/dev/null && u8 "$OUT/locust-$p.txt"
  grep -E '^- (한계|외부 ALB|RDS)' "$OUT/report-$p.md" 2>/dev/null | sed "s/^/  [$p] /" | tee -a "$P"
  grep -E '^http:' "$OUT/locust-$p.txt" 2>/dev/null | sed "s/^/  [$p] /" | tee -a "$P"
}

was_ids() {
  "$AWSCLI" cloudformation describe-stacks --stack-name vet01-was --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?starts_with(OutputKey,'WasInstance')].OutputValue" --output text | tr -d '\r'
}
waslog() { # waslog <이름> <KST 시작 YYYY-MM-DDTHH:MM> : 그 시각 이후 WAS 로그의 ERROR·WARN·Exception 을 종류별로 센다
  local name=$1 since=$2 id cid st f
  for id in $(was_ids); do
    cid=$("$AWSCLI" ssm send-command --region "$AWS_REGION" --instance-ids "$id" --document-name AWS-RunShellScript \
      --parameters "$(printf '{"commands":["%s"]}' "awk -v t=$since '\$1>=t' /var/log/vet/app.log > /tmp/seg.log; echo since: $since; echo lines: \$(wc -l < /tmp/seg.log); echo error_lines: \$(grep -c -E ' ERROR |Exception' /tmp/seg.log); echo --- top messages; grep -E ' ERROR | WARN |Exception' /tmp/seg.log | sed -E 's/^[^ ]+ +//; s/[0-9]+/N/g' | cut -c1-200 | sort | uniq -c | sort -rn | head -n 12; echo --- java rss_kb cpu_pct; ps -o rss=,pcpu= -C java")" \
      --query Command.CommandId --output text | tr -d '\r')
    for _ in $(seq 1 24); do
      st=$("$AWSCLI" ssm get-command-invocation --region "$AWS_REGION" --command-id "$cid" --instance-id "$id" --query Status --output text 2>/dev/null | tr -d '\r')
      case "$st" in Success|Failed|TimedOut|Cancelled) break ;; esac; sleep 5
    done
    f="$OUT/waslog-$name-$id.txt"
    "$AWSCLI" ssm get-command-invocation --region "$AWS_REGION" --command-id "$cid" --instance-id "$id" \
      --query "[StandardOutputContent,StandardErrorContent]" --output text > "$f" 2>&1; u8 "$f"
    say "  [$name] WAS $id $(grep -E '^error_lines:' "$f")"
  done
}
tc07() { step "tc07-$1" $A tc07; u8 "$OUT/tc07-$1.log"; grep TC07_RESULT "$OUT/tc07-$1.log" | sed "s/^/  [$1] /" | tee -a "$P"; }
run_test() { # run_test <프로필> <초>
  local since; since=$(date +%Y-%m-%dT%H:%M)
  step "dbinit-$1" $A dbinit
  step "$1-loadtest" $A loadtest "$1" || { say "  $1 시작 실패 — 건너뜀 ($OUT/$1-loadtest.log)"; return 1; }
  wait_end "$1" "$2"
  collect "$1"; tc07 "$1"; waslog "$1" "$since"
}

say "코드(API) 시나리오 시작 → $OUT"
$A whoami 2>&1 | head -1 | tee -a "$P"
step status-before $A status
if ! step locustsetup $A locustsetup; then say "Locust 설치 실패 — 중단"; exit 1; fi

skip tc02  || run_test tc02 900
skip spike || run_test spike 3660

if ! skip tc06; then
  since=$(date +%Y-%m-%dT%H:%M)
  step dbinit-tc06 $A dbinit
  if step tc06-loadtest $A loadtest tc06; then
    sleep 300; step tc06-1-was-a-stop  $A fault was-a stop;  grep TARGET_CHANGE "$OUT/tc06-1-was-a-stop.log"  | tee -a "$P"
    sleep 100; step tc06-2-was-a-start $A fault was-a start; grep TARGET_CHANGE "$OUT/tc06-2-was-a-start.log" | tee -a "$P"
    wait_end tc06 480
    collect tc06
  else
    say "  tc06 시작 실패 — 건너뜀"
  fi
  step tc06-3-rds-failover $A failover; u8 "$OUT/tc06-3-rds-failover.log"; grep FAILOVER_RESULT "$OUT/tc06-3-rds-failover.log" | tee -a "$P"
  tc07 tc06; waslog tc06 "$since"
fi

skip stress || run_test stress 1800

step status-after $A status
say "완료 → $OUT"
