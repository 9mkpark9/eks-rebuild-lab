# 쿠버네티스에 필요한 Secret 을 만든다. Secret 은 Git 에 넣지 않으므로 클러스터마다 이 스크립트로 넣는다.
# 비밀번호는 무작위로 만들고 화면에 출력하지 않는다. 이미 있는 Secret 은 건드리지 않는다.
#
#   dev (DB 가 클러스터 안의 MySQL Pod):
#     powershell -NoProfile -ExecutionPolicy Bypass -File scripts\new-k8s-secrets.ps1 -Namespace dev
#
#   prod (DB 가 클러스터 밖, 예: RDS):
#     관리자 비밀번호는 명령줄에 적지 않고 환경 변수 VET_DB_ADMIN_PASSWORD 로 준다.
#     powershell -NoProfile -ExecutionPolicy Bypass -File scripts\new-k8s-secrets.ps1 -Namespace prod `
#         -ExternalDbHost <RDS 주소> -ExternalDbAdminUser <관리자 계정>
#
# 만드는 Secret
#   vet-db            root-password, auth-password, clinic-password, reservation-password
#   vet-redis         password
#   vet-db-external   host, admin-user, admin-password        (-ExternalDbHost 를 줬을 때만)
param(
    [Parameter(Mandatory = $true)][string]$Namespace,
    [string]$ExternalDbHost = '',
    [string]$ExternalDbAdminUser = ''
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function New-Secret {
    $bytes = New-Object byte[] 18
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

function Test-K8sSecret([string]$name) {
    kubectl -n $Namespace get secret $name 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# 네임스페이스가 없으면 만든다 (있으면 그대로)
kubectl get namespace $Namespace 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    kubectl create namespace $Namespace | Out-Null
    Write-Host "네임스페이스 $Namespace 를 만들었습니다."
}

if (Test-K8sSecret 'vet-db') {
    Write-Host 'vet-db 는 이미 있습니다. 바꾸지 않았습니다.'
} else {
    kubectl -n $Namespace create secret generic vet-db `
        "--from-literal=root-password=$(New-Secret)" `
        "--from-literal=auth-password=$(New-Secret)" `
        "--from-literal=clinic-password=$(New-Secret)" `
        "--from-literal=reservation-password=$(New-Secret)" | Out-Null
    Write-Host 'vet-db 를 만들었습니다 (비밀번호 4개).'
}

if (Test-K8sSecret 'vet-redis') {
    Write-Host 'vet-redis 는 이미 있습니다. 바꾸지 않았습니다.'
} else {
    kubectl -n $Namespace create secret generic vet-redis "--from-literal=password=$(New-Secret)" | Out-Null
    Write-Host 'vet-redis 를 만들었습니다.'
}

if ($ExternalDbHost) {
    if (-not $ExternalDbAdminUser) { Write-Host '-ExternalDbAdminUser 가 필요합니다.'; exit 1 }
    if (-not $env:VET_DB_ADMIN_PASSWORD) { Write-Host '환경 변수 VET_DB_ADMIN_PASSWORD 에 바깥 DB 의 관리자 비밀번호를 넣고 다시 실행하세요.'; exit 1 }
    if (Test-K8sSecret 'vet-db-external') {
        Write-Host 'vet-db-external 은 이미 있습니다. 바꾸지 않았습니다.'
    } else {
        kubectl -n $Namespace create secret generic vet-db-external `
            "--from-literal=host=$ExternalDbHost" `
            "--from-literal=admin-user=$ExternalDbAdminUser" `
            "--from-literal=admin-password=$($env:VET_DB_ADMIN_PASSWORD)" | Out-Null
        Write-Host 'vet-db-external 을 만들었습니다.'
    }
}

Write-Host ''
kubectl -n $Namespace get secret -o custom-columns=NAME:.metadata.name,KEYS:.data --no-headers 2>&1 |
    ForEach-Object { ($_ -replace ':[A-Za-z0-9+/=]+', '') }
