# 보듬 동물병원 — 앱 런타임 테스트 (평가 단계 ①)
# 서비스 3개를 컨테이너 없이 jar 로 직접 실행해, 웹 서버를 거치지 않고 각 서비스에 바로 요청한다.
# 확인하는 것: 서비스가 맡은 경로, auth 에서 만든 로그인 세션을 clinic 과 reservation 이 읽는지,
#              예약 흐름, 서비스별 DB 연결 수, 슬롯 자동 생성이 clinic 에만 있는지.
#
#   cd msa; .\gradlew.bat build; cd ..        (jar 3개를 먼저 만든다)
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-app.ps1
#
# 앱이 붙을 MySQL 과 Redis 만 일회용 컨테이너로 띄운다 (vet-db 이미지, redis:7-alpine).
# 비밀번호는 실행할 때마다 무작위로 만들고 화면에 출력하지 않는다. 끝나면 프로세스와 컨테이너를 모두 지운다.
# 끝나면 실패 수를 종료 코드로 돌려준다 (0 = 전부 통과).
param(
    [string]$Password = 'test-only',      # README 의 테스트 계정 공통 비밀번호
    [string]$DbImage = 'ghcr.io/9mkpark9/vet-db:1.0.0'
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $root 'build\app-test'
New-Item -ItemType Directory -Force $logDir | Out-Null

$mysql = 'vet-apptest-mysql'
$redis = 'vet-apptest-redis'
$ports = @{ auth = 18081; clinic = 18082; reservation = 18083 }
$procs = @()
$script:pass = 0
$script:fail = 0

function New-Secret { return [guid]::NewGuid().ToString('N') }
$pw = @{ root = New-Secret; auth = New-Secret; clinic = New-Secret; reservation = New-Secret; redis = New-Secret }

function Report([bool]$ok, [string]$name, [string]$detail) {
    if ($ok) { $script:pass++; Write-Host ("[통과] {0} — {1}" -f $name, $detail) }
    else { $script:fail++; Write-Host ("[실패] {0} — {1}" -f $name, $detail) }
}

# 서비스 하나에 직접 요청한다. { Status, Text, Json, ServedBy, AppVersion } 를 돌려주고 4xx·5xx 에서도 예외를 던지지 않는다.
function Invoke-Svc {
    param([string]$Service, [string]$Method, [string]$Path, [System.Net.CookieContainer]$Cookies, [string]$Body)
    $result = [pscustomobject]@{ Status = 0; Text = ''; Json = $null; ServedBy = ''; AppVersion = '' }
    try {
        $req = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$($ports[$Service])$Path")
        $req.Method = $Method
        $req.Accept = 'application/json'
        $req.Timeout = 20000
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
        $result.ServedBy = [string]$resp.Headers['X-Served-By']
        $result.AppVersion = [string]$resp.Headers['X-App-Version']
        $resp.Close()
        $t = $result.Text.TrimStart()
        if ($t.StartsWith('{') -or $t.StartsWith('[')) { try { $result.Json = ConvertFrom-Json $result.Text } catch {} }
    } catch { $result.Text = $_.Exception.Message }
    return $result
}

function Get-Items($r) { if ($null -eq $r.Json) { return @() }; return @($r.Json) }
function Brief($r) { $t = $r.Text; if ($t.Length -gt 100) { $t = $t.Substring(0, 100) + '…' }; return ("{0} {1}" -f $r.Status, $t) }
function Day([int]$offset) { return (Get-Date).AddDays($offset).ToString('yyyy-MM-dd') }

# 로그인은 auth 에만 한다. 돌려받은 쿠키 통을 다른 서비스 요청에 그대로 쓴다 (쿠키는 포트를 가리지 않는다).
function Login([string]$loginId) {
    $jar = New-Object System.Net.CookieContainer
    $r = Invoke-Svc 'auth' 'POST' '/api/auth/login' $jar ('{"loginId":"' + $loginId + '","password":"' + $Password + '"}')
    return @{ Jar = $jar; Response = $r }
}

# 서비스의 DB 계정으로 SQL 한 줄 (DB 컨테이너 안의 vet-sql). 큰따옴표는 쓰지 않는다.
function Invoke-Db([string]$account, [string]$sql) {
    $out = docker exec $mysql vet-sql $account $sql 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = (($out | ForEach-Object { "$_" }) -join ' ').Trim() }
}

