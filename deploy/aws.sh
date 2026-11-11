#!/usr/bin/env bash
# 동물병원 예약 시스템 AWS 배포 (문서 10장). 각 단계는 따로 실행할 수 있다.
# 오토스케일링 없음: WEB 2대 · WAS 2대 고정 EC2 (과부하 테스트에서 고정 대수의 한계와 비용을 잰다).
#
#   bash deploy/aws.sh whoami      # 지금 로그인한 AWS 계정·사용자 확인 (배포 전에 꼭)
#   bash deploy/aws.sh build       # ① 웹 화면 빌드 + WAS jar 빌드 + 시드 SQL 생성
#   bash deploy/aws.sh upload      # ② 배포 버킷에 올리기
#   bash deploy/aws.sh infra       # ③ 네트워크 → 보안 → 데이터 스택 (RDS Multi-AZ 15~20분)
#   bash deploy/aws.sh dbinit      # ④ 관리 EC2에서 DB 초기화 (Session Manager 명령)
#   bash deploy/aws.sh was         # ⑤ WAS 계층: 내부 ALB · WAS 고정 2대 (먼저)
#   bash deploy/aws.sh web         # ⑥ WEB 계층: 외부 ALB · WEB 고정 2대 · 대시보드 (was 다음)
#   bash deploy/aws.sh app         # was → web 를 이어서
#   bash deploy/aws.sh loadgen     # ⑦ Locust 부하 생성 스택
#   bash deploy/aws.sh verify      # 10.6 배포 확인 (대상 정상 대기, 헬스, 라우팅, WAS 분산)
#   bash deploy/aws.sh all         # build → upload → infra → dbinit → was → web → loadgen → verify
#
#   bash deploy/aws.sh locustsetup         # Locust 설치 확인 (venv, 처음 한 번 3~5분)
#   bash deploy/aws.sh loadtest [프로필]   # Locust 시작 (기본 stress: 3분마다 +100명, 100→1000명, 30분)
#   bash deploy/aws.sh loadstatus [프로필] # 진행 상황 / 끝났으면 사용자 수 단계별 RPS·p95·실패율
#   bash deploy/aws.sh loadstop            # Locust 중지
#   bash deploy/aws.sh report [프로필]     # 테스트 구간의 인스턴스별 CPU·메모리 + 비용 보고서 (build/report-*.md)
#
#   bash deploy/aws.sh fixwas      # 실행 중인 WAS에 Redis 포트 설정을 넣고 재시작 → verify
#   bash deploy/aws.sh fault was-a stop|start   # TC-06 장애 주입 (web-a/web-c/was-a/was-c)
#   bash deploy/aws.sh tc07        # TC-07 정합성 SQL 4개 (관리 EC2)
#   bash deploy/aws.sh failover    # TC-06 ③ RDS 강제 장애 조치 + 오류 구간 측정
#   bash deploy/scenarios.sh       # 전체 시나리오 실행·수집 (results/run-*/)
#   bash deploy/aws.sh status      # 스택 상태, 인스턴스, 접속 주소
#   bash deploy/aws.sh destroy     # 10.9 전체 삭제 (RDS 최종 스냅샷과 배포 버킷은 남음)
set -euo pipefail

export AWS_REGION=${AWS_REGION:-ap-northeast-2}
export AWS_DEFAULT_REGION=$AWS_REGION
export AWS_CLI_FILE_ENCODING=UTF-8          # Windows에서 한글 템플릿을 읽기 위해
export MSYS_NO_PATHCONV=1                   # Git Bash가 /aws/... 같은 인자를 경로로 바꾸지 않게
AWS=${AWS:-aws}
command -v "$AWS" >/dev/null 2>&1 || AWS="/c/Program Files/Amazon/AWSCLIV2/aws.exe"
export AWS
CLIENT=${CLIENT:-vet01}
VER=${VER:-1.0.0}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v cygpath >/dev/null 2>&1 && ROOT="$(cygpath -m "$ROOT")"   # Windows용 aws.exe가 읽을 수 있는 C:/... 경로
if [ "${1:-}" != build ]; then   # build 는 AWS 로그인 없이 된다 (콘솔로 직접 올릴 때, docs/07)
  read -r ACCOUNT CALLER < <("$AWS" sts get-caller-identity --query "[Account,Arn]" --output text | tr -d '\r')
  echo "AWS 계정: $ACCOUNT  사용자: $CALLER  리전: $AWS_REGION"
  if [ -n "${EXPECT_ACCOUNT:-}" ] && [ "$ACCOUNT" != "$EXPECT_ACCOUNT" ]; then
    echo "계정이 다릅니다 (기대값 $EXPECT_ACCOUNT). 중단합니다."; exit 1
  fi
