# 보듬 동물병원 — 쿠버네티스 운영 동작 확인 (평가 단계 ③)
# smoke.ps1 이 "기능이 되는가"를 본다면, 이 스크립트는 쿠버네티스에서만 볼 수 있는 운영 동작을 잰다.
#   1) 무중단 배포: 요청을 계속 보내는 동안 web 과 서비스 3개를 차례로 다시 배포해 실패한 요청 수를 센다
#   2) 자동 복구: 서비스 Pod 를 지우고 다시 응답하기까지의 시간을 잰다
#   3) DB 재생성: MySQL Pod 를 지우고 초기 상태로 돌아오는지, 서비스가 재시작 없이 다시 붙는지 본다
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-k8s-ops.ps1 -Namespace dev -BaseUrl http://localhost
#
# -SkipDb  3번을 건너뛴다 (DB 가 클러스터 밖에 있어 mysql Pod 가 없을 때)
# 끝나면 실패 수를 종료 코드로 돌려준다.
param(
    [string]$Namespace = 'dev',
    [string]$BaseUrl = 'http://localhost',
    [string]$Password = 'test-only',
    [switch]$SkipDb
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent $PSScriptRoot
$BaseUrl = $BaseUrl.TrimEnd('/')
$script:pass = 0
$script:fail = 0

function Report([bool]$ok, [string]$name, [string]$detail) {
    if ($ok) { $script:pass++; Write-Host ("[통과] {0} — {1}" -f $name, $detail) }
    else { $script:fail++; Write-Host ("[실패] {0} — {1}" -f $name, $detail) }
}

function Get-Status([string]$path, [System.Net.CookieContainer]$cookies) {
    try {
        $req = [System.Net.HttpWebRequest]::Create($BaseUrl + $path)
        $req.Timeout = 3000; $req.KeepAlive = $false
        if ($cookies) { $req.CookieContainer = $cookies }
        $resp = $req.GetResponse(); $code = [int]$resp.StatusCode; $resp.Close(); return $code
    } catch {
        $we = $_.Exception
        while ($we -and -not ($we -is [System.Net.WebException])) { $we = $we.InnerException }
        if ($we -and $we.Response) { return [int]$we.Response.StatusCode }
        return 0
    }
}

# 응답한 Pod 의 이름 (서비스는 X-Served-By, web 은 X-Web-Node). 200 이 아니면 빈 문자열
function Get-Responder([string]$path, [string]$header) {
    try {
        $req = [System.Net.HttpWebRequest]::Create($BaseUrl + $path)
        $req.Timeout = 3000; $req.KeepAlive = $false
        $resp = $req.GetResponse(); $name = [string]$resp.Headers[$header]; $resp.Close(); return $name
    } catch { return '' }
}

function Get-Json([string]$path, [System.Net.CookieContainer]$cookies) {
    try {
        $req = [System.Net.HttpWebRequest]::Create($BaseUrl + $path)
        $req.Timeout = 5000; $req.KeepAlive = $false; $req.Accept = 'application/json'
        if ($cookies) { $req.CookieContainer = $cookies }
        $resp = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd(); $reader.Close(); $resp.Close()
        return (ConvertFrom-Json $text)
    } catch { return $null }
}

function Login([string]$loginId) {
    $jar = New-Object System.Net.CookieContainer
    try {
        $req = [System.Net.HttpWebRequest]::Create($BaseUrl + '/api/auth/login')
        $req.Method = 'POST'; $req.ContentType = 'application/json'; $req.CookieContainer = $jar; $req.Timeout = 5000
        $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"loginId":"' + $loginId + '","password":"' + $Password + '"}')
        $req.ContentLength = $bytes.Length
        $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
        $req.GetResponse().Close()
    } catch {}
    return $jar
}

# 조건이 참이 될 때까지 걸린 초. 시간 안에 안 되면 -1
function Measure-Until([scriptblock]$check, [int]$timeoutSeconds) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeoutSeconds) {
        if (& $check) { return [math]::Round($sw.Elapsed.TotalSeconds, 1) }
        Start-Sleep -Milliseconds 300
    }
    return -1
}

