# test.ps1 - test klasöründeki ilk video + ilk fotoğrafla deneme yapar
# Kullanım: powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\test.ps1          (hızlı)
#           powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\test.ps1 ultra    (en gerçekçi)
param([string]$Preset = 'hizli')
. "$PSScriptRoot\ortam.ps1"
$dir = Join-Path $FS_ROOT 'test'
New-Item -ItemType Directory -Force $dir | Out-Null
$video = Get-ChildItem $dir -File | Where-Object { $_.Extension -match '^\.(mp4|mov|m4v|mkv|avi|webm)$' } | Select-Object -First 1
$face  = Get-ChildItem $dir -File | Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|webp)$' } | Select-Object -First 1
if (-not $video -or -not $face) {
    Write-Host ""
    Write-Host "Su klasore 1 video + 1 yuz fotografi koy, sonra bu komutu tekrar calistir:" -ForegroundColor Yellow
    Write-Host "  $dir" -ForegroundColor Cyan
    Write-Host "(video: .mp4/.mov   fotograf: .jpg/.png   -  isimleri onemli degil)"
    Start-Process explorer.exe $dir
    exit 1
}
Write-Host "Video    : $($video.Name)"
Write-Host "Yuz      : $($face.Name)"
Write-Host "On ayar  : $Preset"
& $FS_PY (Join-Path $FS_ROOT 'sunucu\cli_test.py') --video $video.FullName --face $face.FullName --preset $Preset --index 0
