# ④ EKS 전환을 실행하며 실제 터미널 화면을 캡처한다 (필수 구성, 네임스페이스 vet2). Git Bash 에서 kubectl, aws.
#   powershell -File v2/tests/shots-4.ps1 [-From <이름>] [-Only <패턴>] [-Skip <패턴>]
param([string] $From = '', [string] $Only = '', [string] $Skip = '')
$S = Join-Path $PSScriptRoot 'shot.ps1'
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$env:KUBECONFIG = Join-Path $root 'v2\_run\kubeconfig-eks'
$env:MSYS_NO_PATHCONV = '1'
# ALB 주소를 환경 변수 A1(필수 구성), A2(RDS 구성)로 넣어 둔다
Get-Content (Join-Path $root 'v2\_run\alb.env') | ForEach-Object { $k, $v = $_ -split '=', 2; Set-Item "env:$k" $v }
$go = ($From -eq '')
function Shot($name, $cmd, $lines = 30, $cols = 140) {
    if (-not $script:go) { if ($name -eq $From) { $script:go = $true } else { return } }
    if ($Only -and ($name -notlike $Only)) { return }
    if ($Skip -and ($name -like $Skip)) { return }
    $env:SHOT_CMD = $cmd; & powershell -NoProfile -ExecutionPolicy Bypass -File $S -Name $name -Shell bash -Cols $cols -Lines $lines
}
$M = 'v2/tests/mask.sh'

Shot '4-01-cluster' "aws eks describe-cluster --name vet2-eks --query 'cluster.[name,version,status,computeConfig.enabled,storageConfig.blockStorage.enabled,kubernetesNetworkConfig.elasticLoadBalancing.enabled]' --output text; kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type,eks.amazonaws.com/compute-type | $M" 12 160
Shot '4-02-pods' "kubectl -n vet2 get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName" 16
Shot '4-03-storage' "kubectl get sc; echo; kubectl get sc vet2-ebs -o jsonpath='{.provisioner}{`"  `"}{.parameters}{`"\n`"}'; echo; kubectl -n vet2 get pvc; kubectl -n vet2 exec mysql-0 -- df -h /var/lib/mysql" 18
Shot '4-04-ingress' "kubectl get ingressclass; echo; kubectl -n vet2 get ingress web; echo; kubectl -n vet2 get ingress web -o yaml | grep -E 'alb.ingress|scheme|target-type|healthcheck|inbound' | $M; echo; curl -s -o /dev/null -w 'ALB → / : %{http_code}\n' http://`$A1/" 22
Shot '4-05-scenario' "v2/tests/with-secrets.sh node v2/tests/scenario.mjs --base-url http://`$A1 --db-exec 'kubectl -n vet2 exec mysql-0 --' | grep -E '^(■|시나리오|대상)|\[실패\]|결과|11-'" 40
Shot '4-06-ops' "v2/tests/k8s-ops.sh --base-url http://`$A1 -n vet2 --new-clinic-image `$(kubectl -n vet2 get deploy clinic -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/:1.0.0`$/:1.0.1/') --only '1 2 3' 2>&1 | grep -E '■|트래픽|버전|까지' | $M" 22
Shot '4-07-db-replace' "v2/tests/k8s-ops.sh --base-url http://`$A1 -n vet2 --only 4 2>&1 | grep -E '■|트래픽|만든 예약|까지|통과|실패\]' | $M" 14
Shot '4-08-pod-replace' "v2/tests/pod-replace-check.sh --base-url http://`$A1 -n vet2 --with-db | $M" 36
# 문제 장면 E-2: EKS 에 처음부터 있는 gp2 로 볼륨을 요청한다 (옛 드라이버 이름이라 아무도 만들어 주지 않는다)
Shot 'prob-4-e2-gp2' "kubectl create ns vet2-prob; kubectl -n vet2-prob apply -f v2/tests/prob/pvc-gp2.yaml; sleep 60; kubectl -n vet2-prob get pvc,pod; kubectl -n vet2-prob describe pvc data-gp2 | grep -A4 Events | cut -c1-200; kubectl get csidrivers; kubectl delete ns vet2-prob --wait=false" 24
