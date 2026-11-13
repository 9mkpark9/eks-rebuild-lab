# 보듬 동물병원 — 동작 확인 스크립트
# web 을 통해 실제 화면이 쓰는 API 를 순서대로 부르고 통과/실패를 출력한다.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\smoke.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\smoke.ps1 -BaseUrl http://localhost:8088 -Isolation none
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\smoke.ps1 -BaseUrl http://localhost -Isolation k8s -Namespace dev
#
# -Isolation  서비스 격리 확인(5번)에서 서비스를 멈추는 방법
#               compose  docker compose stop/start (기본)
#               k8s      kubectl scale --replicas=0/1
#               none     5번과 DB 경계 확인을 건너뛴다
# -NoDbCheck  DB 경계 확인만 건너뛴다 (DB 가 클러스터 밖의 RDS 라 mysql 컨테이너가 없을 때)
# 끝나면 실패 수를 종료 코드로 돌려준다 (0 = 전부 통과).
# 만든 예약은 스크립트가 취소하므로 여러 번 돌려도 된다.
param(
    [string]$BaseUrl = '',
    [ValidateSet('compose', 'k8s', 'none')][string]$Isolation = 'compose',
    [string]$Namespace = 'dev',
    [string]$Password = 'test-only',      # README 의 테스트 계정 공통 비밀번호
    [switch]$NoDbCheck,
    [int]$WaitSeconds = 180
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent $PSScriptRoot

if (-not $BaseUrl) {
    $port = '8088'
    $envFile = Join-Path $root '.env'
    if (Test-Path $envFile) {
        $line = Get-Content -LiteralPath $envFile | Where-Object { $_ -match '^WEB_PORT=(\d+)' } | Select-Object -First 1
        if ($line -match '^WEB_PORT=(\d+)') { $port = $Matches[1] }
    }
    $BaseUrl = "http://localhost:$port"
}
$BaseUrl = $BaseUrl.TrimEnd('/')

$script:pass = 0
$script:fail = 0
$script:savedReplicas = @{}

function Report([bool]$ok, [string]$name, [string]$detail) {
    if ($ok) { $script:pass++; Write-Host ("[통과] {0} — {1}" -f $name, $detail) }
    else { $script:fail++; Write-Host ("[실패] {0} — {1}" -f $name, $detail) }
}

# 응답을 { Status, Text, Json, WebNode, WebVersion, ServedBy, AppVersion } 로 돌려준다. 4xx·5xx 에서도 예외를 던지지 않는다.
# Invoke-WebRequest 는 PowerShell 5.1 에서 한글 본문을 깨뜨리고 오류 응답의 본문을 숨기므로 쓰지 않는다.
function Invoke-Api {
    param([string]$Method, [string]$Path, [System.Net.CookieContainer]$Cookies, [string]$Body)
    $result = [pscustomobject]@{ Status = 0; Text = ''; Json = $null; WebNode = ''; WebVersion = ''; ServedBy = ''; AppVersion = '' }
    try {
        $req = [System.Net.HttpWebRequest]::Create($BaseUrl + $Path)
        $req.Method = $Method
        $req.Accept = 'application/json'
        $req.Timeout = 20000
        $req.AllowAutoRedirect = $false
        $req.KeepAlive = $false
        if ($Cookies) { $req.CookieContainer = $Cookies }
        if ($Body) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
            $req.ContentType = 'application/json'
            $req.ContentLength = $bytes.Length
            $stream = $req.GetRequestStream(); $stream.Write($bytes, 0, $bytes.Length); $stream.Close()
        } elseif ($Method -eq 'POST' -or $Method -eq 'PUT') {
            $req.ContentLength = 0
        }
        $resp = $null
        try { $resp = $req.GetResponse() }
        catch {
            $we = $_.Exception
            while ($we -and -not ($we -is [System.Net.WebException])) { $we = $we.InnerException }
            if ($we -and $we.Response) { $resp = $we.Response } else { $result.Text = $_.Exception.Message; return $result }
        }
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $result.Text = $reader.ReadToEnd(); $reader.Close()
        $result.Status = [int]$resp.StatusCode
        $result.WebNode = [string]$resp.Headers['X-Web-Node']
        $result.WebVersion = [string]$resp.Headers['X-Web-Version']
        $result.ServedBy = [string]$resp.Headers['X-Served-By']
        $result.AppVersion = [string]$resp.Headers['X-App-Version']
        $resp.Close()
        if ($result.Text -and $result.Text.TrimStart().StartsWith('{') -or $result.Text.TrimStart().StartsWith('[')) {
            try { $result.Json = ConvertFrom-Json $result.Text } catch {}
        }
    } catch { $result.Text = $_.Exception.Message }
    return $result
}

