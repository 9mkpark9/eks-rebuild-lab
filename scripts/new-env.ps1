# .env.example 을 복사해 비밀번호를 무작위 값으로 채운 .env 를 만든다.
# 이미 .env 가 있으면 건드리지 않는다. 만든 값은 화면에 출력하지 않는다.
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\new-env.ps1
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent $PSScriptRoot
$example = Join-Path $root '.env.example'
$target = Join-Path $root '.env'

if (Test-Path $target) {
    Write-Host '.env 가 이미 있습니다. 바꾸지 않았습니다.'
    exit 0
}

function New-Secret {
    $bytes = New-Object byte[] 18
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

$lines = Get-Content -LiteralPath $example -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^(DB_ROOT_PASSWORD|DB_PASSWORD|REDIS_PASSWORD)=\s*$') { "$($Matches[1])=$(New-Secret)" } else { $_ }
}
# compose 는 BOM 이 붙은 .env 의 첫 줄을 읽지 못한다. BOM 없이 쓴다.
[System.IO.File]::WriteAllLines($target, $lines, (New-Object System.Text.UTF8Encoding($false)))
Write-Host '.env 를 만들었습니다 (비밀번호 3개를 무작위로 채움).'