fi
BUCKET=${BUCKET:-$CLIENT-artifacts-${ACCOUNT:-}}
ALLOWED_CIDR=${ALLOWED_CIDR:-0.0.0.0/0}
OWNER=${OWNER:-${CALLER##*/}}
TAGS=(Project="$CLIENT" Owner="${OWNER:-unknown}" Purpose=loadtest)   # 비용 집계용 공통 태그 (모든 스택)

log() { printf '\n\033[1;34m[%s] %s\033[0m\n' "$(date +%H:%M:%S)" "$*"; }
out() { "$AWS" cloudformation describe-stacks --stack-name "$CLIENT-$1" --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text; }
clean_failed() { # 첫 생성이 실패해 ROLLBACK_COMPLETE 로 남은 스택은 다시 배포할 수 없으므로 지운다
  local st; st=$("$AWS" cloudformation describe-stacks --stack-name "$1" --query "Stacks[0].StackStatus" --output text 2>/dev/null | tr -d '\r' || true)
  case "$st" in ROLLBACK_COMPLETE|ROLLBACK_FAILED|DELETE_FAILED)
    echo "실패 상태 스택 삭제: $1 ($st)"
    "$AWS" cloudformation delete-stack --stack-name "$1"
    "$AWS" cloudformation wait stack-delete-complete --stack-name "$1" ;;
  esac
}

purge_secrets() { # 이전 삭제로 "삭제 예약" 상태인 같은 이름의 비밀을 즉시 지운다 (같은 이름으로 새로 만들 수 없음)
  local s d
  for s in "$CLIENT/db/app" "$CLIENT/redis/auth"; do
    d=$("$AWS" secretsmanager describe-secret --secret-id "$s" --query DeletedDate --output text 2>/dev/null | tr -d '\r' || true)
    if [ -z "$d" ] || [ "$d" = None ]; then continue; fi
    echo "삭제 예약된 비밀 즉시 삭제: $s (예약 $d)"
    "$AWS" secretsmanager delete-secret --secret-id "$s" --force-delete-without-recovery >/dev/null 2>&1 || {
      "$AWS" secretsmanager restore-secret --secret-id "$s" >/dev/null   # 예약 상태에서 바로 안 지워지면 복구 후 즉시 삭제
      "$AWS" secretsmanager delete-secret --secret-id "$s" --force-delete-without-recovery >/dev/null; }
    for _ in $(seq 1 30); do   # 실제 삭제는 비동기라 사라질 때까지 기다린다
      "$AWS" secretsmanager describe-secret --secret-id "$s" >/dev/null 2>&1 || break
      sleep 5
    done
  done
}

deploy() { # deploy <stack> <template> [params...]
  local name=$1 tpl=$2; shift 2
  clean_failed "$CLIENT-$name"
  log "스택 배포: $CLIENT-$name"
  "$AWS" cloudformation deploy --stack-name "$CLIENT-$name" --template-file "$ROOT/cfn/$tpl" \
    --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset \
    --tags "${TAGS[@]}" \
    --parameter-overrides ClientName="$CLIENT" "$@" || {
      echo "--- 실패 원인 (최근 스택 이벤트)"
      "$AWS" cloudformation describe-stack-events --stack-name "$CLIENT-$name" --max-items 40 \
        --query "StackEvents[?contains(ResourceStatus,'FAILED')].[LogicalResourceId,ResourceStatusReason]" --output text | head -15
      return 1; }
}

whoami() { :; }   # 계정 출력은 위에서 이미 했다

infra() {
  deploy network network.yaml VpcCidr=10.0.0.0/16
  deploy security security.yaml ArtifactBucket="$BUCKET" AllowedCidr="$ALLOWED_CIDR"
  purge_secrets
  deploy data data.yaml DbInstanceClass=db.t3.small MultiAZ=true
}

build() {
  log "① 웹 화면 빌드 (web/dist/site, web/dist/app)"
  (cd "$ROOT/web" && npm ci --no-audit --no-fund && npm run build)
  mkdir -p "$ROOT/build"
  tar --force-local -czf "$ROOT/build/vet-web-$VER.tar.gz" -C "$ROOT/web/dist" site app
  log "① WAS jar 빌드 (was/build/libs)"
  if [ -z "${JAVA_HOME:-}" ]; then   # Windows: winget 으로 설치한 Amazon Corretto 21
    local jdk; jdk=$(ls -d "/c/Program Files/Amazon Corretto/"jdk21* 2>/dev/null | head -1 || true)
    [ -n "$jdk" ] && export JAVA_HOME="$(cygpath -m "$jdk")"
  fi
  (cd "$ROOT/was" && ./gradlew --no-daemon -q bootJar -Pversion="$VER")
  cp "$ROOT/was/build/libs/vet-api-$VER.jar" "$ROOT/build/"
  log "① 시드 SQL 생성 (오늘부터 14일)"
  node "$ROOT/db/gen-seed.mjs" > "$ROOT/db/seed.sql"
}

upload() {
  log "② 배포 버킷에 올리기: s3://$BUCKET"
  if ! "$AWS" s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then   # 처음 한 번: 비공개 버킷 생성
    "$AWS" s3api create-bucket --bucket "$BUCKET" --create-bucket-configuration "LocationConstraint=$AWS_REGION" >/dev/null
    "$AWS" s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    echo "배포 버킷 생성: $BUCKET"
  fi
  "$AWS" s3api put-bucket-tagging --bucket "$BUCKET" --tagging "TagSet=[{Key=Project,Value=$CLIENT},{Key=Owner,Value=${OWNER:-unknown}}]" 2>/dev/null || true
  "$AWS" s3 cp "$ROOT/build/vet-api-$VER.jar" "s3://$BUCKET/was/" --only-show-errors
  "$AWS" s3 cp "$ROOT/build/vet-web-$VER.tar.gz" "s3://$BUCKET/web/" --only-show-errors
  "$AWS" s3 cp "$ROOT/deploy/nginx.conf" "s3://$BUCKET/web/nginx.conf" --only-show-errors
  "$AWS" s3 cp "$ROOT/db/schema.sql" "s3://$BUCKET/db/schema.sql" --only-show-errors
  "$AWS" s3 cp "$ROOT/db/seed.sql" "s3://$BUCKET/db/seed.sql" --only-show-errors
  "$AWS" s3 cp "$ROOT/db/init.sh" "s3://$BUCKET/db/init.sh" --only-show-errors
  "$AWS" s3 cp "$ROOT/loadtest/locustfile.py" "s3://$BUCKET/loadgen/locustfile.py" --only-show-errors
  "$AWS" s3 cp "$ROOT/loadtest/summarize.py" "s3://$BUCKET/loadgen/summarize.py" --only-show-errors
}

ssm_run() { # ssm_run <instance-id> <command...> : Session Manager로 명령을 보내고 끝날 때까지 기다린다 (명령 안에 큰따옴표 금지)
  local id=$1; shift
  local cid status
  cid=$("$AWS" ssm send-command --instance-ids "$id" --document-name AWS-RunShellScript \
        --parameters "$(printf '{"commands":["%s"]}' "$*")" --timeout-seconds 900 --query Command.CommandId --output text)
  for _ in $(seq 1 120); do  # 최대 10분
    status=$("$AWS" ssm get-command-invocation --command-id "$cid" --instance-id "$id" --query Status --output text 2>/dev/null || echo Pending)
    case "$status" in Pending|InProgress|Delayed) sleep 5 ;; *) break ;; esac
  done
  "$AWS" ssm get-command-invocation --command-id "$cid" --instance-id "$id" \
    --query "[Status,StandardOutputContent,StandardErrorContent]" --output text
  [ "$status" = "Success" ]
}