# JSON 배열 응답의 항목들 (빈 배열이면 0개)
function Get-Items($r) {
    if ($null -eq $r.Json) { return @() }
    return @($r.Json)
}

function Brief($r) {
    $t = $r.Text; if ($t.Length -gt 110) { $t = $t.Substring(0, 110) + '…' }
    return ("{0} {1}" -f $r.Status, $t)
}

function Day([int]$offset) { return (Get-Date).AddDays($offset).ToString('yyyy-MM-dd') }

function Login([string]$loginId) {
    $jar = New-Object System.Net.CookieContainer
    $body = '{"loginId":"' + $loginId + '","password":"' + $Password + '"}'
    $r = Invoke-Api 'POST' '/api/auth/login' $jar $body
    return @{ Jar = $jar; Response = $r }
}

function Wait-Until([scriptblock]$check, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if (& $check) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

# 예약 가능한 시간을 찾아 신청한다. 같은 날 이미 예약이 있으면(409) 다음 날로 넘어간다.
function New-Reservation($jar, [long]$petId, [int]$fromDay) {
    $found = @{ Id = 0; Date = ''; Slots = 0; Last = $null }
    for ($d = $fromDay; $d -le 13; $d++) {
        $date = Day $d
        $s = Invoke-Api 'GET' "/api/slots?date=$date&type=GENERAL" $jar ''
        $found.Last = $s
        if ($s.Status -ne 200) { return $found }
        $slots = Get-Items $s
        if ($slots.Count -eq 0) { continue }              # 일요일(휴진)이거나 마감
        $body = '{"petId":' + $petId + ',"slotId":' + $slots[0].slotId + '}'
        $c = Invoke-Api 'POST' '/api/reservations' $jar $body
        $found.Last = $c
        if ($c.Status -eq 201) { $found.Id = [long]$c.Json.reservationId; $found.Date = $date; $found.Slots = $slots.Count; return $found }
        if ($c.Status -ne 409) { return $found }
    }
    return $found
}

# 2번: 반려동물 목록 → 예약 가능 시간 조회 → 예약 신청 → 내 예약 조회 → 취소
function Test-OwnerFlow($jar, [string]$label) {
    $pets = Invoke-Api 'GET' '/api/pets' $jar ''
    $petList = Get-Items $pets
    Report ($pets.Status -eq 200 -and $petList.Count -ge 1) "$label 반려동물 목록" ("{0}, {1}마리, 처리 {2}" -f $pets.Status, $petList.Count, $pets.ServedBy)
    if ($petList.Count -lt 1) { return }

    $n = New-Reservation $jar ([long]$petList[0].petId) 1
    Report ($n.Id -gt 0) "$label 예약 가능 시간 조회 → 예약 신청" $(if ($n.Id -gt 0) { "{0} 에 빈 시간 {1}개, 예약 번호 {2}, 처리 {3}" -f $n.Date, $n.Slots, $n.Id, $n.Last.ServedBy } else { Brief $n.Last })
    if ($n.Id -le 0) { return }

    $mine = Invoke-Api 'GET' '/api/reservations/me' $jar ''
    $row = Get-Items $mine | Where-Object { $_.reservationId -eq $n.Id }
    Report ($mine.Status -eq 200 -and $row -and $row.status -eq 'REQUESTED') "$label 내 예약 조회" ("{0}, 방금 신청한 예약 상태 {1}" -f $mine.Status, $row.status)

    $del = Invoke-Api 'DELETE' "/api/reservations/$($n.Id)" $jar ''
    $after = Invoke-Api 'GET' '/api/reservations/me' $jar ''
    $row2 = Get-Items $after | Where-Object { $_.reservationId -eq $n.Id }
    Report ($del.Status -eq 204 -and $row2 -and $row2.status -eq 'CANCELLED') "$label 예약 취소" ("{0}, 취소 뒤 상태 {1}" -f $del.Status, $row2.status)
}

function Set-Service([string]$name, [bool]$running) {
    Push-Location $root
    try {
        if ($Isolation -eq 'compose') {
            if ($running) { docker compose start $name 2>&1 | Out-Null } else { docker compose stop $name 2>&1 | Out-Null }
        } elseif ($Isolation -eq 'k8s') {
            # 멈출 때 원래 복제본 수를 적어 두고, 켤 때 그 수로 되돌린다 (prod 는 2개다)
            if ($running) {
                $count = $script:savedReplicas[$name]; if (-not $count) { $count = 1 }
                kubectl -n $Namespace scale "deployment/$name" "--replicas=$count" 2>&1 | Out-Null
            } else {
                $script:savedReplicas[$name] = [int](kubectl -n $Namespace get "deployment/$name" -o "jsonpath={.spec.replicas}")
                kubectl -n $Namespace scale "deployment/$name" "--replicas=0" 2>&1 | Out-Null
            }
        }
    } finally { Pop-Location }
}

# 멈춘 서비스의 경로는 HTML 오류 페이지가 아니라 { code, message } JSON 503 이어야 한다
function Test-Down([string]$label, [string]$path, $jar) {
    $r = $null
    $ok = Wait-Until { $script:down = Invoke-Api 'GET' $path $jar ''; ($script:down.Status -eq 503 -and $script:down.Json -and $script:down.Json.code -eq 'SERVICE_UNAVAILABLE') } 40
    $r = $script:down
    Report $ok "$label 멈춘 서비스 경로는 503 JSON" ("{0} → {1}" -f $path, (Brief $r))
}

# 상태 쪽지(/status)가 읽는 응답: 멈춘 서비스의 줄만 503 이고 나머지는 200 이어야 한다
function Test-StatusRows([string]$label, [string]$stopped) {
    $parts = @()
    $ok = $true
    foreach ($svc in 'auth', 'clinic', 'reservation') {
        $s = Invoke-Api 'GET' "/api/status/$svc" $null ''
        $parts += ("{0} {1}" -f $svc, $s.Status)
        if ($svc -eq $stopped) { if ($s.Status -ne 503) { $ok = $false } }
        elseif ($s.Status -ne 200) { $ok = $false }
    }
    Report $ok "$label 상태 쪽지는 그 줄만 응답 없음" ($parts -join ', ')
}

# 서비스의 DB 계정으로 SQL 한 줄을 실행한다 (DB 컨테이너 안의 vet-sql). { Code, Text } 를 돌려준다.
# SQL 에는 따옴표를 쓰지 않는다. PowerShell 5.1 이 외부 명령에 넘길 때 따옴표를 망가뜨린다.
function Invoke-Db([string]$account, [string]$sql) {
    Push-Location $root
    try {
        if ($Isolation -eq 'k8s') { $out = kubectl -n $Namespace exec deploy/mysql -- vet-sql $account $sql 2>&1 }
        else { $out = docker compose exec -T mysql vet-sql $account $sql 2>&1 }
        $text = (($out | ForEach-Object { "$_" }) -join ' ').Trim()
        if ($text.Length -gt 90) { $text = $text.Substring(0, 90) + '…' }
        return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $text }
    } finally { Pop-Location }
}