function Restarts([string]$app) {
    $n = kubectl -n $Namespace get pods -l "app=$app" -o "jsonpath={.items[*].status.containerStatuses[0].restartCount}" 2>$null
    return "$n".Trim()
}

function PodNames([string]$app) {
    return "$(kubectl -n $Namespace get pods -l "app=$app" -o 'jsonpath={.items[*].metadata.name}' 2>$null)".Trim()
}

Write-Host ("대상: {0}   네임스페이스: {1}" -f $BaseUrl, $Namespace)

# ── 1. 무중단 배포 ────────────────────────────────────────────────────
Write-Host ''
Write-Host '== 1. 무중단 배포: 요청을 보내는 동안 차례로 다시 배포 =='
kubectl -n $Namespace delete pod loadgen --ignore-not-found --wait=true 2>&1 | Out-Null
kubectl -n $Namespace apply -f (Join-Path $root 'scripts\k8s\loadgen.yaml') 2>&1 | Out-Null
kubectl -n $Namespace wait --for=condition=Ready pod/loadgen --timeout=60s 2>&1 | Out-Null
Start-Sleep -Seconds 5      # 배포 전의 평소 구간

foreach ($app in 'clinic', 'auth', 'reservation', 'web') {
    $before = PodNames $app
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    kubectl -n $Namespace rollout restart "deployment/$app" 2>&1 | Out-Null
    kubectl -n $Namespace rollout status "deployment/$app" --timeout=180s 2>&1 | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    # 옛 Pod 가 완전히 사라질 때까지 기다린다 (preStop 과 종료 처리 구간도 요청을 받아 본다)
    foreach ($name in ($before -split ' ')) { if ($name) { kubectl -n $Namespace wait --for=delete "pod/$name" --timeout=90s 2>&1 | Out-Null } }
    Report $ok "$app 다시 배포" ("{0}초, Pod {1} → {2}" -f [math]::Round($sw.Elapsed.TotalSeconds, 1), $before, (PodNames $app))
}
Start-Sleep -Seconds 5      # 배포 뒤의 평소 구간

kubectl -n $Namespace exec loadgen -- touch /tmp/stop 2>&1 | Out-Null
kubectl -n $Namespace wait --for=jsonpath='{.status.phase}'=Succeeded pod/loadgen --timeout=60s 2>&1 | Out-Null
$log = @(kubectl -n $Namespace logs loadgen 2>&1 | ForEach-Object { "$_" })
$result = $log | Where-Object { $_ -match '^RESULT total=(\d+) fail=(\d+)' } | Select-Object -Last 1
$total = 0; $failed = -1
if ($result -match 'total=(\d+) fail=(\d+)') { $total = [int]$Matches[1]; $failed = [int]$Matches[2] }
Report ($total -gt 0 -and $failed -eq 0) '배포 4번 동안 실패한 요청' ("{0}건 중 {1}건 실패" -f $total, $failed)
$log | Where-Object { $_ -match ' FAIL ' } | Select-Object -First 8 | ForEach-Object { Write-Host ("       " + $_) }
kubectl -n $Namespace delete pod loadgen --ignore-not-found --wait=false 2>&1 | Out-Null

# ── 2. 자동 복구 ──────────────────────────────────────────────────────
Write-Host ''
Write-Host '== 2. 자동 복구: 서비스 Pod 를 지운다 =='
foreach ($app in 'clinic', 'web') {
    $path = "/api/status/$app"; $header = 'X-Served-By'
    if ($app -eq 'web') { $path = '/health'; $header = 'X-Web-Node' }
    $old = PodNames $app
    kubectl -n $Namespace delete pod -l "app=$app" --wait=false 2>&1 | Out-Null
    # 지운 Pod 가 아닌 다른 Pod 가 200 으로 답할 때까지 (응답 헤더의 Pod 이름으로 구분한다)
    $script:responder = ''
    $t = Measure-Until { $script:responder = Get-Responder $path $header; ($script:responder -ne '') -and (($old -split ' ') -notcontains $script:responder) } 120
    kubectl -n $Namespace rollout status "deployment/$app" --timeout=120s 2>&1 | Out-Null
    Report ($t -ge 0) "$app Pod 를 지운 뒤 새 Pod 가 응답" ("{0}초, Pod {1} → {2}" -f $t, $old, $script:responder)
}