wait_ssm() { # SSM 에이전트 등록 대기
  for _ in $(seq 1 30); do
    [ "$("$AWS" ssm describe-instance-information --filters "Key=InstanceIds,Values=$1" --query 'length(InstanceInformationList)' --output text)" = "1" ] && return 0
    sleep 10
  done
  echo "SSM 에이전트가 등록되지 않았습니다: $1"; return 1
}

dbinit() {
  local ops; ops=$(out data OpsInstanceId)
  log "④ DB 초기화 (관리 EC2 $ops)"
  wait_ssm "$ops"
  ssm_run "$ops" "aws s3 cp s3://$BUCKET/db/init.sh /tmp/init.sh --region $AWS_REGION && CLIENT=$CLIENT BUCKET=$BUCKET AWS_REGION=$AWS_REGION bash /tmp/init.sh"
}

was() {   # 내부 ALB·WAS. WEB 사용자 데이터가 내부 ALB 주소를 쓰므로 먼저 배포한다
  deploy was was.yaml AppVersion="$VER" ArtifactBucket="$BUCKET"
}

web() {
  # 사양 비교: WEB_A_TYPE=t4g.nano WEB_A_ARCH=arm64 WEB_C_TYPE=t3.nano WEB_C_ARCH=x86_64 bash deploy/aws.sh web
  local spec=()
  [ -n "${WEB_A_TYPE:-}" ] && spec+=(WebInstanceTypeA="$WEB_A_TYPE")
  [ -n "${WEB_A_ARCH:-}" ] && spec+=(WebArchA="$WEB_A_ARCH")
  [ -n "${WEB_C_TYPE:-}" ] && spec+=(WebInstanceTypeC="$WEB_C_TYPE")
  [ -n "${WEB_C_ARCH:-}" ] && spec+=(WebArchC="$WEB_C_ARCH")
  [ ${#spec[@]} -gt 0 ] && echo "WEB 사양: ${spec[*]}"
  deploy web web.yaml AppVersion="$VER" ArtifactBucket="$BUCKET" ${spec[@]+"${spec[@]}"}
}

app() { was; web; }

loadgen() {
  deploy loadgen loadgen.yaml ArtifactBucket="$BUCKET"
}

wait_healthy() { # wait_healthy <이름> <대상 그룹 ARN> : 등록된 대상이 모두 healthy 가 될 때까지 (최대 10분)
  local name=$1 tg=$2 states
  for _ in $(seq 1 60); do
    states=$("$AWS" elbv2 describe-target-health --target-group-arn "$tg" --query "TargetHealthDescriptions[].TargetHealth.State" --output text)
    echo "  $name 대상: $states"
    [ -n "$states" ] && ! grep -qv '^healthy$' <(tr '\t' '\n' <<<"$states") && return 0
    sleep 10
  done
  echo "  $name 대상이 10분 안에 정상이 되지 않았습니다"; return 1
}

verify() {
  local alb; alb=$(out web ExternalAlbDns)
  log "10.6 배포 확인: http://$alb"
  wait_healthy WAS "$(out was WasTgArn)"
  wait_healthy WEB "$(out web WebTgArn)"
  for p in /health /about /api/notices; do
    printf '%-14s ' "$p"; curl -s -i -m 10 "http://$alb$p" | grep -iE '^(HTTP|x-web-node|x-served-by)' | tr -d '\r' | tr '\n' ' '; echo
  done
  echo "--- /api/notices 20회: WAS 분산"
  for _ in $(seq 1 20); do curl -s -i -m 10 "http://$alb/api/notices" | grep -i x-served-by | tr -d '\r'; done | sort | uniq -c
  echo "--- / 20회: WEB 분산"
  for _ in $(seq 1 20); do curl -s -i -m 10 "http://$alb/" | grep -i x-web-node | tr -d '\r'; done | sort | uniq -c
  echo "대시보드: https://$AWS_REGION.console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards/dashboard/$CLIENT-dashboard"
}

# ── 부하 테스트 (Locust EC2, 마스터 1 + 워커 2) ──
profile_seconds() { # 프로필 길이(초). report 가 테스트 끝 시각을 정할 때 쓴다
  case "$1" in
    stress|webstress) echo $(( ${STRESS_STEP_SEC:-180} * ${STRESS_STEPS:-10} )) ;;
    web02|web06) echo 900 ;; webspike) echo 1860 ;;
    tc08) echo 1080 ;; spike) echo 3660 ;; tc02|tc06) echo 900 ;; *) echo 1800 ;;
  esac
}