function Test-DbAllowed([string]$name, [string]$account, [string]$sql) {
    $r = Invoke-Db $account $sql
    Report ($r.Code -eq 0) $name ("vet_{0}: 허용됨 {1}" -f $account, $r.Text)
}

function Test-DbDenied([string]$name, [string]$account, [string]$sql) {
    $r = Invoke-Db $account $sql
    Report ($r.Code -ne 0 -and $r.Text -match 'denied|Unknown column') $name ("vet_{0}: {1}" -f $account, $(if ($r.Code -eq 0) { '허용됨 (막혀야 한다)' } else { $r.Text }))
}

Write-Host ("대상: {0}   격리 확인 방식: {1}" -f $BaseUrl, $Isolation)

# ── 0. 준비: 어떤 순서로 떴든 전부 응답할 때까지 기다린다 ─────────────
Write-Host ''
Write-Host '== 0. 준비 =='
$ok = Wait-Until { (Invoke-Api 'GET' '/health' $null '').Status -eq 200 } $WaitSeconds
$h = Invoke-Api 'GET' '/health' $null ''
Report $ok 'web /health' ("{0} {1}, X-Web-Node={2}, X-Web-Version={3}" -f $h.Status, $h.Text, $h.WebNode, $h.WebVersion)
if (-not $ok) { Write-Host '웹 서버가 응답하지 않아 중단합니다.'; exit 1 }

