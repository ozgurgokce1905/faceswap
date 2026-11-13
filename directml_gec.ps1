# directml_gec.ps1 - NVIDIA kartı olmayan bilgisayarda Intel/AMD ekran kartını DirectML ile kullanmaya geçirir
# Çalıştırma: powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\directml_gec.ps1
. "$PSScriptRoot\ortam.ps1"
$ErrorActionPreference = 'Continue'
function Fail($msg) { Write-Host "`n  HATA: $msg" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $FS_PY)) { Fail "Önce kur.ps1 çalıştır (venv yok)." }
$env:Path = "$FS_VENV\Scripts;" + $env:Path

Write-Host "`n==== [1/3] onnxruntime-directml kuruluyor (onnxruntime-gpu kaldırılıyor)" -ForegroundColor Cyan
Push-Location $FS_FF
& $FS_PY install.py directml --skip-conda
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Fail "install.py directml başarısız" }

Write-Host "`n==== [2/3] Gereksiz NVIDIA paketleri temizleniyor" -ForegroundColor Cyan
& $FS_PY -m pip uninstall -y -q nvidia-cuda-runtime-cu12 nvidia-cudnn-cu12 nvidia-cublas-cu12 nvidia-cufft-cu12 nvidia-curand-cu12 nvidia-cuda-nvrtc-cu12 nvidia-nvjitlink-cu12 2>$null
Remove-Item (Join-Path $FS_SITE 'sitecustomize.py') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $FS_ROOT 'data\cpu_only.txt') -Force -ErrorAction SilentlyContinue
& $FS_PY -c "import onnxruntime as o; print('onnxruntime', o.__version__, o.get_available_providers())"

Write-Host "`n==== [3/3] Hızlandırıcı testi" -ForegroundColor Cyan
& $FS_PY (Join-Path $FS_ROOT 'sunucu\gpu_test.py')
$p = Get-Content (Join-Path $FS_ROOT 'data\provider.txt') -ErrorAction SilentlyContinue
if ($p -eq 'directml') { Write-Host "`nTAMAM: DirectML (Intel Iris Xe) kullanılacak. Sunucu: calistir.ps1" -ForegroundColor Green }
else { Write-Host "`nUYARI: DirectML çalışmadı, CPU kullanılacak ($p). Yukarıdaki çıktıyı Claude'a gönder." -ForegroundColor Yellow }
