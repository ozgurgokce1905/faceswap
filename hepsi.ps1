# hepsi.ps1 - Tek komut: motoru kur -> sunucuyu ayrı pencerede başlat -> testi çalıştır
# Kullanım: powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\hepsi.ps1 openvino
#           powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\hepsi.ps1 cpu
#           powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\hepsi.ps1            (motor değiştirmeden sadece sunucu + test)
param([string]$Sec = '', [string]$Preset = 'hizli')
. "$PSScriptRoot\ortam.ps1"
$ErrorActionPreference = 'Continue'

if ($Sec) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $FS_ROOT 'hizlandirici.ps1') $Sec
    $p = Get-Content (Join-Path $FS_ROOT 'data\provider.txt') -ErrorAction SilentlyContinue
    if ("$p".Trim() -ne $Sec) { Write-Host "`n'$Sec' çalışmadı. Yukarıdaki çıktıyı Claude'a gönder." -ForegroundColor Red; exit 1 }
}

# Sunucu zaten açık mı?
$acik = $false
try { $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 'http://127.0.0.1:8765/health'; $acik = ($r.StatusCode -eq 200) } catch {}
if (-not $acik) {
    Write-Host "`nSunucu ayrı pencerede başlatılıyor..." -ForegroundColor Cyan
    Start-Process powershell -ArgumentList '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $FS_ROOT 'calistir.ps1')
    $t0 = Get-Date
    while (-not $acik -and ((Get-Date) - $t0).TotalSeconds -lt 180) {
        Start-Sleep -Seconds 3
        try { $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 'http://127.0.0.1:8765/health'; $acik = ($r.StatusCode -eq 200) } catch {}
        Write-Host "." -NoNewline
    }
    Write-Host ""
    if (-not $acik) { Write-Host "Sunucu 3 dakikada açılmadı. Sunucu penceresindeki yazıyı Claude'a gönder." -ForegroundColor Red; exit 1 }
    Write-Host "Sunucu hazır." -ForegroundColor Green
}

Write-Host "`nTest başlıyor ($Preset)..." -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File (Join-Path $FS_ROOT 'test.ps1') $Preset
