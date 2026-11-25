# PowerPoint 로 덱을 열어 슬라이드마다 PNG 로 내보낸다 (검토용). 열다가 오류가 나면 그대로 알린다.
param([Parameter(Mandatory)][string]$Deck, [string]$OutDir = "", [int[]]$Only = @())
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot 'render' }; New-Item -ItemType Directory -Force $OutDir | Out-Null
$pp = New-Object -ComObject PowerPoint.Application
try {
    # ReadOnly, Untitled=false, WithWindow=false
    $p = $pp.Presentations.Open((Resolve-Path $Deck).Path, -1, 0, 0)
    "슬라이드 수: $($p.Slides.Count)"
    foreach ($s in $p.Slides) {
        if ($Only.Count -and -not ($Only -contains $s.SlideIndex)) { continue }
        $f = Join-Path $OutDir ("s{0:D2}.png" -f $s.SlideIndex)
        $s.Export($f, 'PNG', 1600, 900)
    }
    $p.Close()
    '내보냄'
} catch { "오류: $($_.Exception.Message)" } finally { $pp.Quit() }

