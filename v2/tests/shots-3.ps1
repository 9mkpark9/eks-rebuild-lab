# ③ Kubernetes 전환 (EC2 kubeadm) 을 실행하며 실제 터미널 화면을 캡처한다. Git Bash 에서 kubectl, aws 를 쓴다.
#   powershell -File v2/tests/shots-3.ps1 [-From <이름>]
param([string] $From = '', [string] $Only = '', [string] $Skip = '')
$S = Join-Path $PSScriptRoot 'shot.ps1'
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$env:KUBECONFIG = Join-Path $root 'v2\_run\kubeconfig-kubeadm'
$env:MSYS_NO_PATHCONV = '1'
$go = ($From -eq '')
function Shot($name, $cmd, $lines = 40, $cols = 140) {
    if (-not $script:go) { if ($name -eq $From) { $script:go = $true } else { return } }
    if ($Only -and ($name -notlike $Only)) { return }
    if ($Skip -and ($name -like $Skip)) { return }
    $env:SHOT_CMD = $cmd; & powershell -NoProfile -ExecutionPolicy Bypass -File $S -Name $name -Shell bash -Cols $cols -Lines $lines
}
# 워커의 공인 IP 를 환경 변수 W1, W2 로 넣어 둔다. 명령 안에서 파일을 불러오면 bash -v 가 그 내용(IP)을 화면에 보여 준다
Get-Content (Join-Path $root 'v2\_run\kubeadm-public.env') | ForEach-Object { $_ -split ' ' } | ForEach-Object { $k, $v = $_ -split '=', 2; Set-Item "env:$k" $v }
$M = 'v2/tests/mask.sh'

# ── 클러스터 구축 ──
Shot '3-01-nodes' "kubectl get nodes -o wide | $M" 8 170
Shot '3-02-sg' "aws ec2 describe-security-groups --filters Name=group-name,Values=vet2-nodes --query 'SecurityGroups[0].IpPermissions[].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp,IpRanges[0].Description,UserIdGroupPairs[0].Description]' --output table | $M" 22
Shot '3-03-system' "kubectl -n kube-system get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName | grep -E 'NAME|coredns|apiserver|etcd|scheduler|controller'; kubectl -n kube-flannel get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName | tail -n +2" 16
# ── 배포와 운영 ──
Shot '3-04-pods' "kubectl -n vet2 get deploy,sts; echo; kubectl -n vet2 get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName" 26
Shot '3-05-probes' "kubectl -n vet2 describe deploy clinic | grep -E 'Replicas:|StrategyType|RollingUpdateStrategy|Liveness|Readiness|Startup|preStop|Limits|Requests|memory'" 16
Shot '3-06-ops' "v2/tests/k8s-ops.sh --base-url http://`$W1:30080 -n vet2 --new-clinic-image `$(kubectl -n vet2 get deploy clinic -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/:1.0.0`$/:1.0.1/') --only '1 2 3' 2>&1 | grep -E '■|트래픽|버전|까지' | $M" 22
# ── 노출 ──
Shot '3-07-svc' "kubectl -n vet2 get svc; echo; for p in 3306 30080; do timeout 5 bash -c `"echo > /dev/tcp/`$W1/`$p`" 2>/dev/null && echo `"이 PC → 워커1:`$p 열림`" || echo `"이 PC → 워커1:`$p 접속 안 됨`"; done" 16
Shot '3-08-scenario' "v2/tests/with-secrets.sh node v2/tests/scenario.mjs --base-url http://`$W2:30080 --db-exec 'kubectl -n vet2 exec mysql-0 --' | grep -E '^(■|시나리오)|\[실패\]|결과|11-' | $M" 40
# ── 데이터와 설정 ──
Shot '3-09-storage' "kubectl get sc; echo; kubectl get pv; echo; kubectl -n vet2 get pvc" 14
Shot '3-10-db-replace' "v2/tests/k8s-ops.sh --base-url http://`$W1:30080 -n vet2 --only 4 2>&1 | grep -E '■|트래픽|만든 예약|까지|통과|실패\]' | $M" 14
Shot '3-11-pod-replace' "v2/tests/pod-replace-check.sh --base-url http://`$W1:30080 -n vet2 --with-db | $M" 36
Shot '3-12-config' "kubectl -n vet2 get deploy clinic -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{`"  `"}{.valueFrom.configMapKeyRef.name}{.valueFrom.secretKeyRef.name}{`"\n`"}{end}' | grep -E 'vet-config|vet-db|vet-redis'; echo; kubectl -n vet2 exec deploy/clinic -- env | grep -E '^(DB_HOST|DB_POOL_MAX|SPRING_DATA_REDIS_HOST|REDIS_TLS)='; echo; kubectl -n vet2 get secret vet-db vet-redis -o go-template='{{range .items}}{{.metadata.name}}: {{range `$k,`$v := .data}}{{`$k}} {{end}}{{`"\n`"}}{{end}}'; echo; kubectl -n vet2 get deploy clinic -o yaml | grep -B1 -A3 'name: SPRING_DATASOURCE_PASSWORD'; echo; echo `"배포 정보에서 비밀번호 값이 나온 줄: `$(kubectl -n vet2 get deploy,sts -o yaml | grep -c -F -f <(sed 's/^[A-Z_]*=//' v2/_run/secrets.env))`"" 30