loadtest() {
  local p=${1:-stress} wait=${WAIT_SCALE:-}
  if [ -z "$wait" ]; then case "$p" in stress|webstress) wait=0.2 ;; *) wait=1 ;; esac; fi
  local id alb; id=$(out loadgen LocustInstanceId); alb=$(out web ExternalAlbDns)
  log "부하 테스트 시작: 프로필 $p, 대기 시간 배율 $wait, 대상 http://$alb (Locust $id)"
  "$AWS" s3 cp "$ROOT/loadtest/locustfile.py" "s3://$BUCKET/loadgen/locustfile.py" --only-show-errors   # 최신 스크립트로
  "$AWS" s3 cp "$ROOT/loadtest/summarize.py" "s3://$BUCKET/loadgen/summarize.py" --only-show-errors
  wait_ssm "$id"
  local res; if ! res=$(ssm_run "$id" "mkdir -p /opt/loadtest; cd /opt/loadtest; /opt/locust-venv/bin/python -m locust --version >/dev/null 2>&1 || { echo locust not installed - run locustsetup; exit 1; }; pkill -f locustfile.py; sleep 1; aws s3 cp s3://$BUCKET/loadgen/locustfile.py locustfile.py --region $AWS_REGION --only-show-errors; aws s3 cp s3://$BUCKET/loadgen/summarize.py summarize.py --region $AWS_REGION --only-show-errors; mkdir -p results; rm -f results/${p}_*; echo LOCUST_STARTED=\$(date +%s); export PROFILE=$p WORKERS=2 WAIT_SCALE=$wait STRESS_STEP=${STRESS_STEP:-100} STRESS_STEPS=${STRESS_STEPS:-10} STRESS_STEP_SEC=${STRESS_STEP_SEC:-180}; setsid nohup /opt/locust-venv/bin/python -m locust -f locustfile.py --master --headless --expect-workers 2 -H http://$alb --csv results/$p --csv-full-history --html results/$p.html > results/$p-master.log 2>&1 < /dev/null & sleep 3; for i in 1 2; do setsid nohup /opt/locust-venv/bin/python -m locust -f locustfile.py --worker --master-host 127.0.0.1 > results/$p-worker\$i.log 2>&1 < /dev/null & done; sleep 8; n=\$(pgrep -fc locustfile.py); echo locust processes: \$n; tail -n 3 results/$p-master.log; [ \$n -ge 3 ]"); then echo "$res"; echo "Locust 시작 실패 (위 출력 확인)"; return 1; fi
  echo "$res"
  mkdir -p "$ROOT/build"
  local started; started=$(grep -o 'LOCUST_STARTED=[0-9]*' <<<"$res" | head -1 | cut -d= -f2)
  echo "${started:-$(date +%s)}" > "$ROOT/build/loadtest-$p.start"   # Locust EC2 에서 실제로 시작한 시각
  echo "$wait" > "$ROOT/build/loadtest-$p.wait"
  local sec; sec=$(profile_seconds "$p")
  echo "시작 시각 기록: build/loadtest-$p.start  (약 $((sec / 60))분 뒤 끝남)"
  echo "진행 확인: bash deploy/aws.sh loadstatus $p   / 끝난 뒤: bash deploy/aws.sh report $p"
}

