#!/usr/bin/env bash
# ① 워크로드 테스트를 WSL 2 Ubuntu 에서 처음부터 다시 한다. 단계마다 v2/tests/cap.sh 로 명령과 출력을 기록한다.
#   wsl -d Ubuntu -- bash /mnt/c/.../v2/wsl/stage1.sh
# 작업 폴더: ~/vet2-lab (이 PC 의 저장소를 git clone 하고, 아직 커밋하지 않은 v2/ 를 덮어쓴다)
# 기록: Windows 쪽 저장소의 v2/_run/capture/ (그림은 Windows 에서 v2/tests/render.mjs 가 만든다)
set -u
SRC=/mnt/c/Users/junseo/Desktop/webserver/eks-rebuild-lab
W="$HOME/vet2-lab"
export CAP_DIR="$SRC/v2/_run/capture"

if [ ! -d "$W/.git" ]; then
    git clone -q "$SRC" "$W"
fi
rsync -a --delete --exclude '_run/' "$SRC/v2/" "$W/v2/"
cd "$W"
. v2/tests/cap.sh

cap w1-00-env "① 테스트 환경: WSL 2 Ubuntu 의 도구" bash v2/wsl/check.sh
cap w1-01-gradlew "① 줄 끝 확인: git 으로 받은 gradlew 는 LF" bash -c 'file msa/gradlew; head -1 msa/gradlew | od -c | head -1'
cap w1-02-build "① 소스 빌드 (Gradle, 서비스 3개)" bash -c 'cd msa && ./gradlew clean build --console=plain 2>&1 | grep -E "^> Task .*(bootJar|test)|BUILD|actionable"; ls -l */build/libs/*.jar | grep -v plain | awk "{print \$5, \$9}"'
cap w1-03-stores "① MySQL·Redis 띄우기 (공식 이미지, Docker Engine)" bash -c 'v2/workload/stores.sh down; v2/workload/stores.sh up'
cap w1-04-dbinit "① DB 초기화 (스키마·시드·서비스 계정)" bash v2/workload/db-init.sh
cap w1-05-services "① 서비스 3개를 jar 로 실행 (환경 변수로 설정)" bash v2/workload/services.sh start
cap w1-06-status "① 서비스 상태 (포트, PID, 메모리, /health)" bash v2/workload/services.sh status
set -a; . v2/_run/secrets.env; set +a
cap w1-07-scenario "① 시나리오 테스트 (서비스 3개에 직접)" node v2/tests/scenario.mjs --auth-url http://127.0.0.1:28081 --clinic-url http://127.0.0.1:28082 --reservation-url http://127.0.0.1:28083 --db-container v2-mysql
cap w1-08-fault "① 구성 요소 하나씩 멈추기 (W-3 포함)" bash v2/workload/fault-check.sh