$ok = Wait-Until { (Invoke-Api 'GET' '/api/notices' $null '').Status -eq 200 } $WaitSeconds
$r = Invoke-Api 'GET' '/api/notices' $null ''
Report $ok 'clinic 준비 (/api/notices)' ("{0}, 공지 {1}건, 처리 {2}" -f $r.Status, (Get-Items $r).Count, $r.ServedBy)

$ok = Wait-Until { (Login 'owner001').Response.Status -eq 200 } $WaitSeconds
Report $ok 'auth 준비 (로그인 가능)' $(if ($ok) { 'DB 와 Redis 에 연결됨' } else { Brief (Login 'owner001').Response })

$probe = Login 'owner001'
$ok = Wait-Until { (Invoke-Api 'GET' '/api/reservations/me' $probe.Jar '').Status -eq 200 } $WaitSeconds
$r = Invoke-Api 'GET' '/api/reservations/me' $probe.Jar ''
Report $ok 'reservation 준비 (/api/reservations/me)' ("{0}, 처리 {1}" -f $r.Status, $r.ServedBy)

$home1 = Invoke-Api 'GET' '/' $null ''
$app1 = Invoke-Api 'GET' '/app/reserve' $null ''
Report ($home1.Status -eq 200 -and $app1.Status -eq 200) '홈과 예약 화면' ("/ {0}, /app/reserve {1}" -f $home1.Status, $app1.Status)

# ── 1. 보호자 로그인 → /api/auth/me ───────────────────────────────────
Write-Host ''
Write-Host '== 1. 보호자 로그인 =='
$owner = Login 'owner001'
Report ($owner.Response.Status -eq 200 -and $owner.Response.Json.role -eq 'OWNER') '1 보호자 로그인 (owner001)' ("{0}, 역할 {1}, 처리 {2}" -f $owner.Response.Status, $owner.Response.Json.role, $owner.Response.ServedBy)
$me = Invoke-Api 'GET' '/api/auth/me' $owner.Jar ''
Report ($me.Status -eq 200 -and $me.Json.loginId -eq 'owner001') '1 /api/auth/me' ("{0}, {1} ({2})" -f $me.Status, $me.Json.loginId, $me.Json.name)

# ── 2. 반려동물 → 예약 가능 시간 → 신청 → 내 예약 → 취소 ──────────────
Write-Host ''
Write-Host '== 2. 보호자 예약 흐름 =='
Test-OwnerFlow $owner.Jar '2'

# ── 3. 간호사 로그인 → 예약 현황 → 승인 ───────────────────────────────
Write-Host ''
Write-Host '== 3. 간호사 =='
$pets = Get-Items (Invoke-Api 'GET' '/api/pets' $owner.Jar '')
$forNurse = @{ Id = 0 }
if ($pets.Count -ge 1) { $forNurse = New-Reservation $owner.Jar ([long]$pets[0].petId) 1 }
Report ($forNurse.Id -gt 0) '3 승인받을 예약 준비 (보호자가 신청)' $(if ($forNurse.Id -gt 0) { "{0}, 예약 번호 {1}" -f $forNurse.Date, $forNurse.Id } else { Brief $forNurse.Last })

$nurse = Login 'admin1'
Report ($nurse.Response.Status -eq 200 -and $nurse.Response.Json.role -eq 'NURSE') '3 간호사 로그인 (admin1)' ("{0}, 역할 {1}" -f $nurse.Response.Status, $nurse.Response.Json.role)
if ($forNurse.Id -gt 0) {
    $list = Invoke-Api 'GET' "/api/admin/reservations?date=$($forNurse.Date)" $nurse.Jar ''
    $row = Get-Items $list | Where-Object { $_.reservationId -eq $forNurse.Id }
    Report ($list.Status -eq 200 -and $row -and $row.status -eq 'REQUESTED') '3 예약 현황' ("{0}, {1} 예약 {2}건, 대상 예약 상태 {3}, 처리 {4}" -f $list.Status, $forNurse.Date, (Get-Items $list).Count, $row.status, $list.ServedBy)
    $ap = Invoke-Api 'POST' "/api/admin/reservations/$($forNurse.Id)/approve" $nurse.Jar ''
    Report ($ap.Status -eq 200 -and $ap.Json.status -eq 'CONFIRMED') '3 승인' ("{0}, 승인 뒤 상태 {1}" -f $ap.Status, $ap.Json.status)
    $cleanup = Invoke-Api 'DELETE' "/api/reservations/$($forNurse.Id)" $owner.Jar ''
    Report ($cleanup.Status -eq 204) '3 뒷정리 (보호자가 취소)' ("{0}" -f $cleanup.Status)
}

