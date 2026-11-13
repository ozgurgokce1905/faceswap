# app_derle.ps1 - APK derler, D:\Dev\faceswap\FaceSwap.apk olarak kopyalar, telefon bağlıysa yükler
# Çalıştırma: powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\app_derle.ps1
$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$App  = Join-Path $Root 'app'
$flutter = 'D:\Dev\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# Uygulamanın içine gömülen RunPod dosyaları (pod'u telefondan açmak için): bootstrap + sunucu kodu
$assets = Join-Path $App 'assets\runpod'
New-Item -ItemType Directory -Force $assets | Out-Null
Copy-Item (Join-Path $Root 'runpod\bootstrap.sh') (Join-Path $assets 'bootstrap.sh') -Force
$codeTar = Join-Path $assets 'code.tar.gz'
if (Test-Path $codeTar) { Remove-Item $codeTar -Force }
& tar -czf $codeTar --exclude=__pycache__ -C $Root sunucu runpod
Write-Host "Sunucu kodu uygulamaya gömüldü: $([math]::Round((Get-Item $codeTar).Length/1KB)) KB"

Push-Location $App
Write-Host "APK derleniyor (release)..." -ForegroundColor Cyan
& $flutter build apk --release
if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Host "`n  HATA: derleme başarısız. Çıktıyı Claude'a gönder." -ForegroundColor Red; exit 1 }
$apk = 'build\app\outputs\flutter-apk\app-release.apk'
Copy-Item $apk (Join-Path $Root 'FaceSwap.apk') -Force
Pop-Location
Write-Host "APK hazır: $Root\FaceSwap.apk" -ForegroundColor Green

$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$adbCmd = Get-Command adb -ErrorAction SilentlyContinue
if ($adbCmd) { $adb = $adbCmd.Source }
if (Test-Path $adb) {
    $devs = & $adb devices | Select-String -Pattern "`tdevice$"
    if ($devs) {
        Write-Host "Telefona yükleniyor..." -ForegroundColor Cyan
        & $adb install -r (Join-Path $Root 'FaceSwap.apk')
    } else {
        Write-Host "USB'de telefon görünmüyor. FaceSwap.apk dosyasını telefona gönderip kurabilirsin (WhatsApp/kablo)." -ForegroundColor Yellow
    }
} else {
    Write-Host "adb bulunamadı. FaceSwap.apk dosyasını telefona gönderip kurabilirsin." -ForegroundColor Yellow
}
