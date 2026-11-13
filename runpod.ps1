# runpod.ps1 - RunPod üzerinde FaceSwap sunucusunu yönetir (bilgisayardan)
# Kullanım:
#   powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\runpod.ps1 kur      (bir kez: kalıcı disk oluşturur)
#   powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\runpod.ps1 ac       (HAZIR İMAJLA pod açar: en iyi boş kart, kurulum yok, 1-2 dk)
#   powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\runpod.ps1 ac -Gpu 5090   (sadece belirli kart)
#   (eski yöntem) runpod.ps1 ac -Cloud secure   (pod açar, kodu yükler, hazır olunca adresi yazar)
#   powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\runpod.ps1 ac -Cloud community   (kalıcı disksiz, ucuz, her açılışta kurulum)
#   powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\runpod.ps1 kapat    (pod'u kapatır; sayaç durur, disk kalır)
#   powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\runpod.ps1 durum    (bakiye, açık pod, adres)
#   powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\runpod.ps1 kod      (açık pod'a yeni kodu yükler, 10 sn; kurulum tekrarlanmaz)
param(
    [Parameter(Position=0)][ValidateSet('kur','ac','kapat','durum','stok','disksil','kod')][string]$Komut = 'durum',
    [string]$Dc = '',               # veri merkezi (boş = en son kullanılan; ilk kurulumda EU-RO-1)
    [int]$DiskGb = 40,
    [int]$BostaDk = 15,             # bu kadar dakika iş gelmezse pod kendini kapatır
    [ValidateSet('imaj','secure','community','disksiz')][string]$Cloud = 'imaj',  # imaj: hazır imaj, kurulum yok, her veri merkezi (önerilen)  # community: ucuz; disksiz: Secure Cloud ama kalıcı disk yok (her merkez olur)
    [string]$Gpu = '',             # belirli kart iste, ör: -Gpu H100  (H100 / 4090 / A5000 / L40S / A6000 ...)
    [int]$BekleDk = 60             # boş kart yoksa bu kadar dakika boyunca dakikada bir tekrar dener
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$Root = $PSScriptRoot
$Data = Join-Path $Root 'data'
New-Item -ItemType Directory -Force $Data | Out-Null
$KeyFile = Join-Path $Data 'runpod_key.txt'
$DcFile = Join-Path $Data 'runpod_dc.txt'
if (-not $Dc) { if (Test-Path $DcFile) { $Dc = (Get-Content $DcFile -Raw).Trim() } else { $Dc = 'EU-RO-1' } }
$VolFile = Join-Path $Data ('runpod_volume_' + $Dc + '.txt')
if (-not (Test-Path $VolFile) -and $Dc -eq 'EU-RO-1' -and (Test-Path (Join-Path $Data 'runpod_volume.txt'))) { Move-Item (Join-Path $Data 'runpod_volume.txt') $VolFile }
$TokFile = Join-Path $Data 'runpod_token.txt'
$AdrFile = Join-Path $Data 'runpod_adres.txt'
if (-not (Test-Path $KeyFile)) { Write-Host "API anahtarı yok: $KeyFile" -ForegroundColor Red; exit 1 }
$Key = (Get-Content $KeyFile -Raw).Trim()
$H = @{ 'Authorization' = "Bearer $Key"; 'Content-Type' = 'application/json' }
$Api = 'https://rest.runpod.io/v1'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Tercih sırası: önce 4090, bulunamazsa diğerleri (hepsi 16-24 GB)
$Gpus = @('NVIDIA GeForce RTX 4090', 'NVIDIA RTX A5000', 'NVIDIA GeForce RTX 3090', 'NVIDIA GeForce RTX 3090 Ti', 'NVIDIA RTX 4000 Ada Generation', 'NVIDIA RTX A6000', 'NVIDIA L40', 'NVIDIA L4', 'NVIDIA RTX A4500', 'NVIDIA RTX A4000')
$Image = 'runpod/pytorch:1.5.0-cu1281-torch280-ubuntu2404'
$HazirImaj = 'ghcr.io/ozgurgokce1905/faceswap-hazir:latest'   # GitHub Actions derler (docker/Dockerfile)
if ($Cloud -eq 'imaj') {
    $Image = $HazirImaj
    # En iyi kart önce: 5090 > 4090 > L40S > H100 > diğerleri (FaceFusion için 5090 en hızlı/ucuz)
    $Gpus = @('NVIDIA GeForce RTX 5090', 'NVIDIA GeForce RTX 4090', 'NVIDIA L40S', 'NVIDIA H100 PCIe', 'NVIDIA H100 80GB HBM3', 'NVIDIA RTX 6000 Ada Generation', 'NVIDIA L40', 'NVIDIA RTX A6000', 'NVIDIA GeForce RTX 3090', 'NVIDIA RTX A5000')
}   # Ubuntu 24.04 -> Python 3.12 (FaceFusion numpy 2.5 için şart)
$GpuAdlari = @{ 'h100' = @('NVIDIA H100 80GB HBM3', 'NVIDIA H100 PCIe', 'NVIDIA H100 NVL'); 'h100nvl' = 'NVIDIA H100 NVL'; 'h200' = 'NVIDIA H200'; 'a100' = 'NVIDIA A100 80GB PCIe'; 'l40s' = 'NVIDIA L40S'; 'l40' = 'NVIDIA L40'; 'a6000' = 'NVIDIA RTX A6000'; '5090' = 'NVIDIA GeForce RTX 5090'; '4090' = 'NVIDIA GeForce RTX 4090'; '3090' = 'NVIDIA GeForce RTX 3090'; 'a5000' = 'NVIDIA RTX A5000'; 'l4' = 'NVIDIA L4'; '4000ada' = 'NVIDIA RTX 4000 Ada Generation'; 'a40' = 'NVIDIA A40' }
if ($Gpu) {
    $k = $Gpu.ToLower() -replace '[^a-z0-9]', ''
    if ($GpuAdlari.ContainsKey($k)) { $Gpus = @($GpuAdlari[$k]) ; $Gpus = @($Gpus | ForEach-Object { $_ }) } elseif ($Gpu -like 'NVIDIA*') { $Gpus = @($Gpu) } else { Write-Host "Bilinmeyen kart: $Gpu  (seçenekler: $($GpuAdlari.Keys -join ', '))" -ForegroundColor Red; exit 1 }
}

# PowerShell 5.1'in ConvertTo-Json'u uzun metinlerde çökebiliyor; JSON'u elle kuruyoruz
function J($v) {
    if ($v -eq $null) { return 'null' }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [int] -or $v -is [long] -or $v -is [double]) { return "$v" }
    if ($v -is [string]) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        foreach ($ch in $v.ToCharArray()) {
            $c = [int]$ch
            if ($ch -eq '"') { [void]$sb.Append('\"') }
            elseif ($ch -eq '\') { [void]$sb.Append('\\') }
            elseif ($c -eq 10) { [void]$sb.Append('\n') }
            elseif ($c -eq 13) { [void]$sb.Append('\r') }
            elseif ($c -eq 9) { [void]$sb.Append('\t') }
            elseif ($c -lt 32) { [void]$sb.Append('\u' + $c.ToString('x4')) }
            else { [void]$sb.Append($ch) }
        }
        [void]$sb.Append('"')
        return $sb.ToString()
    }
    if ($v -is [System.Collections.IDictionary]) {
        $parts = @(); foreach ($k in $v.Keys) { $parts += ((J ([string]$k)) + ':' + (J $v[$k])) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($v -is [System.Collections.IEnumerable]) {
        $parts = @(); foreach ($e in $v) { $parts += (J $e) }
        return '[' + ($parts -join ',') + ']'
    }
    return (J ([string]$v))
}
function Api($Method, $Path, $Body = $null) {
    $p = @{ Method = $Method; Uri = "$Api$Path"; Headers = $H; TimeoutSec = 60 }
    if ($Body -ne $null) {
        $json = J $Body
        Set-Content (Join-Path $Data 'son_istek.json') -Value $json -Encoding UTF8
        $p.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
    }
    try { return Invoke-RestMethod @p }
    catch {
        $msg = ''
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
        if (-not $msg) { try { $st = $_.Exception.Response.GetResponseStream(); $st.Position = 0; $r = New-Object IO.StreamReader($st); $msg = $r.ReadToEnd() } catch {} }
        if (-not $msg) { $msg = $_.Exception.Message }
        $code = ''
        try { $code = [int]$_.Exception.Response.StatusCode } catch {}
        Set-Content (Join-Path $Data 'son_hata.txt') -Value "$Method $Path`nHTTP $code`n$msg" -Encoding UTF8
        throw "RunPod API hatası ($Method $Path) HTTP $code : $msg"
    }
}
function Gql($Query) {
    $r = Invoke-RestMethod -Method Post -Uri 'https://api.runpod.io/graphql' -Headers $H -Body ([System.Text.Encoding]::UTF8.GetBytes((J @{ query = $Query }))) -TimeoutSec 60
    return $r.data
}
function Bakiye {
    try { $m = (Gql 'query { myself { clientBalance currentSpendPerHr } }').myself; return "Bakiye: $([math]::Round($m.clientBalance,2)) $ | Şu anki harcama: $($m.currentSpendPerHr) $/saat" } catch { return "Bakiye okunamadı" }
}
function Token {
    if (-not (Test-Path $TokFile)) { Set-Content $TokFile -Value ([guid]::NewGuid().ToString('N')) -NoNewline }
    return (Get-Content $TokFile -Raw).Trim()
}
function AcikPodlar {
    $pods = Api GET '/pods'
    if ($pods -eq $null) { return @() }
    return @($pods | Where-Object { $_.name -eq 'faceswap' })
}
function ProxyUrl($id) { return "https://$id-8765.proxy.runpod.net" }
function GpuAdi($p) { if ($p.gpu -and $p.gpu.displayName) { return $p.gpu.displayName }; if ($p.machine -and $p.machine.gpuDisplayName) { return $p.machine.gpuDisplayName }; return '?' }

switch ($Komut) {
# ------------------------------------------------------------------------------------------------
'kur' {
    if (Test-Path $VolFile) { Write-Host "Kalıcı disk zaten var ($Dc): $(Get-Content $VolFile)"; Set-Content $DcFile -Value $Dc -NoNewline; break }
    Write-Host "Kalıcı disk oluşturuluyor ($DiskGb GB, $Dc)..." -ForegroundColor Cyan
    $v = Api POST '/networkvolumes' @{ name = 'faceswap'; size = $DiskGb; dataCenterId = $Dc }
    Set-Content $VolFile -Value $v.id -NoNewline
    Set-Content $DcFile -Value $Dc -NoNewline
    Write-Host "Tamam. Disk id: $($v.id)  (aylık ücret ~$([math]::Round($DiskGb*0.07,2)) $)" -ForegroundColor Green
    Write-Host (Bakiye)
}
# ------------------------------------------------------------------------------------------------
'ac' {
    $vol = $null
    if ($Cloud -eq 'secure') {
        if (-not (Test-Path $VolFile)) { Write-Host "Bu veri merkezinde ($Dc) disk yok. Önce: runpod.ps1 kur -Dc $Dc" -ForegroundColor Red; exit 1 }
        $vol = (Get-Content $VolFile -Raw).Trim()
        Set-Content $DcFile -Value $Dc -NoNewline
    }
    $tok = Token
    $pod = AcikPodlar | Select-Object -First 1
    if ($pod) {
        Write-Host "Pod zaten açık: $($pod.id)" -ForegroundColor Yellow
    } else {
        Write-Host "Pod açılıyor..." -ForegroundColor Cyan
        $boot = Get-Content (Join-Path $Root 'runpod\bootstrap.sh') -Raw
        $body = @{
            name = 'faceswap'; imageName = $Image; computeType = 'GPU'
            gpuTypeIds = $Gpus; gpuTypePriority = 'custom'; gpuCount = 1
            containerDiskInGb = 30; volumeMountPath = '/workspace'
            ports = @('8765/http')
            env = @{ FACESWAP_TOKEN = $tok; RUNPOD_API_KEY = $Key; FACESWAP_IDLE_MINUTES = "$BostaDk"; FACESWAP_THREADS = '8' }
            dockerEntrypoint = @('bash', '-c'); dockerStartCmd = @($boot)
        }
        if ($Cloud -eq 'imaj') {
            $body.Remove('dockerEntrypoint'); $body.Remove('dockerStartCmd')
            $body.cloudType = 'SECURE'; $body.volumeInGb = 20
            Write-Host "Hazır imaj: $Image (kurulum yok, tüm veri merkezleri; Secure + Community sırayla denenir)" -ForegroundColor Cyan
        } elseif ($Cloud -eq 'secure') {
            $body.cloudType = 'SECURE'; $body.networkVolumeId = $vol; $body.dataCenterIds = @($Dc)
            Write-Host "Secure Cloud, veri merkezi $Dc, kalıcı disk $vol"
        } elseif ($Cloud -eq 'disksiz') {
            $body.cloudType = 'SECURE'; $body.volumeInGb = 100
            Write-Host "Secure Cloud, kalıcı disk yok (kapanınca kurulum silinir)" -ForegroundColor Yellow
        } else {
            $body.cloudType = 'COMMUNITY'; $body.volumeInGb = 100
            Write-Host "Community Cloud (kalıcı disk yok; kapanınca kurulum silinir)" -ForegroundColor Yellow
        }
        Write-Host "İstenen kart(lar): $(($Gpus | ForEach-Object { $_ -replace 'NVIDIA ','' }) -join ', ')"
        $pod = $null; $tb = Get-Date; $deneme = 0
        while (-not $pod) {
            $deneme++
            if ($Cloud -eq 'imaj') { $body.cloudType = $(if ($deneme % 2 -eq 1) { 'SECURE' } else { 'COMMUNITY' }) }
            try { $pod = Api POST '/pods' $body }
            catch {
                if ($Cloud -eq 'imaj' -and $deneme % 2 -eq 1) { continue }   # Secure'da yoksa hemen Community'yi dene
                if ("$_" -notlike '*no instances*' -and "$_" -notlike '*instances available*' -and "$_" -notlike '*no longer*') { throw }
                $gecen = [int]((Get-Date) - $tb).TotalMinutes
                if ($gecen -ge $BekleDk) { Write-Host "`n$BekleDk dakikadır boş kart yok ($Cloud). Daha sonra tekrar dene." -ForegroundColor Yellow; exit 1 }
                Write-Host ("`r[{0:HH:mm}] boş kart yok, {1}. deneme, 60 sn sonra tekrar (toplam {2} dk bekleyeceğim)     " -f (Get-Date), $deneme, $BekleDk) -NoNewline
                Start-Sleep -Seconds 60
            }
        }
        Write-Host ''

        Write-Host "Pod id: $($pod.id)  GPU: $(GpuAdi $pod)  Ücret: $($pod.costPerHr) $/saat"
    }
    $url = ProxyUrl $pod.id
    Set-Content $AdrFile -Value $url -NoNewline

    # Kod paketi (sunucu + runpod klasörleri)
    $tar = Join-Path $env:TEMP 'faceswap_code.tar.gz'
    if (Test-Path $tar) { Remove-Item $tar -Force }
    & tar -czf $tar -C $Root sunucu runpod
    Write-Host "Pod başlıyor, bekleniyor (1-2 dk)..." -NoNewline
    $uploaded = $false; $t0 = Get-Date
    while (((Get-Date) - $t0).TotalMinutes -lt 25) {
        Start-Sleep -Seconds 5
        try {
            $s = Invoke-RestMethod -Uri "$url/ping" -TimeoutSec 10
        } catch { Write-Host '.' -NoNewline; continue }
        if ($s.ok -eq $true) {
            Write-Host "`nHAZIR." -ForegroundColor Green
            break
        }
        if ("$($s.stage)" -like 'HATA*') {
            Write-Host "`n$($s.stage)" -ForegroundColor Red
            try { $log = Invoke-RestMethod -Uri "$url/log" -TimeoutSec 15; Set-Content (Join-Path $Data 'pod_log.txt') -Value $log -Encoding UTF8; Write-Host "---- pod log (son kısım) ----"; Write-Host ($log -split "`n" | Select-Object -Last 40 | Out-String) } catch {}
            Write-Host "Log dosyası: data\pod_log.txt — Claude'a gönder. Pod'u kapatmak için: runpod.ps1 kapat" -ForegroundColor Yellow
            exit 1
        }
        if ($Cloud -eq 'imaj') { $uploaded = $true }   # kod imajın içinde
        if (-not $uploaded -and "$($s.stage)" -like 'Kod*') {
            Write-Host "`nKod yükleniyor..." -NoNewline
            try {
                Invoke-RestMethod -Method Post -Uri "$url/code" -InFile $tar -ContentType 'application/octet-stream' -TimeoutSec 120 | Out-Null
                $uploaded = $true; Write-Host ' tamam' 
            } catch { Write-Host " (tekrar denenecek) $($_.Exception.Message)" }
            continue
        }
        Write-Host "`r[$([int]((Get-Date)-$t0).TotalSeconds) sn] $($s.stage)                    " -NoNewline
    }
    Write-Host ''
    Write-Host "Uygulama ayarları:" -ForegroundColor Cyan
    Write-Host "  Sunucu adresi : $url"
    Write-Host "  Erişim kodu   : $tok"
    Write-Host "Boşta $BostaDk dk kalınca pod kendini kapatır. Elle kapatmak için: runpod.ps1 kapat"
    Write-Host (Bakiye)
}
# ------------------------------------------------------------------------------------------------
'kod' {
    # Açık pod'daki sunucuya yeni kodu gönderir; sunucu kendini yeniden başlatır (paket/model kurulumu yok).
    $pods = AcikPodlar
    if (-not $pods) { Write-Host "Açık pod yok. Önce: runpod.ps1 ac" -ForegroundColor Red; exit 1 }
    $pod = $pods[0]
    $url = ProxyUrl $pod.id
    $tok = (Get-Content $TokFile -Raw).Trim()
    $tar = Join-Path $env:TEMP 'faceswap_code.tar.gz'
    if (Test-Path $tar) { Remove-Item $tar -Force }
    & tar -czf $tar -C $Root sunucu runpod
    Write-Host "Kod gönderiliyor ($($pod.id))..." -NoNewline
    try {
        Invoke-RestMethod -Method Post -Uri "$url/code" -InFile $tar -ContentType 'application/octet-stream' -Headers @{ 'X-Token' = $tok } -TimeoutSec 120 | Out-Null
    } catch { Write-Host "`nGönderilemedi: $($_.Exception.Message)" -ForegroundColor Red; Write-Host "Not: video işlenirken kod yüklenemez (409). Pod eski kodla açıldıysa (/code yok, 404): kapat + ac." -ForegroundColor Yellow; exit 1 }
    Write-Host ' tamam. Sunucu yeniden başlıyor' -NoNewline
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalMinutes -lt 5) {
        Start-Sleep -Seconds 3
        try { $s = Invoke-RestMethod -Uri "$url/ping" -TimeoutSec 10 } catch { Write-Host '.' -NoNewline; continue }
        if ($s.ok -eq $true) { Write-Host "`nHAZIR. Adres aynı: $url" -ForegroundColor Green; exit 0 }
        if ("$($s.stage)" -like 'HATA*') { Write-Host "`n$($s.stage)" -ForegroundColor Red; exit 1 }
        Write-Host '.' -NoNewline
    }
    Write-Host "`nZaman aşımı. runpod.ps1 durum ile kontrol et." -ForegroundColor Red
}
# ------------------------------------------------------------------------------------------------
'kapat' {
    $pods = AcikPodlar
    if (-not $pods) { Write-Host "Açık pod yok." }
    foreach ($p in $pods) { Api DELETE "/pods/$($p.id)" | Out-Null; Write-Host "Kapatıldı: $($p.id)" -ForegroundColor Green }
    Write-Host (Bakiye)
}
# ------------------------------------------------------------------------------------------------
'durum' {
    Write-Host (Bakiye)
    $pods = AcikPodlar
    if (-not $pods) { Write-Host "Açık pod yok (ücret işlemiyor)." } 
    foreach ($p in $pods) {
        Write-Host "Pod $($p.id): $($p.desiredStatus)  GPU: $(GpuAdi $p)  $($p.costPerHr) $/saat  Adres: $(ProxyUrl $p.id)"
    }
    Get-ChildItem $Data -Filter 'runpod_volume_*.txt' | ForEach-Object { Write-Host "Kalıcı disk [$($_.BaseName -replace 'runpod_volume_','')]: $(Get-Content $_.FullName)" }
    Write-Host "Kullanılan veri merkezi: $Dc"
    if (Test-Path $TokFile) { Write-Host "Erişim kodu: $(Get-Content $TokFile)" }
}
# ------------------------------------------------------------------------------------------------
'stok' {
    Write-Host "Veri merkezlerine göre kart stoğu:" -ForegroundColor Cyan
    $q = 'query { dataCenters { id name gpuAvailability(input: {gpuCount: 1}) { gpuTypeId stockStatus available } } }'
    try { $raw = Invoke-RestMethod -Method Post -Uri 'https://api.runpod.io/graphql' -Headers $H -Body ([System.Text.Encoding]::UTF8.GetBytes((J @{ query = $q }))) -TimeoutSec 60 }
    catch { Write-Host "Sorgu başarısız: $_" -ForegroundColor Red; break }
    ($raw | ConvertTo-Json -Depth 10) | Set-Content (Join-Path $Data 'stok.json') -Encoding UTF8
    if ($raw.errors) { Write-Host "API: $($raw.errors[0].message)" -ForegroundColor Red; break }
    foreach ($c in $raw.data.dataCenters) {
        $list = @($c.gpuAvailability | Where-Object { $_.gpuTypeId -match '4090|A5000|4000 Ada|L4$|A4500|3090' })
        $var = @($list | Where-Object { $_.available -eq $true -or ("$($_.stockStatus)" -ne '' -and "$($_.stockStatus)" -notmatch 'Unavailable|None') })
        if ($var.Count -gt 0) {
            Write-Host ("  {0,-10} " -f $c.id) -NoNewline
            Write-Host (($var | ForEach-Object { "$($_.gpuTypeId -replace 'NVIDIA ','')[$($_.stockStatus)]" }) -join ', ')
        }
    }
    Write-Host "(ayrıntı: data\stok.json)"
    Write-Host "`nCommunity Cloud (kalıcı disk yok, daha ucuz):" -ForegroundColor Cyan
    $q2 = 'query { gpuTypes { id communityPrice securePrice lowestPrice(input: {gpuCount: 1, secureCloud: false}) { stockStatus uninterruptablePrice } } }'
    try {
        $raw2 = Invoke-RestMethod -Method Post -Uri 'https://api.runpod.io/graphql' -Headers $H -Body ([System.Text.Encoding]::UTF8.GetBytes((J @{ query = $q2 }))) -TimeoutSec 60
        ($raw2 | ConvertTo-Json -Depth 10) | Set-Content (Join-Path $Data 'stok_community.json') -Encoding UTF8
        foreach ($g in $raw2.data.gpuTypes) {
            if ($g.id -match '4090|A5000|4000 Ada|L4$|A4500|3090|A6000|L40') {
                Write-Host ("  {0,-36} stok: {1,-8} community {2} $/sa  secure {3} $/sa" -f ($g.id -replace 'NVIDIA ',''), $g.lowestPrice.stockStatus, $g.communityPrice, $g.securePrice)
            }
        }
    } catch { Write-Host "Community sorgusu başarısız: $_" -ForegroundColor Yellow }
    Write-Host "`nSeçtiğin merkez için:  runpod.ps1 kur -Dc <ID>   sonra   runpod.ps1 ac -Dc <ID>"
}
# ------------------------------------------------------------------------------------------------
'disksil' {
    if (-not (Test-Path $VolFile)) { Write-Host "Bu merkezde ($Dc) disk yok."; break }
    $vol = (Get-Content $VolFile -Raw).Trim()
    if (AcikPodlar) { Write-Host "Önce pod'u kapat: runpod.ps1 kapat" -ForegroundColor Red; break }
    Api DELETE "/networkvolumes/$vol" | Out-Null
    Remove-Item $VolFile -Force
    Write-Host "Disk silindi ($Dc): $vol" -ForegroundColor Green
}
}
