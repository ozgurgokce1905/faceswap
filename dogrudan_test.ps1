# dogrudan_test.ps1 - FaceFusion'ı sunucusuz, doğrudan bu pencerede çalıştırır (ne yaptığı canlı görünür)
# Kullanım: powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\dogrudan_test.ps1
param([string]$Preset = 'hizli')
. "$PSScriptRoot\ortam.ps1"
Add-FaceSwapPaths
$dir = Join-Path $FS_ROOT 'test'
$video = Get-ChildItem $dir -File | Where-Object { $_.Extension -match '^\.(mp4|mov|m4v|mkv|avi|webm)$' } | Select-Object -First 1
$face  = Get-ChildItem $dir -File | Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|webp)$' } | Select-Object -First 1
if (-not $video -or -not $face) { Write-Host "test klasöründe video/fotoğraf yok" -ForegroundColor Red; exit 1 }
$provider = (Get-Content (Join-Path $FS_ROOT 'data\provider.txt') -ErrorAction SilentlyContinue)
if (-not $provider) { $provider = 'cpu' }
$provider = "$provider".Trim()
$out = Join-Path $dir ($video.BaseName + '_dogrudan.mp4')
$tmp = Join-Path $FS_ROOT 'data\temp\dogrudan'
Write-Host "Video: $($video.Name)  Yüz: $($face.Name)  Hızlandırıcı: $provider  Ön ayar: $Preset" -ForegroundColor Cyan
$t0 = Get-Date
Push-Location $FS_FF
& $FS_PY facefusion.py headless-run -s $face.FullName -t $video.FullName -o $out --temp-path $tmp `
    --face-detector-model yolo_face --face-detector-size 640x640 --face-selector-mode reference --reference-frame-number 0 --reference-face-position 0 --reference-face-distance 0.6 `
    --processors face_swapper --face-swapper-model hyperswap_1a_256 --face-swapper-pixel-boost 512x512 --face-mask-types box occlusion `
    --output-video-quality 85 --output-video-preset veryfast `
    --execution-providers $provider --execution-thread-count 1 --video-memory-strategy moderate --log-level debug
Pop-Location
Write-Host ("Süre: {0:N0} sn  Çıkış kodu: {1}" -f ((Get-Date) - $t0).TotalSeconds, $LASTEXITCODE) -ForegroundColor Yellow
if (Test-Path $out) { Write-Host "Sonuç: $out" -ForegroundColor Green }
