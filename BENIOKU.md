# FaceSwap (kendi bilgisayarında çalışan yüz değiştirme sunucusu)

Motor: FaceFusion 3.9.2 (açık kaynak) + onnxruntime (NVIDIA varsa CUDA, yoksa DirectML ile Intel/AMD ekran kartı). Hiçbir ücretli servis yok.

## Klasörler
- `kur.ps1`       – tek seferlik kurulum
- `calistir.ps1`  – sunucuyu başlatır (telefon buna bağlanır)
- `gpu_test.ps1`  – hangi hızlandırıcı çalışıyor (cuda / directml / cpu) -> data\provider.txt
- `directml_gec.ps1` – NVIDIA kartı olmayan makinede DirectML'e geçiş (tek sefer)
- `ortam.ps1`     – ortak ortam ayarları (elle çalıştırılmaz)
- `sunucu/`       – API (server.py), FaceFusion köprüsü, kalite ön ayarları, testler
- `facefusion/`   – kurulumda indirilir
- `venv/`         – kurulumda oluşur
- `data/`         – videolar, yüz kütüphanesi, işler (sonuçlar `data/jobs/<iş>/sonuc.mp4`)

## Kurulum (PowerShell)
    powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\kur.ps1

## Çalıştırma
    powershell -ExecutionPolicy Bypass -File D:\Dev\faceswap\calistir.ps1

## Telefon olmadan test
    D:\Dev\faceswap\venv\Scripts\python.exe D:\Dev\faceswap\sunucu\cli_test.py --video C:\video.mp4 --face C:\yuz.jpg

## Kalite ön ayarları (sunucu/presets.py)
- `hizli`    : sadece yüz değiştirme (önizleme)
- `kaliteli` : değiştir + hafif netleştirme (varsayılan)
- `ultra`    : değiştir + mimikleri geri getir (LivePortrait) + netleştirme (en gerçekçi, en yavaş)

## Notlar
- İçerik filtresi FaceFusion'ın kendi filtresidir, kapatılamaz (uygunsuz videoyu işlemez, hata kodu 3).
- Sağ alt köşeye küçük "AI" etiketi eklenir; iş başlatırken `watermark=false` ile kapatılabilir.
- Kullanılan modellerin lisansı ticari olmayan/kişisel kullanım içindir.
