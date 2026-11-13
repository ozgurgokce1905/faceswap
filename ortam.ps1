# ortam.ps1 - FaceSwap ortam değişkenleri (kur.ps1 ve calistir.ps1 tarafından dot-source edilir)
# Kullanım: . "$PSScriptRoot\ortam.ps1"

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $script:Root) { $script:Root = (Get-Location).Path }
$global:FS_ROOT   = $script:Root
$global:FS_VENV   = Join-Path $FS_ROOT 'venv'
$global:FS_PY     = Join-Path $FS_VENV 'Scripts\python.exe'
$global:FS_FF     = Join-Path $FS_ROOT 'facefusion'
$global:FS_SITE   = Join-Path $FS_VENV 'Lib\site-packages'

$env:FACESWAP_HOME   = $FS_ROOT
$env:FACESWAP_FF_DIR = $FS_FF
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'
# Python UTF-8 yazar; PowerShell de UTF-8 okusun (Türkçe karakterli yollar/yazılar bozulmasın)
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    $global:OutputEncoding    = [System.Text.Encoding]::UTF8
} catch {}

function Refresh-Path {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$m;$u"
}

function Add-FaceSwapPaths {
    # venv + pip nvidia DLL klasörleri + ffmpeg
    $paths = @("$FS_VENV\Scripts")
    foreach ($p in @('cuda_runtime', 'cudnn', 'cublas', 'cufft', 'curand', 'cuda_nvrtc', 'nvjitlink')) {
        $d = Join-Path $FS_SITE "nvidia\$p\bin"
        if (Test-Path $d) { $paths += $d }
    }
    $ov = Join-Path $FS_SITE 'openvino\libs'
    if (Test-Path $ov) { $paths += $ov }
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        $wg = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        if (Test-Path $wg) {
            $ff = Get-ChildItem $wg -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ff) { $paths += $ff.DirectoryName }
        }
    }
    $env:Path = ($paths -join ';') + ';' + $env:Path
}

function Get-LanIps {
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Select-Object -ExpandProperty IPAddress
}
