# hizlandirici.ps1 - Hangi motorla çalışılacağını seçer ve gerekli onnxruntime paketini kurar
# Kullanım:
#   powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\hizlandirici.ps1 openvino   (Intel ekran kartı, Intel'in motoru)
#   powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\hizlandirici.ps1 directml   (Intel/AMD ekran kartı, Microsoft motoru)
#   powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\hizlandirici.ps1 cpu        (sadece işlemci)
param([Parameter(Mandatory=$true)][ValidateSet('cpu','directml','openvino','cuda')][string]$Sec)
. "$PSScriptRoot\ortam.ps1"
$ErrorActionPreference = 'Continue'
function Fail($msg) { Write-Host "`n  HATA: $msg" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $FS_PY)) { Fail "Önce kur.ps1 çalıştır (venv yok)." }
$env:Path = "$FS_VENV\Scripts;" + $env:Path
Add-FaceSwapPaths

$paket = @{ cpu = 'default'; directml = 'directml'; openvino = 'openvino'; cuda = 'cuda@12' }[$Sec]
Write-Host "`n==== [1/2] onnxruntime ($paket) kuruluyor" -ForegroundColor Cyan
Push-Location $FS_FF
& $FS_PY install.py $paket --skip-conda
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "install.py $paket başarısız" }
if ($Sec -eq 'openvino') {
    # Windows'ta OpenVINO çalışma zamanı ayrı pip paketi (onnxruntime-openvino 1.24.1 -> OpenVINO 2025.4)
    & $FS_PY -m pip install --upgrade "openvino==2025.4.*"
    if ($LASTEXITCODE -ne 0) { Fail "pip openvino kurulumu başarısız" }
}
Copy-Item (Join-Path $FS_ROOT 'sunucu\sitecustomize.py') (Join-Path $FS_SITE 'sitecustomize.py') -Force
Add-FaceSwapPaths
& $FS_PY -c "import onnxruntime as o; print('onnxruntime', o.__version__, o.get_available_providers())"

Write-Host "`n==== [2/2] Test" -ForegroundColor Cyan
& $FS_PY (Join-Path $FS_ROOT 'sunucu\gpu_test.py') $Sec
$p = Get-Content (Join-Path $FS_ROOT 'data\provider.txt') -ErrorAction SilentlyContinue
if ($p -eq $Sec) { Write-Host "`nTAMAM: '$Sec' kullanılacak. Sunucuyu yeniden başlat: calistir.ps1" -ForegroundColor Green }
else { Write-Host "`nUYARI: '$Sec' çalışmadı, '$p' seçildi. Yukarıdaki çıktıyı Claude'a gönder." -ForegroundColor Yellow }