locustsetup() { # Locust 를 venv(/opt/locust-venv)에 설치한다. 시스템 pip(rpm)는 업그레이드할 수 없어 새 wheel 을 못 받는다
  local id; id=$(out loadgen LocustInstanceId | tr -d '\r')
  log "Locust 설치 확인 ($id)"
  wait_ssm "$id"
  local res; res=$(ssm_run "$id" "if /opt/locust-venv/bin/python -m locust --version 2>/dev/null; then echo LOCUST_READY; exit 0; fi; echo installing; python3 -m venv /opt/locust-venv || { dnf install -y -q python3-pip >/dev/null; python3 -m venv /opt/locust-venv; }; /opt/locust-venv/bin/pip install -q -U pip; /opt/locust-venv/bin/pip install -q --prefer-binary 'locust>=2.30,<3' 2>&1 | tail -n 5; /opt/locust-venv/bin/python -m locust --version && echo LOCUST_READY" || true)
  echo "$res"
  grep -q LOCUST_READY <<<"$res"
}

limit_ms() { case "$1" in web*) echo 300 ;; *) echo 1000 ;; esac; }   # 한계 판정 p95 기준 (WEB 정적 300ms, 문서 03장)

loadstatus() {
  local p=${1:-stress} id; id=$(out loadgen LocustInstanceId)
  ssm_run "$id" "cd /opt/loadtest; echo running: \$(pgrep -fc locustfile.py); tail -n 2 results/$p-master.log; python3 summarize.py $p $(limit_ms "$p")" \
    | tee "$ROOT/build/loadtest-$p-summary.txt"
}

