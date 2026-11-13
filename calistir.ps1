# calistir.ps1 - FaceSwap sunucusunu başlatır
# Çalıştırma: powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\calistir.ps1
# Durdurma:   bu pencerede Ctrl+C
param(
    [int]$Port = 8765,
    [string]$Provider = '',   # boş = data\provider.txt (cuda / directml / cpu)
    [int]$Threads = 0         # 0 = otomatik
)
. "$PSScriptRoot\ortam.ps1"

if (-not (Test-Path $FS_PY)) { Write-Host "Önce kur.ps1 çalıştır." -ForegroundColor Red; exit 1 }
Add-FaceSwapPaths

if (-not $Provider) {
    $Provider = Get-Content (Join-Path $FS_ROOT 'data\provider.txt') -ErrorAction SilentlyContinue
    if (-not $Provider) { $Provider = 'cpu' }
}
$Provider = "$Provider".Trim()
if ($Threads -le 0) { $Threads = @{ cuda = 4; directml = 1; openvino = 2; cpu = 2 }[$Provider]; if (-not $Threads) { $Threads = 2 } }

$env:FACESWAP_PORT = "$Port"
$env:FACESWAP_PROVIDER = $Provider
$env:FACESWAP_THREADS = "$Threads"

Write-Host ''
Write-Host '  FaceSwap sunucusu' -ForegroundColor Cyan
Write-Host "  Hızlandırıcı : $Provider  (iş parçacığı: $Threads)"
foreach ($ip in (Get-LanIps)) { Write-Host "  Adres        : http://$ip`:$Port" -ForegroundColor Yellow }
Write-Host '  Durdurmak için Ctrl+C' -ForegroundColor DarkGray
Write-Host ''

& $FS_PY (Join-Path $FS_ROOT 'sunucu\server.py')
