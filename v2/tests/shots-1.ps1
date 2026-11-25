# ① 워크로드 테스트를 WSL 2 Ubuntu 에서 차례로 실행하며 실제 터미널 화면을 캡처한다 (v2/tests/shot.ps1).
#   powershell -File v2/tests/shots-1.ps1 [-From <이름>]
param([string] $From = '')
$S = Join-Path $PSScriptRoot 'shot.ps1'
$go = ($From -eq '')
function Shot($name, $cmd, $lines = 40, $cols = 140) {
    if (-not $script:go) { if ($name -eq $From) { $script:go = $true } else { return } }
    $env:SHOT_CMD = $cmd; & powershell -NoProfile -ExecutionPolicy Bypass -File $S -Name $name -Shell wsl -Cols $cols -Lines $lines
}

Shot '1-01-tools' "head -2 /etc/os-release; uname -r; java -version 2>&1 | head -1; node --version; docker version --format 'Docker Engine {{.Server.Version}} ({{.Server.Os}}/{{.Server.Arch}})'; file msa/gradlew" 14
# 문제 장면(prob-1-build-spawn-helper): JDK 가 업데이트된 뒤 옛 Gradle 데몬이 테스트 프로세스를 띄우지 못했다. 데몬을 멈추고 다시 빌드한다
Shot '1-02-gradle-stop' "cd msa && ./gradlew --stop; java -version 2>&1 | head -1" 10
Shot '1-03-build' "cd msa && ./gradlew clean build --console=plain 2>&1 | grep -E 'bootJar|:test|BUILD|actionable'; ls -l */build/libs/*.jar | grep -v plain" 24
# 비밀번호를 새로 만든다 (앞선 캡처에 시험용 비밀번호가 찍혀 바꾼다). 파일 내용은 화면에 내지 않는다
Shot '1-04-stores' "v2/workload/services.sh stop > /dev/null; v2/workload/stores.sh down; rm -f v2/_run/secrets.env; v2/workload/stores.sh up" 12
Shot '1-05-dbinit' "v2/workload/db-init.sh" 40
Shot '1-06-services' "v2/workload/services.sh start; v2/workload/services.sh status" 12
Shot '1-07-scenario' "v2/tests/with-secrets.sh node v2/tests/scenario.mjs --auth-url http://127.0.0.1:28081 --clinic-url http://127.0.0.1:28082 --reservation-url http://127.0.0.1:28083 --db-container v2-mysql | grep -E '^(■|시나리오|대상)|\[실패\]|결과|11-'" 40
Shot '1-08-fault' "v2/workload/fault-check.sh" 62