loadstop() {
  local id; id=$(out loadgen LocustInstanceId)
  ssm_run "$id" "pkill -f locustfile.py; sleep 2; echo running: \$(pgrep -fc locustfile.py)" || true
}

report() {
  local p=${1:-stress}
  [ -f "$ROOT/build/loadtest-$p.start" ] || { echo "build/loadtest-$p.start 가 없습니다. 먼저 loadtest $p 를 실행하세요."; return 1; }
  local start end now sec; start=$(cat "$ROOT/build/loadtest-$p.start"); sec=$(profile_seconds "$p"); now=$(date +%s)
  end=$(( start + sec )); [ "$end" -gt "$now" ] && end=$now
  loadstatus "$p" >/dev/null 2>&1 || true
  log "보고서: 프로필 $p, $(date -d "@$start" '+%m-%d %H:%M') ~ $(date -d "@$end" '+%H:%M')"
  CLIENT=$CLIENT PROFILE=$p START=$start END=$end ROOT="$ROOT" node "$ROOT/deploy/report.mjs"
}

# ── TC-06 장애 주입 · TC-07 정합성 ──
fault() { # fault <web-a|web-c|was-a|was-c> <stop|start> : nginx / vet-api 를 멈추거나 다시 켠다 (고정 대수라 ASG 교체 없음)
  local who=$1 act=$2 id svc
  case "$who" in
    web-a) id=$(out web WebInstanceA); svc=nginx ;; web-c) id=$(out web WebInstanceC); svc=nginx ;;
    was-a) id=$(out was WasInstanceA); svc=vet-api ;; was-c) id=$(out was WasInstanceC); svc=vet-api ;;
    *) echo "fault <web-a|web-c|was-a|was-c> <stop|start>"; return 1 ;;
  esac
  id=$(tr -d '\r' <<<"$id")
  log "장애 주입: $who($id) $svc $act"
  local tg t0 st; tg=$(out "${who%-*}" "$( [ "${who%-*}" = web ] && echo WebTgArn || echo WasTgArn )" | tr -d '\r')
  local res; res=$(ssm_run "$id" "systemctl $act $svc; echo ACTED_AT=\$(date +%s); echo $svc: \$(systemctl is-active $svc)" || true)
  echo "$res"
  t0=$(grep -o 'ACTED_AT=[0-9]*' <<<"$res" | head -1 | cut -d= -f2); t0=${t0:-$(date +%s)}
  for _ in $(seq 1 90); do   # 최대 약 3분: 중지면 healthy 가 아니게 될 때까지, 시작이면 healthy 가 될 때까지
    st=$("$AWS" elbv2 describe-target-health --target-group-arn "$tg" --targets "Id=$id" --query "TargetHealthDescriptions[0].TargetHealth.State" --output text | tr -d '\r')
    if { [ "$act" = stop ] && [ "$st" != healthy ]; } || { [ "$act" = start ] && [ "$st" = healthy ]; }; then break; fi
    sleep 2
  done
  echo "TARGET_CHANGE $who $act → 대상 상태 $st, $svc $act 시각부터 $(( $(date +%s) - t0 ))초 (2초 간격 확인)"
}

