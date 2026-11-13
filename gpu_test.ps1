# gpu_test.ps1 - Hızlandırıcı testi (CUDA / DirectML / CPU); sonucu data\provider.txt ve data\gpu_test.log'a yazar
. "$PSScriptRoot\ortam.ps1"
Add-FaceSwapPaths
$log = Join-Path $FS_ROOT 'data\gpu_test.log'
New-Item -ItemType Directory -Force (Join-Path $FS_ROOT 'data') | Out-Null
& $FS_PY (Join-Path $FS_ROOT 'sunucu\gpu_test.py') 2>&1 | Tee-Object -FilePath $log
$p = Get-Content (Join-Path $FS_ROOT 'data\provider.txt') -ErrorAction SilentlyContinue
if ($p -and $p -ne 'cpu') { Write-Host "`nSONUC: $p kullanilacak." -ForegroundColor Green }
else { Write-Host "`nSONUC: GPU yok, CPU kullanilacak. Log: $log" -ForegroundColor Yellow }