# ── 4. 원장 로그인 → 내 일정 ──────────────────────────────────────────
Write-Host ''
Write-Host '== 4. 원장 =='
$director = Login 'vet1'
Report ($director.Response.Status -eq 200 -and $director.Response.Json.role -eq 'DIRECTOR') '4 원장 로그인 (vet1)' ("{0}, 역할 {1}, vetId {2}" -f $director.Response.Status, $director.Response.Json.role, $director.Response.Json.vetId)
$workDay = Day 1; if ((Get-Date).AddDays(1).DayOfWeek -eq 'Sunday') { $workDay = Day 2 }
$sch = Invoke-Api 'GET' "/api/director/schedule?date=$workDay" $director.Jar ''
Report ($sch.Status -eq 200 -and (Get-Items $sch).Count -ge 1) '4 내 일정' ("{0}, {1} 진료 시간 {2}칸, 처리 {3}" -f $sch.Status, $workDay, (Get-Items $sch).Count, $sch.ServedBy)

# ── 버전과 상태 쪽지: 서비스마다 버전과 응답한 서버를 알려 준다 ───────
Write-Host ''
Write-Host '== 버전과 상태 쪽지 =='
foreach ($svc in 'auth', 'clinic', 'reservation') {
    $s = Invoke-Api 'GET' "/api/status/$svc" $null ''
    $good = ($s.Status -eq 200 -and $s.Json -and $s.Json.service -eq $svc -and $s.Json.version -and $s.AppVersion -eq $s.Json.version)
    Report $good "상태 $svc (/api/status/$svc)" $(if ($s.Status -eq 200) { "{0}, 버전 {1}, 응답 {2}" -f $s.Status, $s.Json.version, $s.Json.servedBy } else { Brief $s })
}
$page = Invoke-Api 'GET' '/status' $null ''
Report ($page.Status -eq 200 -and $page.WebVersion) '상태 쪽지 화면 (/status)' ("{0}, web 버전 {1}, 응답 {2}" -f $page.Status, $page.WebVersion, $page.WebNode)

# ── DB 경계: 서비스 계정은 자기 스키마만 쓰고, 남의 데이터는 뷰로 읽기만 한다 ──
Write-Host ''
Write-Host '== DB 경계 =='
if ($Isolation -eq 'none' -or $NoDbCheck) {
    Write-Host '건너뜀'
} else {
    Test-DbAllowed 'auth 가 자기 사용자 테이블 읽기' 'auth' 'SELECT COUNT(*) FROM users'
    Test-DbDenied  'auth 가 예약 읽기' 'auth' 'SELECT COUNT(*) FROM vet_reservation.reservations'
    Test-DbDenied  'clinic 이 사용자 읽기' 'clinic' 'SELECT COUNT(*) FROM vet_auth.users'
    Test-DbDenied  'clinic 이 예약 지우기' 'clinic' 'DELETE FROM vet_reservation.reservations WHERE reservation_id = 0'
    Test-DbAllowed 'reservation 이 뷰로 보호자 읽기' 'reservation' 'SELECT COUNT(*) FROM users'
    Test-DbDenied  'reservation 이 비밀번호 해시 읽기 (뷰)' 'reservation' 'SELECT password_hash FROM users LIMIT 1'
    Test-DbDenied  'reservation 이 사용자 원본 테이블 읽기' 'reservation' 'SELECT COUNT(*) FROM vet_auth.users'
    Test-DbDenied  'reservation 이 반려동물 고치기' 'reservation' 'UPDATE pets SET age = age WHERE pet_id = 1'
    Test-DbDenied  'reservation 이 진료 시각 고치기' 'reservation' 'UPDATE slots SET start_at = start_at WHERE slot_id = 1'
    Test-DbDenied  'reservation 이 진료 시간 지우기' 'reservation' 'DELETE FROM slots WHERE slot_id = 0'
}