tc07() {
  local ops; ops=$(out data OpsInstanceId | tr -d '\r')
  log "TC-07 정합성 검사 (관리 EC2 $ops)"
  "$AWS" s3 cp "$ROOT/db/tc07.sh" "s3://$BUCKET/db/tc07.sh" --only-show-errors
  ssm_run "$ops" "aws s3 cp s3://$BUCKET/db/tc07.sh /tmp/tc07.sh --region $AWS_REGION --only-show-errors && CLIENT=$CLIENT AWS_REGION=$AWS_REGION bash /tmp/tc07.sh"
}

failover() { # TC-06 ③ RDS 강제 장애 조치: 2초마다 /api/notices 를 호출해 오류 구간을 잰다
  local alb db0 db1 t0 code last_err="" first_err="" ok_run=0 n=0 errs=0
  alb=$(out web ExternalAlbDns | tr -d '\r')
  db0=$("$AWS" rds describe-db-instances --db-instance-identifier "$CLIENT-db" --query "DBInstances[0].[AvailabilityZone,SecondaryAvailabilityZone]" --output text | tr -d '\r')
  log "TC-06 ③ RDS 강제 장애 조치 시작 (주/대기 AZ: $db0)"
  "$AWS" rds reboot-db-instance --db-instance-identifier "$CLIENT-db" --force-failover --query "DBInstance.DBInstanceStatus" --output text
  t0=$(date +%s)
  while :; do
    code=$(curl -s -m 5 -i "http://$alb/api/notices" 2>/dev/null | awk 'NR==1{print $2}' | tr -d '\r' || true); code=${code:-000}
    n=$((n + 1))
    if [ "$code" = 200 ]; then ok_run=$((ok_run + 1)); else
      errs=$((errs + 1)); ok_run=0; last_err=$(( $(date +%s) - t0 )); [ -z "$first_err" ] && first_err=$last_err
      echo "  +${last_err}s HTTP $code"
    fi
    # 장애 조치 이벤트가 끝나고(available) 오류 없이 2분(60회 x 2초) 지나면 끝
    if [ $(( $(date +%s) - t0 )) -gt 60 ] && [ $ok_run -ge 60 ] && \
       [ "$("$AWS" rds describe-db-instances --db-instance-identifier "$CLIENT-db" --query "DBInstances[0].DBInstanceStatus" --output text | tr -d '\r')" = available ]; then break; fi
    [ $(( $(date +%s) - t0 )) -gt 900 ] && { echo "  15분 제한 도달"; break; }
    sleep 2
  done
  db1=$("$AWS" rds describe-db-instances --db-instance-identifier "$CLIENT-db" --query "DBInstances[0].[AvailabilityZone,SecondaryAvailabilityZone]" --output text | tr -d '\r')
  echo "FAILOVER_RESULT 요청 $n회, 오류 $errs회, 첫 오류 +${first_err:-없음}s, 마지막 오류 +${last_err:-없음}s, 주 AZ: ${db0%%[[:space:]]*} → ${db1%%[[:space:]]*}"
}

