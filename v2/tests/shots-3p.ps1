# ③ 문제 장면을 kubeadm 에서 다시 일으켜 실제 터미널 화면을 캡처한다. 운영 중인 vet2, vet2-rds 와 섞이지 않게
# vet2-prob, vet2-v0 네임스페이스에서 하고 끝나면 지운다.
#   powershell -File v2/tests/shots-3p.ps1 [-From <이름>]
param([string] $From = '', [string] $Only = '', [string] $Skip = '')
$S = Join-Path $PSScriptRoot 'shot.ps1'
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$env:KUBECONFIG = Join-Path $root 'v2\_run\kubeconfig-kubeadm'
$env:MSYS_NO_PATHCONV = '1'
Get-Content (Join-Path $root 'v2\_run\kubeadm-public.env') | ForEach-Object { $_ -split ' ' } | ForEach-Object { $k, $v = $_ -split '=', 2; Set-Item "env:$k" $v }
$go = ($From -eq '')
function Shot($name, $cmd, $lines = 30, $cols = 140) {
    if (-not $script:go) { if ($name -eq $From) { $script:go = $true } else { return } }
    if ($Only -and ($name -notlike $Only)) { return }
    if ($Skip -and ($name -like $Skip)) { return }
    $env:SHOT_CMD = $cmd; & powershell -NoProfile -ExecutionPolicy Bypass -File $S -Name $name -Shell bash -Cols $cols -Lines $lines
}
$M = 'v2/tests/mask.sh'
$IMG = "`$(kubectl -n vet2 get deploy auth -o jsonpath='{.spec.template.spec.containers[0].image}')"

# K-5: ECR 로그인 Secret 이 없는 네임스페이스에서 ECR 이미지를 받으려 한다
Shot 'prob-3-k5-imagepull' "kubectl create ns vet2-prob; kubectl -n vet2-prob run pull-test --image=$IMG --image-pull-policy=Always --restart=Never; sleep 30; kubectl -n vet2-prob get pod pull-test; kubectl -n vet2-prob describe pod pull-test | grep -E 'Failed|BackOff' | head -3 | cut -c1-230 | $M" 18
# K-6: StorageClass 를 정하지 않은 볼륨 요청 (기본 StorageClass 도, 맞는 PV 도 없다)
Shot 'prob-3-k6-pvc-pending' "kubectl get sc; kubectl -n vet2-prob apply -f v2/tests/prob/pvc-no-class.yaml; sleep 8; kubectl -n vet2-prob get pvc data-test; kubectl -n vet2-prob describe pvc data-test | grep -A3 Events" 18
# K-7: StatefulSet 의 볼륨 요청 틀을 바꿔 다시 적용한다
Shot 'prob-3-k7-sts-forbidden' "kubectl -n vet2-prob apply -f v2/tests/prob/sts-a.yaml; diff v2/tests/prob/sts-a.yaml v2/tests/prob/sts-b.yaml; kubectl -n vet2-prob apply -f v2/tests/prob/sts-b.yaml" 18
# K-12: kubeadm 에는 LoadBalancer 를 처리할 것이 없다
Shot 'prob-3-k12-lb-pending' "kubectl -n vet2-prob create deployment lb-test --image=registry.k8s.io/pause:3.10; kubectl -n vet2-prob expose deployment lb-test --port 80 --type LoadBalancer; sleep 40; kubectl -n vet2-prob get svc lb-test; kubectl delete ns vet2-prob --wait=false" 14
# K-1 ~ K-4: 가장 단순한 배포(v0)
Shot 'prob-3-v0-up' "v2/tests/prob/v0-kubeadm.sh up" 26
Shot 'prob-3-k3-secret' "kubectl -n vet2-v0 get deploy auth -o yaml | grep -A1 'name: SPRING_DATASOURCE_PASSWORD' | sed -E 's/value: .*/value: ******** (캡처에서만 가림. 실제로는 비밀번호 글자가 그대로 있다)/'; echo; echo `"배포 정보에서 비밀번호 값이 나온 줄: `$(kubectl -n vet2-v0 get deploy -o yaml | grep -c -F -f <(sed 's/^[A-Z_]*=//' v2/_run/secrets.env))`"" 12
Shot 'prob-3-k4-besteffort' "kubectl -n vet2-v0 get pods -o custom-columns=POD:.metadata.name,QOS:.status.qosClass,REQUESTS:.spec.containers[0].resources.requests,LIMITS:.spec.containers[0].resources.limits" 12
Shot 'prob-3-k1-rollout' "v2/tests/k8s-ops.sh --base-url http://`$W1:30081 -n vet2-v0 --new-clinic-image `$(kubectl -n vet2-v0 get deploy clinic -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/:1.0.0`$/:1.0.1/') --only '1 2' 2>&1 | grep -E '■|트래픽|^      /|버전' | head -24 | $M" 30
Shot 'prob-3-k2-data-lost' "v2/tests/k8s-ops.sh --base-url http://`$W1:30081 -n vet2-v0 --only 4 2>&1 | grep -E '■|트래픽|만든 예약|까지|통과|실패\]' | $M" 14
Shot 'prob-3-v0-down' "v2/tests/prob/v0-kubeadm.sh down" 10