# ── 5. 서비스 격리: 하나가 멈춰도 다른 서비스 경로는 정상이어야 한다 ───
Write-Host ''
Write-Host '== 5. 서비스 격리 =='
if ($Isolation -eq 'none') {
    Write-Host '건너뜀 (-Isolation none)'
} else {
    $workDate = $workDay

    Write-Host '-- auth 를 멈춘 상태'
    Set-Service 'auth' $false
    try {
        Test-Down '5-1' '/api/auth/me' $owner.Jar
        Test-StatusRows '5-1' 'auth'
        Test-OwnerFlow $owner.Jar '5-1 (이미 로그인한 세션)'
    } finally { Set-Service 'auth' $true }
    $ok = Wait-Until { (Invoke-Api 'GET' '/api/auth/me' $owner.Jar '').Status -eq 200 } $WaitSeconds
    Report $ok '5-1 auth 를 다시 켜면 복구' ("/api/auth/me {0}" -f (Invoke-Api 'GET' '/api/auth/me' $owner.Jar '').Status)

    Write-Host '-- clinic 을 멈춘 상태'
    Set-Service 'clinic' $false
    try {
        Test-Down '5-2' '/api/notices' $null
        Test-StatusRows '5-2' 'clinic'
        $r = Invoke-Api 'GET' '/api/reservations/me' $owner.Jar ''
        Report ($r.Status -eq 200) '5-2 내 예약 조회' ("{0}, {1}건" -f $r.Status, (Get-Items $r).Count)
        $r = Invoke-Api 'GET' "/api/admin/reservations?date=$workDate" $nurse.Jar ''
        Report ($r.Status -eq 200) '5-2 간호사 예약 현황' ("{0}, {1}건" -f $r.Status, (Get-Items $r).Count)
        $r = Invoke-Api 'GET' "/api/admin/slots?date=$workDate" $nurse.Jar ''
        Report ($r.Status -eq 200) '5-2 간호사 진료 시간 조회' ("{0}, {1}칸" -f $r.Status, (Get-Items $r).Count)
        $r = Invoke-Api 'GET' "/api/director/schedule?date=$workDate" $director.Jar ''
        Report ($r.Status -eq 200) '5-2 원장 내 일정' ("{0}, {1}칸" -f $r.Status, (Get-Items $r).Count)
        $r = Invoke-Api 'GET' '/api/director/stats' $director.Jar ''
        Report ($r.Status -eq 200) '5-2 원장 병원 현황' ("{0}" -f $r.Status)
    } finally { Set-Service 'clinic' $true }
    $ok = Wait-Until { (Invoke-Api 'GET' '/api/notices' $null '').Status -eq 200 } $WaitSeconds
    Report $ok '5-2 clinic 을 다시 켜면 복구' ("/api/notices {0}" -f (Invoke-Api 'GET' '/api/notices' $null '').Status)

    Write-Host '-- reservation 을 멈춘 상태'
    Set-Service 'reservation' $false
    try {
        Test-Down '5-3' '/api/reservations/me' $owner.Jar
        Test-StatusRows '5-3' 'reservation'
        $r = Invoke-Api 'GET' '/api/notices' $null ''
        Report ($r.Status -eq 200) '5-3 공지' ("{0}, {1}건" -f $r.Status, (Get-Items $r).Count)
        $r = Invoke-Api 'GET' '/api/pets' $owner.Jar ''
        Report ($r.Status -eq 200) '5-3 반려동물' ("{0}, {1}마리" -f $r.Status, (Get-Items $r).Count)
        $r = Invoke-Api 'GET' "/api/slots?date=$workDate&type=GENERAL" $owner.Jar ''
        Report ($r.Status -eq 200) '5-3 예약 가능 시간' ("{0}, {1}개" -f $r.Status, (Get-Items $r).Count)
        $r = Invoke-Api 'GET' '/' $null ''
        Report ($r.Status -eq 200) '5-3 홈 화면' ("{0}" -f $r.Status)
    } finally { Set-Service 'reservation' $true }
    $ok = Wait-Until { (Invoke-Api 'GET' '/api/reservations/me' $owner.Jar '').Status -eq 200 } $WaitSeconds
    Report $ok '5-3 reservation 을 다시 켜면 복구' ("/api/reservations/me {0}" -f (Invoke-Api 'GET' '/api/reservations/me' $owner.Jar '').Status)
}

Write-Host ''
Write-Host ("결과: 통과 {0}, 실패 {1}" -f $script:pass, $script:fail)
exit $script:fail
