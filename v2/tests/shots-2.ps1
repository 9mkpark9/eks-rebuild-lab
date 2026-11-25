# ② 이미지 빌드·컨테이너 테스트를 WSL 2 Ubuntu 의 Docker Engine 에서 실행하며 실제 터미널 화면을 캡처한다.
#   powershell -File v2/tests/shots-2.ps1 [-From <이름>]
param([string] $From = '', [string] $Only = '', [string] $Run = '1')
$S = Join-Path $PSScriptRoot 'shot.ps1'
$go = ($From -eq '')
function Shot($name, $cmd, $lines = 40, $cols = 140) {
    if (-not $script:go) { if ($name -eq $From) { $script:go = $true } else { return } }
    if ($Only -and ($name -notlike $Only)) { return }
    $env:SHOT_CMD = $cmd; & powershell -NoProfile -ExecutionPolicy Bypass -File $S -Name $name -Shell wsl -Cols $cols -Lines $lines
}
$C = 'docker compose -f v2/docker/compose.yaml --env-file v2/_run/secrets.env'
$F = 'msa/auth-service/src/main/java/kr/bodeum/vet/AuthServiceApplication.java'

Shot '2-01-dockerignore' "head -20 v2/docker/service.Dockerfile.dockerignore v2/docker/web.Dockerfile.dockerignore v2/docker/db.Dockerfile.dockerignore" 24
Shot '2-02-dockerfile' "cat v2/docker/service.Dockerfile" 40
# 빌드 최적화 사다리: 단계마다 소스 한 줄을 바꾸고 다시 빌드한다 (CACHED 와 걸린 시간)
foreach ($x in 'A', 'B', 'C', 'D', 'E') {
    Shot "2-03-ladder-$x" "head -2 v2/docker/bench/$x.Dockerfile; v2/tests/touch-src.sh $F; time (docker build --progress=plain -f v2/docker/bench/$x.Dockerfile --build-arg SERVICE=auth -t vet2-bench:$x msa 2>&1 | grep -E '^#[0-9]+ (\[(build|stage-1|[0-9]/[0-9])|CACHED|transferring context: [0-9])' | uniq | head -22); git checkout -q -- $F; docker image ls vet2-bench:$x --format '이미지 {{.Repository}}:{{.Tag}}  {{.Size}}'" 30
}
# 시험용 비밀번호를 ①에서 새로 만들었으므로 옛 비밀번호로 초기화된 DB 볼륨을 지우고 다시 만든다
Shot '2-04-up' "WEB_PORT=28090 $C down -v 2>&1 | tail -1; WEB_PORT=28090 $C up -d --build --wait 2>&1 | grep -E 'Built|Healthy|Started|Error'" 24
Shot '2-05-images' "docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E 'TAG|^vet2-(auth|clinic|reservation|web|db):1.0.0'; for i in auth clinic reservation web db; do docker image inspect vet2-`$i:1.0.0 --format '{{index .RepoTags 0}}  {{.Os}}/{{.Architecture}}'; done" 16
Shot '2-06-ps' "WEB_PORT=28090 $C ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'" 12
Shot '2-07-user' "for s in web auth clinic reservation mysql redis; do p=`$(docker inspect -f '{{.State.Pid}}' v2-`$s-1); printf '%-12s %-14s uid=%s\n' `$s `$(cat /proc/`$p/comm) `$(ps -o uid= -p `$p); done" 12
Shot '2-08-env' "docker exec v2-clinic-1 env | grep -E '^(SPRING_|DB_|REDIS_|APP_|JAVA_)' | sed -E 's/(PASSWORD=).*/\1(값 가림)/' | sort" 16
Shot '2-09-logs' "WEB_PORT=28090 $C logs --no-log-prefix --tail 3 clinic | cut -c1-150; echo ---; WEB_PORT=28090 $C logs --tail 3 web | cut -c1-150" 14
Shot '2-10-scenario' "v2/tests/with-secrets.sh node v2/tests/scenario.mjs --base-url http://localhost:28090 --db-container v2-mysql-1 | grep -E '^(■|시나리오|대상)|\[실패\]|결과|0-[0-9]'" 40
Shot "2-11-sigterm-$Run" "(docker run --rm -i --network v2_default node:22-alpine node --input-type=module - http://auth:8080 20 < v2/tests/shutdown-check.mjs) & sleep 4; docker stop v2-auth-1; wait; docker start v2-auth-1 > /dev/null" 22
Shot "2-12-sigkill-$Run" "(docker run --rm -i --network v2_default node:22-alpine node --input-type=module - http://auth:8080 20 < v2/tests/shutdown-check.mjs) & sleep 4; docker kill v2-auth-1; wait; docker start v2-auth-1 > /dev/null" 22
# WSL 의 AWS 로그인이 만료되어, 이 PC(Windows)의 aws 로 받은 ECR 로그인 토큰을 WSL 의 docker 에 넘긴다. 계정 번호는 가린다
function ShotBash($name, $cmd, $lines = 16, $cols = 140) {
    if (-not $script:go) { if ($name -eq $From) { $script:go = $true } else { return } }
    $env:SHOT_CMD = $cmd; & powershell -NoProfile -ExecutionPolicy Bypass -File $S -Name $name -Shell bash -Cols $cols -Lines $lines
}
ShotBash '2-13-push' "R=`$(aws sts get-caller-identity --query Account --output text).dkr.ecr.ap-northeast-2.amazonaws.com; aws ecr get-login-password --region ap-northeast-2 | wsl -d Ubuntu -u junseo -- docker login -u AWS --password-stdin `$R 2>&1 | tail -1; for s in auth web; do wsl -d Ubuntu -u junseo -- docker tag vet2-`$s:1.0.0 `$R/vet2-`$s:1.0.0-wsl; wsl -d Ubuntu -u junseo -- docker push `$R/vet2-`$s:1.0.0-wsl 2>&1 | tail -2; done | sed 's/[0-9]\{12\}/************/g'; wsl -d Ubuntu -u junseo -- docker logout `$R > /dev/null"
ShotBash '2-14-ecr' "for s in auth clinic reservation web; do aws ecr describe-images --region ap-northeast-2 --repository-name vet2-`$s --image-ids imageTag=1.0.0-wsl --query 'imageDetails[0].[repositoryName,imageTags[0],imagePushedAt]' --output text; done 2>&1 | sed 's/[0-9]\{12\}/************/g'" 12