try {
    $jars = @{}
    foreach ($svc in 'auth', 'clinic', 'reservation') {
        $jar = Get-ChildItem (Join-Path $root "msa\$svc-service\build\libs\vet-$svc-*.jar") -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $jar) { throw "msa\$svc-service 의 jar 가 없습니다. msa 폴더에서 .\gradlew.bat build 를 먼저 실행하세요." }
        $jars[$svc] = $jar.FullName
    }

    Write-Host '== 준비: MySQL 과 Redis (일회용 컨테이너, 내 PC 에서만 접속) =='
    docker rm -f $mysql $redis 2>&1 | Out-Null
    docker run -d --name $mysql -p 127.0.0.1:13306:3306 --tmpfs /var/lib/mysql `
        -e "MYSQL_ROOT_PASSWORD=$($pw.root)" -e "VET_AUTH_PASSWORD=$($pw.auth)" `
        -e "VET_CLINIC_PASSWORD=$($pw.clinic)" -e "VET_RESERVATION_PASSWORD=$($pw.reservation)" $DbImage | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'MySQL 컨테이너를 띄우지 못했습니다. docker compose build mysql 로 이미지를 먼저 만드세요.' }
    docker run -d --name $redis -p 127.0.0.1:16379:6379 redis:7-alpine redis-server --appendonly no --requirepass $pw.redis | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Redis 컨테이너를 띄우지 못했습니다.' }

    $users = ''
    for ($i = 0; $i -lt 60; $i++) {
        $r = Invoke-Db 'auth' 'SELECT COUNT(*) FROM users'
        if ($r.Code -eq 0) { $users = $r.Text; break }
        Start-Sleep -Seconds 2
    }
    Report ($users -eq '305') 'DB 준비 (서비스별 스키마와 시드)' "사용자 $users 명"

    # 슬롯 자동 생성을 확인하려고 마지막 이틀의 빈 슬롯을 지워 둔다. clinic 이 뜨면서 다시 채워야 한다.
    $slotsFull = (Invoke-Db 'clinic' 'SELECT COUNT(*) FROM slots').Text
    docker exec -e "MYSQL_PWD=$($pw.root)" $mysql mysql -uroot -e 'DELETE FROM vet_clinic.slots WHERE reservation_id IS NULL AND start_at >= CURDATE() + INTERVAL 12 DAY' 2>&1 | Out-Null
    $slotsCut = (Invoke-Db 'clinic' 'SELECT COUNT(*) FROM slots').Text

    Write-Host ''
    Write-Host '== 서비스 3개를 jar 로 직접 실행 =='
    $env:SPRING_DATA_REDIS_HOST = '127.0.0.1'
    $env:SPRING_DATA_REDIS_PORT = '16379'
    $env:SPRING_DATA_REDIS_PASSWORD = $pw.redis
    $env:REDIS_TLS = 'false'
    $env:DB_POOL_MAX = '3'
    $env:APP_VERSION = 'app-test'
    foreach ($svc in 'auth', 'clinic', 'reservation') {
        # 서비스마다 자기 스키마에 자기 계정으로 접속한다
        $env:SPRING_DATASOURCE_URL = "jdbc:mysql://127.0.0.1:13306/vet_${svc}?connectionTimeZone=LOCAL&characterEncoding=UTF-8"
        $env:SPRING_DATASOURCE_USERNAME = "vet_$svc"
        $env:SPRING_DATASOURCE_PASSWORD = $pw[$svc]
        $procs += Start-Process -FilePath java -PassThru -WindowStyle Hidden `
            -ArgumentList @('-Dfile.encoding=UTF-8', '-Dstdout.encoding=UTF-8', '-jar', "`"$($jars[$svc])`"", "--server.port=$($ports[$svc])") `
            -RedirectStandardOutput (Join-Path $logDir "$svc.log") -RedirectStandardError (Join-Path $logDir "$svc.err.log")
    }
    $env:SPRING_DATASOURCE_PASSWORD = $null
    $env:SPRING_DATA_REDIS_PASSWORD = $null

    foreach ($svc in 'auth', 'clinic', 'reservation') {
        $h = $null
        for ($i = 0; $i -lt 60; $i++) {
            $h = Invoke-Svc $svc 'GET' '/health' $null ''
            if ($h.Status -eq 200) { break }
            Start-Sleep -Seconds 1
        }
        Report ($h.Status -eq 200 -and $h.ServedBy -and $h.AppVersion -eq 'app-test') "$svc /health" ("{0} {1}, X-Served-By={2}, X-App-Version={3}" -f $h.Status, $h.Text, $h.ServedBy, $h.AppVersion)
    }
    # clinic 은 포트가 열린 뒤에도 슬롯을 채운다. 로그에 그 줄이 나올 때까지 기다린다.
    for ($i = 0; $i -lt 90; $i++) {
        if (@(Select-String -Path (Join-Path $logDir 'clinic.log') -Pattern 'SlotGenerator' -Encoding UTF8).Count -ge 1) { break }
        Start-Sleep -Seconds 1
    }

    Write-Host ''
    Write-Host '== 서비스가 맡은 경로 =='
    foreach ($svc in 'auth', 'clinic', 'reservation') {
        $s = Invoke-Svc $svc 'GET' "/api/status/$svc" $null ''
        Report ($s.Status -eq 200 -and $s.Json.service -eq $svc -and $s.Json.version -eq 'app-test') "상태 응답 $svc" ("{0}, 버전 {1}, 응답 {2}" -f $s.Status, $s.Json.version, $s.Json.servedBy)
    }
    $r = Invoke-Svc 'auth' 'GET' '/api/pets' $null ''
    Report ($r.Status -eq 404 -and $r.Json.code -eq 'NOT_FOUND') 'auth 에는 반려동물 경로가 없다' (Brief $r)
    $r = Invoke-Svc 'clinic' 'GET' '/api/reservations/me' $null ''
    Report ($r.Status -eq 404 -and $r.Json.code -eq 'NOT_FOUND') 'clinic 에는 예약 경로가 없다' (Brief $r)
    $r = Invoke-Svc 'reservation' 'GET' '/api/notices' $null ''
    Report ($r.Status -eq 404 -and $r.Json.code -eq 'NOT_FOUND') 'reservation 에는 공지 경로가 없다' (Brief $r)

    Write-Host ''
    Write-Host '== 로그인 세션을 세 서비스가 함께 읽는다 =='
    $r = Invoke-Svc 'clinic' 'GET' '/api/pets' $null ''
    Report ($r.Status -eq 401 -and $r.Json.code -eq 'UNAUTHORIZED') '쿠키 없이 clinic 에 요청' (Brief $r)

    $owner = Login 'owner001'
    Report ($owner.Response.Status -eq 200 -and $owner.Response.Json.role -eq 'OWNER') 'auth 에서 보호자 로그인 (owner001)' ("{0}, 역할 {1}" -f $owner.Response.Status, $owner.Response.Json.role)
    $r = Invoke-Svc 'auth' 'GET' '/api/auth/me' $owner.Jar ''
    Report ($r.Status -eq 200 -and $r.Json.loginId -eq 'owner001') 'auth 의 /api/auth/me' ("{0}, {1} ({2})" -f $r.Status, $r.Json.loginId, $r.Json.name)
    $pets = Invoke-Svc 'clinic' 'GET' '/api/pets' $owner.Jar ''
    Report ($pets.Status -eq 200 -and (Get-Items $pets).Count -eq 2) '같은 쿠키로 clinic 의 반려동물' ("{0}, {1}마리" -f $pets.Status, (Get-Items $pets).Count)
    $mine = Invoke-Svc 'reservation' 'GET' '/api/reservations/me' $owner.Jar ''
    Report ($mine.Status -eq 200 -and (Get-Items $mine).Count -eq 3) '같은 쿠키로 reservation 의 내 예약' ("{0}, {1}건" -f $mine.Status, (Get-Items $mine).Count)
    $r = Invoke-Svc 'reservation' 'GET' "/api/admin/reservations?date=$(Day 1)" $owner.Jar ''
    Report ($r.Status -eq 403) '보호자 쿠키로 간호사 경로' (Brief $r)

    Write-Host ''
    Write-Host '== 예약 흐름 (clinic 에서 시간 조회 → reservation 에 신청) =='
    $petId = [long](Get-Items $pets)[0].petId
    $made = @{ Id = 0; Date = '' }
    for ($d = 1; $d -le 13 -and $made.Id -eq 0; $d++) {
        $date = Day $d
        $slots = Get-Items (Invoke-Svc 'clinic' 'GET' "/api/slots?date=$date&type=GENERAL" $owner.Jar '')
        if ($slots.Count -eq 0) { continue }
        $c = Invoke-Svc 'reservation' 'POST' '/api/reservations' $owner.Jar ('{"petId":' + $petId + ',"slotId":' + $slots[0].slotId + '}')
        if ($c.Status -eq 201) { $made = @{ Id = [long]$c.Json.reservationId; Date = $date; SlotId = $slots[0].slotId; Slots = $slots.Count } }
        elseif ($c.Status -ne 409) { break }
    }
    Report ($made.Id -gt 0) '예약 신청' $(if ($made.Id -gt 0) { "{0} 에 빈 시간 {1}개, 예약 번호 {2}" -f $made.Date, $made.Slots, $made.Id } else { '신청하지 못함' })
    if ($made.Id -gt 0) {
        $left = Get-Items (Invoke-Svc 'clinic' 'GET' "/api/slots?date=$($made.Date)&type=GENERAL" $owner.Jar '')
        Report (@($left | Where-Object { $_.slotId -eq $made.SlotId }).Count -eq 0) '잡힌 시간은 clinic 의 목록에서 빠진다' ("남은 빈 시간 {0}개" -f $left.Count)

        $nurse = Login 'admin1'
        $list = Invoke-Svc 'reservation' 'GET' "/api/admin/reservations?date=$($made.Date)" $nurse.Jar ''
        $row = Get-Items $list | Where-Object { $_.reservationId -eq $made.Id }
        Report ($nurse.Response.Json.role -eq 'NURSE' -and $list.Status -eq 200 -and $row.status -eq 'REQUESTED') '간호사 로그인 → 예약 현황' ("{0}, 대상 예약 상태 {1}, 보호자 {2}" -f $list.Status, $row.status, $row.ownerName)
        $ap = Invoke-Svc 'reservation' 'POST' "/api/admin/reservations/$($made.Id)/approve" $nurse.Jar ''
        Report ($ap.Status -eq 200 -and $ap.Json.status -eq 'CONFIRMED') '승인' ("{0}, 승인 뒤 상태 {1}" -f $ap.Status, $ap.Json.status)

        $del = Invoke-Svc 'reservation' 'DELETE' "/api/reservations/$($made.Id)" $owner.Jar ''
        Report ($del.Status -eq 204) '보호자가 취소' ("{0}" -f $del.Status)
    }
    $director = Login 'vet1'
    $workDay = Day 1; if ((Get-Date).AddDays(1).DayOfWeek -eq 'Sunday') { $workDay = Day 2 }
    $sch = Invoke-Svc 'reservation' 'GET' "/api/director/schedule?date=$workDay" $director.Jar ''
    Report ($director.Response.Json.role -eq 'DIRECTOR' -and $sch.Status -eq 200 -and (Get-Items $sch).Count -ge 1) '원장 로그인 → 내 일정' ("{0}, {1} 진료 시간 {2}칸" -f $sch.Status, $workDay, (Get-Items $sch).Count)

    Write-Host ''
    Write-Host '== 서비스별 DB 연결과 슬롯 자동 생성 =='
    foreach ($svc in 'auth', 'clinic', 'reservation') {
        # 계정은 자기 연결만 볼 수 있다. 쉬고 있는 연결이 풀 크기(DB_POOL_MAX=3)와 같아야 한다.
        $r = Invoke-Db $svc "SELECT COUNT(*) FROM information_schema.processlist WHERE command = 'Sleep'"
        Report ($r.Text -eq '3') "vet_$svc 계정의 연결 수" "$($r.Text) (DB_POOL_MAX=3)"
    }
    $gen = @{}
    foreach ($svc in 'auth', 'clinic', 'reservation') {
        $gen[$svc] = @(Select-String -Path (Join-Path $logDir "$svc.log") -Pattern 'SlotGenerator' -Encoding UTF8).Count
    }
    $slotsNow = (Invoke-Db 'clinic' 'SELECT COUNT(*) FROM slots').Text
    Report ([int]$slotsCut -lt [int]$slotsFull -and $slotsNow -eq $slotsFull) 'clinic 이 빈 슬롯을 다시 채운다' ("슬롯 수: 처음 {0} → 지운 뒤 {1} → 서비스가 뜬 뒤 {2}" -f $slotsFull, $slotsCut, $slotsNow)
    Report ($gen.clinic -ge 1 -and $gen.auth -eq 0 -and $gen.reservation -eq 0) '슬롯 자동 생성은 clinic 에만' ("로그 줄 수: auth {0}, clinic {1}, reservation {2}" -f $gen.auth, $gen.clinic, $gen.reservation)

    Write-Host ''
    Write-Host '== auth 에서 로그아웃하면 다른 서비스에서도 끝난다 =='
    $out = Invoke-Svc 'auth' 'POST' '/api/auth/logout' $owner.Jar ''
    $after = Invoke-Svc 'clinic' 'GET' '/api/pets' $owner.Jar ''
    Report ($out.Status -eq 204 -and $after.Status -eq 401) '로그아웃 뒤 같은 쿠키로 clinic' ("로그아웃 {0}, clinic {1}" -f $out.Status, $after.Status)
}
catch {
    Write-Host ("[오류] " + $_.Exception.Message)
    $script:fail++
}
finally {
    foreach ($p in $procs) { if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -Confirm:$false } }
    docker rm -f $mysql $redis 2>&1 | Out-Null
}

Write-Host ''
Write-Host ("결과: 통과 {0}, 실패 {1}   (서비스 로그: build\app-test)" -f $script:pass, $script:fail)
exit $script:fail
