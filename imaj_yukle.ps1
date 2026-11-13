# imaj_yukle.ps1 - Sunucu kodunu GitHub'a gönderir; GitHub hazır imajı kendisi derler (~15-20 dk, ilk sefer).
# Sonraki her kod değişikliğinde tekrar çalıştır: imaj otomatik yenilenir.
#   powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\imaj_yukle.ps1
$ErrorActionPreference = 'Continue'   # git uyarıları (LF/CRLF) hata sayılmasın
Set-Location $PSScriptRoot
$Repo = 'https://github.com/ozgurgokce1905/faceswap.git'
if (-not (Test-Path .git)) {
    git init -b main | Out-Null
    git remote add origin $Repo
}
git config core.autocrlf false
git config core.safecrlf false
git add .gitattributes .gitignore .dockerignore docker .github sunucu runpod *.ps1 BENIOKU.md app/lib app/pubspec.yaml app/android 2>&1 | Out-Null
git -c user.name='Ozgur Gokce' -c user.email='ozgurgokce15@gmail.com' commit -m "FaceSwap sunucu + hazır imaj $(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Out-Null
git push -u origin main
if ($LASTEXITCODE -ne 0) { Write-Host "Gönderilemedi. GitHub'da 'faceswap' adlı boş private repo var mı?" -ForegroundColor Red; exit 1 }
Write-Host "`nGönderildi. İmaj derleniyor: https://github.com/ozgurgokce1905/faceswap/actions" -ForegroundColor Green
Write-Host "Yeşil tik çıkınca pod açmak için: powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\runpod.ps1 ac"