fixwas() { # 실행 중인 WAS에 Redis 포트 환경 변수를 넣고 재시작한다 (인스턴스 교체 없이). 먼저 실패 원인을 출력한다
  local id
  for id in $(out was WasInstanceA | tr -d '\r') $(out was WasInstanceC | tr -d '\r'); do
    log "WAS 수정: $id"
    wait_ssm "$id"
    ssm_run "$id" "echo '--- startup error'; journalctl -u vet-api --no-pager | grep -m 4 -E 'APPLICATION FAILED|Could not resolve|Caused by|Failed to bind' | cut -c1-240; grep -q SPRING_DATA_REDIS_PORT /opt/vet/app.conf || echo export SPRING_DATA_REDIS_PORT=6379 >> /opt/vet/app.conf; systemctl restart vet-api; for i in \$(seq 1 24); do curl -sf -m 2 localhost:8080/health >/dev/null && break; sleep 5; done; echo '--- after restart'; systemctl is-active vet-api; curl -s -m 2 localhost:8080/health; echo; tail -n 3 /var/log/vet/app.log | cut -c1-240" || true
  done
  verify
}

status() {
  "$AWS" cloudformation describe-stacks --query "Stacks[?starts_with(StackName,'$CLIENT-')].[StackName,StackStatus]" --output table
  "$AWS" ec2 describe-instances --filters "Name=tag:Project,Values=$CLIENT" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,InstanceId,InstanceType,State.Name,Placement.AvailabilityZone]" --output table
  local alb; alb=$(out web ExternalAlbDns 2>/dev/null || true)
  [ -n "$alb" ] && [ "$alb" != "None" ] && echo "접속 주소: http://$alb"
  return 0
}

destroy() {
  log "10.9 삭제: loadgen → web → was → data → security → network"
  local logs; logs=$(out was AlbLogBucket 2>/dev/null || true)
  [ "$logs" = "None" ] && logs=""
  for s in loadgen web was data security network; do
    for try in 1 2 3; do  # ALB 로그는 5분마다 들어오므로, 버킷이 다시 차서 삭제가 실패하면 비우고 재시도한다
      [ "$s" = was ] && [ -n "$logs" ] && { "$AWS" s3 rm "s3://$logs" --recursive --only-show-errors 2>/dev/null || true; }
      "$AWS" cloudformation delete-stack --stack-name "$CLIENT-$s"
      "$AWS" cloudformation wait stack-delete-complete --stack-name "$CLIENT-$s" 2>/dev/null && break
      [ "$try" = 3 ] && { echo "삭제 실패: $CLIENT-$s (콘솔의 스택 이벤트를 확인하세요)"; return 1; }
      echo "재시도 $try: $CLIENT-$s"
    done
    echo "삭제됨: $CLIENT-$s"
  done
  purge_secrets
  echo "RDS 최종 스냅샷과 배포 버킷(s3://$BUCKET)은 남아 있습니다."
}

case "${1:-}" in
  whoami) whoami ;;
  infra) infra ;; build) build ;; upload) upload ;; dbinit) dbinit ;; loadgen) loadgen ;;
  was) was ;; web) web ;; app) app ;;
  verify) verify ;; status) status ;; destroy) destroy ;; fixwas) fixwas ;;
  loadtest) loadtest "${2:-stress}" ;; loadstatus) loadstatus "${2:-stress}" ;; loadstop) loadstop ;;
  report) report "${2:-stress}" ;; locustsetup) locustsetup ;;
  fault) fault "${2:-}" "${3:-}" ;; tc07) tc07 ;; failover) failover ;;
  all) build; upload; infra; dbinit; was; web; loadgen; verify ;;
  *) sed -n '2,25p' "$0"; exit 1 ;;
esac
