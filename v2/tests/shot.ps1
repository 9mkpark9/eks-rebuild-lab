# 실제 터미널 화면 캡처: 새 콘솔 창을 열어 명령을 실행하고, 끝나면 그 창이 화면에 보이는 그대로를 PNG 로 저장한다.
# 그림을 그리거나 고치지 않는다. 캡처한 픽셀 그대로다.
#
#   powershell -File v2/tests/shot.ps1 -Name w1-build -Shell wsl  -Cmd "cd ~/vet2-lab/msa && ./gradlew build"
#   powershell -File v2/tests/shot.ps1 -Name k8s-nodes -Shell bash -Cmd "kubectl get nodes"
#     -Shell wsl  : WSL 2 Ubuntu 의 bash 에서 실행
#     -Shell bash : 이 PC 의 Git Bash 에서 실행 (kubectl, aws)
#     -Cols/-Lines: 창 크기 (글자 수). 출력이 창보다 길면 마지막 화면만 남으므로 명령에서 줄여 보여 준다
# 저장: v2/docs/img/shot/<Name>.png
param(
    [Parameter(Mandatory)] [string] $Name,
    [string] $Cmd = '',
    [ValidateSet('wsl', 'bash')] [string] $Shell = 'bash',
    [int] $Cols = 150,
    [int] $Lines = 48,
    [int] $TimeoutSec = 900
)
$ErrorActionPreference = 'Stop'
# 명령은 -Cmd 대신 환경 변수 SHOT_CMD 로 받을 수 있다 (PowerShell 5.1 은 다른 프로세스에 인자를 넘길 때 큰따옴표를 깨뜨린다)
if (-not $Cmd) { $Cmd = $env:SHOT_CMD }
if (-not $Cmd) { throw '명령이 없다 (-Cmd 또는 SHOT_CMD)' }
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$out = Join-Path $root "v2\docs\img\shot"; New-Item -ItemType Directory -Force $out | Out-Null
$done = Join-Path $env:TEMP "vet2-shot-$Name.done"; Remove-Item $done -ErrorAction SilentlyContinue
$doneUnix = ($done -replace '\\', '/')

# 창 안에서 할 일: 크기를 정하고, 명령을 bash -v 로 실행하고(bash 가 읽은 명령 줄을 실행 전에 그대로 찍는다),
# 끝났다는 표시 파일을 만든 다음 창을 그대로 둔다. 명령 줄을 따로 꾸며 찍지 않는다.
function ToWsl([string] $p) { $p = $p -replace '\\', '/'; return '/mnt/' + $p.Substring(0, 1).ToLower() + $p.Substring(2) }
$cmdFile = Join-Path $env:TEMP "vet2-shot-$Name.sh"
$inFile = Join-Path $env:TEMP "vet2-shot-$Name.cmd.txt"
[IO.File]::WriteAllText($inFile, $Cmd + "`n", (New-Object Text.UTF8Encoding $false))
if ($Shell -eq 'wsl') {
    $body = "cd ~/vet2-lab 2>/dev/null; bash -v '$(ToWsl $inFile)'; touch '$(ToWsl $done)'; sleep 600"
} else {
    $body = "cd '$($root -replace '\\','/')'; bash -v '$($inFile -replace '\\','/')'; touch '$doneUnix'; sleep 600"
}
[IO.File]::WriteAllText($cmdFile, $body + "`n", (New-Object Text.UTF8Encoding $false))
# 창 제목을 고유하게 정해 두고 그 제목으로 창을 찾는다 (conhost 의 프로세스에서는 창 핸들을 얻지 못한다)
$title = "VET2SHOT-$Name"
if ($Shell -eq 'wsl') {
    $cmdUnix = ToWsl $cmdFile
    $inner = "title $title & mode con: cols=$Cols lines=$Lines & chcp 65001 >nul & cls & wsl.exe -d Ubuntu -u junseo -- bash $cmdUnix"
} else {
    $bash = 'C:\Program Files\Git\bin\bash.exe'
    $inner = "title $title & mode con: cols=$Cols lines=$Lines & chcp 65001 >nul & cls & `"$bash`" `"$cmdFile`""
}
$p = Start-Process -FilePath conhost.exe -ArgumentList "cmd.exe /c $inner" -PassThru
# 창을 찾아 화면 왼쪽 위에 두고 "항상 맨 위"로 고정한다. 다른 창이 겹쳐 찍히지 않게 한다
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 50 -and $h -eq [IntPtr]::Zero; $i++) {
    $wp = Get-Process | Where-Object { $_.MainWindowTitle -like "$title*" } | Select-Object -First 1
    if ($wp) { $h = $wp.MainWindowHandle } else { Start-Sleep -Milliseconds 200 }
}
if ($h -eq [IntPtr]::Zero) { throw "창을 찾지 못함: $title" }
[W]::ShowWindow($h, 9) | Out-Null
[W]::SetWindowPos($h, [IntPtr](-1), 20, 20, 0, 0, 0x0041) | Out-Null   # HWND_TOPMOST, SWP_NOSIZE|SWP_SHOWWINDOW
$t0 = Get-Date
while (-not (Test-Path $done)) {
    if (((Get-Date) - $t0).TotalSeconds -gt $TimeoutSec) { Write-Host "시간 초과: $Name"; break }
    Start-Sleep -Milliseconds 500
}
Start-Sleep -Milliseconds 800   # 마지막 출력이 화면에 그려질 시간
[W]::SetWindowPos($h, [IntPtr](-1), 20, 20, 0, 0, 0x0041) | Out-Null
[W]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 600
# 창 영역(그림자 뺀 것)을 값이 두 번 같게 나올 때까지 다시 읽는다. 창이 움직이는 중에 찍으면 다른 창이 섞인다
$r = New-Object W+RECT; $prev = ''
for ($i = 0; $i -lt 10; $i++) {
    [W]::DwmGetWindowAttribute($h, 9, [ref]$r, [Runtime.InteropServices.Marshal]::SizeOf($r)) | Out-Null
    $now = "$($r.Left),$($r.Top),$($r.Right),$($r.Bottom)"; if ($now -eq $prev) { break }; $prev = $now; Start-Sleep -Milliseconds 400
}
$w = $r.Right - $r.Left; $hgt = $r.Bottom - $r.Top
$bmp = New-Object Drawing.Bitmap $w, $hgt
$g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$file = Join-Path $out "$Name.png"; $bmp.Save($file, [Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Remove-Item $done, $cmdFile, $inFile -ErrorAction SilentlyContinue
Write-Host "캡처: $file ($w x $hgt)"
