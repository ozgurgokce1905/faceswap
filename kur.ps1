# kur.ps1 - FaceSwap sunucusu kurulumu (tek sefer çalıştırılır)
# Çalıştırma: powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\kur.ps1
#
# Yaptıkları:
#   1. Git, Python 3.12, FFmpeg (winget ile; varsa atlar)
#   2. FaceFusion'ı indirir (github)
#   3. venv kurar, FaceFusion bağımlılıkları + onnxruntime-gpu (CUDA 12)
#   4. NVIDIA varsa CUDA/cuDNN'i pip'ten kurar (CUDA Toolkit gerekmez); yoksa DirectML (Intel/AMD)
#   5. Hızlandırıcı testi
#   6. Modelleri indirir (yaklaşık 2-3 GB)

$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\ortam.ps1"

function Step($n, $msg) { Write-Host "`n==== [$n/8] $msg" -ForegroundColor Cyan }
function Ok($msg) { Write-Host "  OK  $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  !!  $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "`n  HATA: $msg" -ForegroundColor Red; Write-Host "  Kurulum durdu. Bu ekranı Claude'a yapıştır." -ForegroundColor Red; exit 1 }
# venv python'u çalıştırır, hata kodunda kurulumu durdurur
function Run-Py {
    param([string[]]$ArgList, [string]$What)
    if (-not (Test-Path $FS_PY)) { Fail "venv python yok: $FS_PY" }
    $global:LASTEXITCODE = 0
    & $FS_PY @ArgList
    if ($LASTEXITCODE -ne 0) { Fail "$What başarısız (çıkış kodu $LASTEXITCODE)" }
}

$FF_COMMIT = 'decc6c9'   # FaceFusion 3.9.2 (26 Ekim 2026) - sunucu kodu bu sürüme göre yazıldı

Write-Host "FaceSwap kurulumu başlıyor. Klasör: $FS_ROOT" -ForegroundColor White

# ------------------------------------------------------------------ 0. winget
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Fail "winget bulunamadı. Microsoft Store'dan 'App Installer' kurup tekrar çalıştır."
}
$wgArgs = @('-e', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')

# ------------------------------------------------------------------ 1. Git
Step 1 'Git'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    winget install --id Git.Git @wgArgs
    Refresh-Path
}
git --version | Out-Host

# ------------------------------------------------------------------ 2. Python 3.12
Step 2 'Python 3.12'
function Find-Py312 {
    # Önce dosya sisteminden bak (Python'un yazdığı yolu okumak Türkçe karakterli kullanıcı adında bozuluyordu)
    foreach ($c in @("$env:LOCALAPPDATA\Programs\Python\Python312\python.exe", "C:\Program Files\Python312\python.exe", "C:\Python312\python.exe", "$env:ProgramFiles\Python312\python.exe")) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    # py launcher ile sor (UTF-8 konsol ayarı ortam.ps1'de yapıldı)
    try {
        $v = & py -3.12 -c "import sys;print(sys.executable)" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { $v = "$v".Trim(); if (Test-Path -LiteralPath $v) { return $v } }
    } catch {}
    return $null
}
$py = Find-Py312
if (-not $py) {
    winget install --id Python.Python.3.12 @wgArgs
    Refresh-Path
    $py = Find-Py312
}
if (-not $py) { Fail "Python 3.12 bulunamadı. https://www.python.org/downloads/ adresinden 3.12 kur (Add to PATH işaretle) ve tekrar çalıştır." }
Ok "Python: $py"

# ------------------------------------------------------------------ 3. FFmpeg
Step 3 'FFmpeg'
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    winget install --id Gyan.FFmpeg @wgArgs
    Refresh-Path
}
Add-FaceSwapPaths
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { Fail "ffmpeg bulunamadı. Yeni bir PowerShell açıp tekrar dene." }
if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) { Fail "ffprobe bulunamadı." }
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { Fail "curl.exe bulunamadı (Windows 10 1803+ ile gelir)." }
Ok ((ffmpeg -version 2>&1 | Select-Object -First 1))

# ------------------------------------------------------------------ 4. FaceFusion kaynak kodu
Step 4 'FaceFusion indiriliyor'
if (-not (Test-Path (Join-Path $FS_FF 'facefusion.py'))) {
    if (Test-Path $FS_FF) { Remove-Item $FS_FF -Recurse -Force }
    git clone https://github.com/facefusion/facefusion.git $FS_FF
    if ($LASTEXITCODE -ne 0) { Fail "git clone başarısız (internet / github erişimi?)" }
}
git -C $FS_FF fetch --quiet origin
git -C $FS_FF checkout --quiet $FF_COMMIT
if ($LASTEXITCODE -eq 0) { Ok "FaceFusion sürümü sabitlendi: $FF_COMMIT" } else { Warn "Sürüm sabitlenemedi, master kullanılıyor." }
& git -C $FS_FF log -1 --format='  %h %ad %s' --date=short | Out-Host

# ------------------------------------------------------------------ 5. venv + bağımlılıklar
Step 5 'Python ortamı (venv) ve FaceFusion bağımlılıkları'
# NVIDIA kartı var mı? (PCI üretici kodu 10DE) -> CUDA; yoksa Intel/AMD için DirectML
$hasNvidia = [bool](Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\VEN_10DE*' })
$ortKind = if ($hasNvidia) { 'cuda@12' } else { 'directml' }
Write-Host "  Ekran kartı: $(if ($hasNvidia) { 'NVIDIA -> CUDA 12' } else { 'NVIDIA yok -> DirectML (Intel/AMD)' })"
if (-not (Test-Path $FS_PY)) {
    & $py -m venv $FS_VENV
    if (-not (Test-Path $FS_PY)) { Fail "venv oluşturulamadı ($FS_VENV). Python yolu: $py" }
}
$env:Path = "$FS_VENV\Scripts;" + $env:Path
Run-Py @('-m', 'pip', 'install', '--upgrade', 'pip', '--quiet') 'pip güncelleme'
Push-Location $FS_FF
try {
    Run-Py @('install.py', $ortKind, '--skip-conda') 'FaceFusion install.py'
} finally { Pop-Location }
Run-Py @('-c', 'import onnxruntime, cv2, numpy, gradio; print(onnxruntime.__version__)') 'FaceFusion bağımlılık kontrolü'
Ok "FaceFusion bağımlılıkları kuruldu ($ortKind)"

# ------------------------------------------------------------------ 6. sunucu paketleri (+ NVIDIA ise CUDA/cuDNN pip)
Step 6 'Sunucu paketleri'
$pkgs = @('fastapi', 'uvicorn', 'python-multipart', 'requests')
if ($hasNvidia) {
    $pkgs += @('nvidia-cuda-runtime-cu12', 'nvidia-cudnn-cu12', 'nvidia-cublas-cu12', 'nvidia-cufft-cu12',
               'nvidia-curand-cu12', 'nvidia-cuda-nvrtc-cu12', 'nvidia-nvjitlink-cu12')
}
Run-Py (@('-m', 'pip', 'install', '--upgrade') + $pkgs) 'pip (sunucu paketleri)'
if (-not (Test-Path $FS_SITE)) { Fail "site-packages bulunamadı: $FS_SITE" }
if ($hasNvidia) {
    Copy-Item (Join-Path $FS_ROOT 'sunucu\sitecustomize.py') (Join-Path $FS_SITE 'sitecustomize.py') -Force
} else {
    Remove-Item (Join-Path $FS_SITE 'sitecustomize.py') -Force -ErrorAction SilentlyContinue
}
Add-FaceSwapPaths
Ok 'Kuruldu'

# ------------------------------------------------------------------ 7. Hızlandırıcı testi
Step 7 'Hızlandırıcı testi (CUDA / DirectML / CPU)'
New-Item -ItemType Directory -Force (Join-Path $FS_ROOT 'data') | Out-Null
$global:LASTEXITCODE = 1
& $FS_PY (Join-Path $FS_ROOT 'sunucu\gpu_test.py')
$provider = Get-Content (Join-Path $FS_ROOT 'data\provider.txt') -ErrorAction SilentlyContinue
if (-not $provider) { $provider = 'cpu'; 'cpu' | Set-Content (Join-Path $FS_ROOT 'data\provider.txt') }
if ($provider -ne 'cpu') { Ok "Hızlandırıcı: $provider" } else { Warn 'GPU bulunamadı, CPU modunda devam (yavaş).' }

# Güvenlik duvarı (yönetici gerekir; değilse Windows ilk çalıştırmada kendisi soracak)
try {
    if (-not (Get-NetFirewallRule -DisplayName 'FaceSwap 8765' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'FaceSwap 8765' -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow -Profile Private,Domain | Out-Null
        Ok 'Güvenlik duvarı kuralı eklendi (8765)'
    }
} catch { Warn 'Güvenlik duvarı kuralı eklenemedi (yönetici değil). Sunucu ilk açılışta Windows sorarsa "İzin ver" de.' }

# ------------------------------------------------------------------ 8. Modeller
Step 8 'Modeller indiriliyor (2-3 GB, tek sefer)'
$env:FACESWAP_PROVIDER = "$provider".Trim()
$global:LASTEXITCODE = 1
& $FS_PY (Join-Path $FS_ROOT 'sunucu\warmup.py')
if ($LASTEXITCODE -ne 0) { Warn 'Bazı modeller indirilemedi; sunucu ilk kullanımda tekrar dener.' } else { Ok 'Modeller hazır' }

$ips = (Get-LanIps) -join ', '
Write-Host ''
Write-Host '==================== KURULUM TAMAM ====================' -ForegroundColor Green
Write-Host "Sunucuyu başlatmak için:" -ForegroundColor White
Write-Host "  powershell -ExecutionPolicy Bypass -File $FS_ROOT\calistir.ps1" -ForegroundColor Yellow
Write-Host "Telefondan bağlanacağın adres: http://$ips`:8765" -ForegroundColor White
Write-Host '=======================================================' -ForegroundColor Green
