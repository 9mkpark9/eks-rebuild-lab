# ⑥ 선택 과제를 실행하며 실제 터미널 화면을 캡처한다: RDS, PDB, Kustomize, 노드 장애 비교.
#   powershell -File v2/tests/shots-6.ps1 [-From <이름>] [-Only <패턴>] [-Skip <패턴>]
param([string] $From = '', [string] $Only = '', [string] $Skip = '')
$S = Join-Path $PSScriptRoot 'shot.ps1'
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$env:MSYS_NO_PATHCONV = '1'
Get-Content (Join-Path $root 'v2\_run\alb.env') | ForEach-Object { $k, $v = $_ -split '=', 2; Set-Item "env:$k" $v }
Get-Content (Join-Path $root 'v2\_run\kubeadm-public.env') | ForEach-Object { $_ -split ' ' } | ForEach-Object { $k, $v = $_ -split '=', 2; Set-Item "env:$k" $v }
$KE = Join-Path $root 'v2\_run\kubeconfig-eks'
$KK = Join-Path $root 'v2\_run\kubeconfig-kubeadm'
$go = ($From -eq '')
function Shot($name, $kube, $cmd, $lines = 30, $cols = 140) {
    if (-not $script:go) { if ($name -eq $From) { $script:go = $true } else { return } }
    if ($Only -and ($name -notlike $Only)) { return }
    if ($Skip -and ($name -like $Skip)) { return }
    $env:KUBECONFIG = $kube
    $env:SHOT_CMD = $cmd; & powershell -NoProfile -ExecutionPolicy Bypass -File $S -Name $name -Shell bash -Cols $cols -Lines $lines
}
$M = 'v2/tests/mask.sh'

# ── RDS ──
Shot '6-01-rds' $KE "aws rds describe-db-instances --db-instance-identifier vet2-db --query 'DBInstances[0].[DBInstanceIdentifier,Engine,EngineVersion,DBInstanceClass,MultiAZ,PubliclyAccessible,StorageType,StorageEncrypted,AvailabilityZone,DBSubnetGroup.DBSubnetGroupName]' --output text; aws rds describe-db-subnet-groups --db-subnet-group-name vet2-db-private --query 'DBSubnetGroups[0].Subnets[].[SubnetIdentifier,SubnetAvailabilityZone.Name]' --output text; aws ec2 describe-route-tables --filters Name=tag:Name,Values=vet2-private-rt --query 'RouteTables[0].Routes[].[DestinationCidrBlock,GatewayId]' --output text" 16
Shot '6-02-rds-sg' $KE "aws ec2 describe-security-groups --filters Name=group-name,Values=vet2-db --query 'SecurityGroups[0].IpPermissions[].[IpProtocol,FromPort,ToPort,UserIdGroupPairs[].Description|join(``,``,@)]' --output table; aws rds describe-db-instances --db-instance-identifier vet2-db --query 'DBInstances[0].MasterUserSecret.[SecretStatus,KmsKeyId]' --output text | $M" 14
Shot '6-03-rds-init' $KE "kubectl -n vet2-rds delete job db-init --ignore-not-found; v2/k8s/apply.sh eks-rds 2>&1 | grep job; kubectl -n vet2-rds wait --for=condition=complete job/db-init --timeout=300s; kubectl -n vet2-rds logs job/db-init | $M; kubectl -n vet2-rds exec deploy/clinic -- printenv DB_HOST DB_POOL_MAX | $M" 16
Shot '6-04-rds-connections' $KE "NS=vet2-rds v2/tests/rds-sql.sh `"SELECT @@max_connections max_conn, @@version ver; SHOW GLOBAL STATUS WHERE Variable_name IN ('Threads_connected','Max_used_connections','Connection_errors_max_connections'); SELECT user, COUNT(*) conns FROM information_schema.processlist GROUP BY user`"" 26
Shot '6-05-rds-scenario-eks' $KE "v2/tests/rds-check.sh http://`$A2 | grep -E '^(■|시나리오|대상)|\[실패\]|결과|11-' | $M" 40
Shot '6-06-rds-scenario-kubeadm' $KK "v2/tests/rds-check.sh http://`$W1:30081 | grep -E '\[실패\]|결과' | $M" 8
Shot '6-07-rds-reboot' $KE "v2/tests/k8s-ops.sh --base-url http://`$A2 -n vet2-rds --only 4 2>&1 | grep -E '■|rebooting|트래픽|^      /|만든 예약|까지|통과|실패\]' | $M" 20
Shot '6-08-rds-pod-replace' $KE "v2/tests/pod-replace-check.sh --base-url http://`$A2 -n vet2-rds | $M" 44
# ── PDB, Kustomize ──
Shot '6-09-pdb' $KK "v2/tests/pdb-check.sh" 56
Shot '6-10-kustomize-tree' $KK "find v2/k8s/base v2/k8s/mysql v2/k8s/components v2/k8s/overlays -name '*.yaml' | sort; echo; PYTHONIOENCODING=utf-8 python v2/tests/overlay-diff.py" 40
Shot '6-11-kustomize-apply' $KK "R=`$(kubectl -n vet2 get deploy auth -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's#/vet2-auth:.*##'); kubectl kustomize v2/k8s/overlays/kubeadm | sed `"s#ECR_REGISTRY#`$R#g`" | kubectl apply -f - --dry-run=server 2>&1 | $M" 24
# ── 노드 장애: 같은 워커를 멈췄을 때 필수 구성(DB 가 그 노드에)과 RDS 구성 ──
Shot '6-12-node-w1' $KK "v2/tests/node-down.sh i-04599621d6a4c0163 vet2-w1 `$W2 240 | $M" 54 150