# ── 3. DB 재생성 ──────────────────────────────────────────────────────
Write-Host ''
Write-Host '== 3. DB 재생성: MySQL Pod 를 지운다 =='
if ($SkipDb) {
    Write-Host '건너뜀 (-SkipDb)'
} else {
    $owner = Login 'owner001'
    $pets = @(Get-Json '/api/pets' $owner)
    $made = $false
    for ($d = 1; $d -le 13 -and -not $made; $d++) {
        $date = (Get-Date).AddDays($d).ToString('yyyy-MM-dd')
        $slots = @(Get-Json "/api/slots?date=$date&type=GENERAL" $owner)
        if ($slots.Count -eq 0 -or $null -eq $slots[0]) { continue }
        try {
            $req = [System.Net.HttpWebRequest]::Create($BaseUrl + '/api/reservations')
            $req.Method = 'POST'; $req.ContentType = 'application/json'; $req.CookieContainer = $owner; $req.Timeout = 5000
            $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"petId":' + $pets[0].petId + ',"slotId":' + $slots[0].slotId + '}')
            $req.ContentLength = $bytes.Length
            $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
            $r = $req.GetResponse(); $made = ([int]$r.StatusCode -eq 201); $r.Close()
        } catch {}
    }
    $countBefore = @(Get-Json '/api/reservations/me' $owner).Count
    $restartsBefore = "{0}/{1}/{2}" -f (Restarts 'auth'), (Restarts 'clinic'), (Restarts 'reservation')
    $oldDb = PodNames 'mysql'

    kubectl -n $Namespace delete pod -l app=mysql --wait=false 2>&1 | Out-Null
    $down = Measure-Until { (Get-Status '/api/notices' $null) -eq 503 } 60
    $up = Measure-Until { (Get-Status '/api/notices' $null) -eq 200 } 180
    kubectl -n $Namespace rollout status deployment/mysql --timeout=120s 2>&1 | Out-Null
    Report ($up -ge 0) 'MySQL Pod 를 지운 뒤 다시 응답' ("끊긴 것을 확인한 뒤 {0}초, Pod {1} → {2}" -f $up, $oldDb, (kubectl -n $Namespace get pods -l app=mysql --field-selector=status.phase=Running -o 'jsonpath={.items[*].metadata.name}'))
    Report ($down -ge 0) 'DB 가 없는 동안 서비스는 죽지 않고 503 을 돌려준다' ("/api/notices 503 을 {0}초 뒤 확인" -f $down)

    $owner2 = Login 'owner001'
    $countAfter = @(Get-Json '/api/reservations/me' $owner2).Count
    Report ($made -and $countBefore -gt 3 -and $countAfter -eq 3) '데이터가 초기 상태로 돌아온다' ("owner001 의 예약 수: 지우기 전 {0} → 다시 뜬 뒤 {1} (시드는 3건)" -f $countBefore, $countAfter)
    $restartsAfter = "{0}/{1}/{2}" -f (Restarts 'auth'), (Restarts 'clinic'), (Restarts 'reservation')
    Report ($restartsBefore -eq $restartsAfter) '서비스는 재시작 없이 다시 붙는다' ("재시작 횟수 auth/clinic/reservation: {0} → {1}" -f $restartsBefore, $restartsAfter)
    Report ((Get-Status '/api/auth/me' $owner) -eq 200) 'DB 가 다시 떠도 로그인은 유지된다 (세션은 Redis 에 있다)' '지우기 전의 쿠키로 /api/auth/me 200'
}

Write-Host ''
Write-Host ("결과: 통과 {0}, 실패 {1}" -f $script:pass, $script:fail)
exit $script:fail
