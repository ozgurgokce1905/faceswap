# app_kur.ps1 - Flutter uygulamasını ilk kez kurar (android klasörünü oluşturur, izinleri ekler)
# Çalıştırma: powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\app_kur.ps1
$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
$App  = Join-Path $Root 'app'
$flutter = 'D:\Dev\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Fail($m) { Write-Host "`n  HATA: $m" -ForegroundColor Red; exit 1 }

Push-Location $App
Write-Host "==== [1/4] flutter create (mevcut lib/ ve pubspec.yaml korunur)" -ForegroundColor Cyan
& $flutter create --org com.ozgurgokce --project-name faceswap --platforms android .
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "flutter create başarısız" }
if (Test-Path 'test\widget_test.dart') { Remove-Item 'test\widget_test.dart' -Force }

Write-Host "==== [2/4] Android ayarları (izinler, HTTP, uygulama adı, kotlin.incremental)" -ForegroundColor Cyan
$mf = 'android\app\src\main\AndroidManifest.xml'
$t = [IO.File]::ReadAllText($mf)
if ($t -notmatch 'android.permission.INTERNET') {
    $perm = @"
    <!-- Bilgisayardaki FaceSwap sunucusuna bağlanmak için -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <!-- Galeriye kaydetme (Android 9 ve altı) -->
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>
"@
    $t = $t -replace '(<manifest[^>]*>)', ('$1' + "`r`n" + $perm)
}
$t = $t -replace 'android:label="faceswap"', 'android:label="FaceSwap"'
if ($t -notmatch 'usesCleartextTraffic') {
    # Sunucu yerel ağda http ile çalışıyor; Android 9+ bunu varsayılan engeller
    $t = $t -replace '<application', '<application android:usesCleartextTraffic="true"'
}
[IO.File]::WriteAllText($mf, $t, (New-Object System.Text.UTF8Encoding $false))

$gp = 'android\gradle.properties'
if ((Get-Content $gp -Raw) -notmatch 'kotlin.incremental') { Add-Content $gp "`nkotlin.incremental=false" }

Write-Host "==== [3/4] Paketler" -ForegroundColor Cyan
& $flutter pub get
if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "flutter pub get başarısız" }

Write-Host "==== [4/4] Kod kontrolü" -ForegroundColor Cyan
& $flutter analyze
Pop-Location
Write-Host "`nTAMAM. Derlemek için: powershell -ExecutionPolicy Bypass -File $Root\app_derle.ps1" -ForegroundColor Green
