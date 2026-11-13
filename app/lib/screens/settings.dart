import 'package:flutter/material.dart';

import '../api.dart';
import '../runpod.dart';
import '../widgets/common.dart';
import '../widgets/runpod_card.dart';

/// Ayarlar: sunucu adresi, filigran, varsayılan kalite.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _addr = TextEditingController(text: Api.I.baseUrl);
  late final TextEditingController _tok = TextEditingController(text: Api.I.token);
  bool _wm = Api.I.watermark;
  String _preset = Api.I.defaultPreset;
  String? _status;
  bool _testing = false;
  late final TextEditingController _rpKey = TextEditingController(text: RunPod.I.apiKey);
  late final TextEditingController _rpDc = TextEditingController(text: RunPod.I.dc);
  bool _showKey = false;
  String _gpu = RunPod.I.gpu;
  bool _vol = RunPod.I.useVolume;
  int _idle = RunPod.I.idleMinutes;
  bool _readyImage = RunPod.I.useReadyImage;
  String? _rpStatus;

  Future<void> _saveRunPod() async {
    await RunPod.I.save(key: _rpKey.text, gpuKey: _gpu, volume: _vol, dataCenter: _rpDc.text, idle: _idle, readyImage: _readyImage);
    setState(() => _rpStatus = 'Kontrol ediliyor…');
    await RunPod.I.refresh();
    if (!mounted) return;
    setState(() => _rpStatus = RunPod.I.apiKey.isEmpty ? 'API anahtarı boş' : (RunPod.I.apiError != null ? 'Hata: ${RunPod.I.apiError}' : 'Bağlandı ✓  Bakiye ${fmtUsd(RunPod.I.balance)}'));
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });
    await Api.I.save(base: _addr.text, tok: _tok.text);
    try {
      final h = await Api.I.health();
      setState(() => _status = 'Bağlandı ✓  (${h.provider})');
    } catch (e) {
      setState(() => _status = 'Bağlanamadı: ${Api.err(e)}');
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar'), actions: const [BalanceChip()]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('RunPod (kiralık ekran kartı)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _rpKey,
              obscureText: !_showKey,
              decoration: InputDecoration(
                labelText: 'RunPod API anahtarı',
                hintText: 'rpa_… (runpod.io → Settings → API Keys)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showKey = !_showKey)),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _gpu,
              decoration: const InputDecoration(labelText: 'Ekran kartı', border: OutlineInputBorder()),
              items: [for (final e in RunPod.gpuOptions.entries) DropdownMenuItem(value: e.key, child: Text('${e.value.label}  ·  ~${fmtUsd(e.value.pricePerHr)}/sa'))],
              onChanged: (v) => setState(() => _gpu = v ?? 'h100'),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hazır imajla aç (önerilir)'),
              subtitle: const Text('Kurulum ve modeller imajın içinde: açılış ~2 dk, her merkezde çalışır. Kapalıysa her açılışta ~10 dk kurulum.'),
              value: _readyImage,
              onChanged: (v) => setState(() => _readyImage = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Kalıcı disk kullan'),
              subtitle: Text('Kurulum diskte kalır: açılış ~1-2 dk, aylık ~${fmtUsd(RunPod.I.volumeGb * 0.07)}. Ancak H100 olan merkezlerde çoğu zaman disk desteği yok; açılamazsa disksiz devam eder (~10 dk).'),
              value: _vol,
              onChanged: (v) => setState(() => _vol = v),
            ),
            if (_vol)
              TextField(
                controller: _rpDc,
                decoration: const InputDecoration(labelText: 'Veri merkezi (diskin yeri)', hintText: 'US-MO-1', border: OutlineInputBorder(), helperText: 'H100 bulunan merkez. Değiştirirsen yeni disk açılır.'),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Boşta kapanma: '),
                DropdownButton<int>(
                  value: _idle,
                  items: [for (final m in const [5, 10, 15, 30]) DropdownMenuItem(value: m, child: Text('$m dk'))],
                  onChanged: (v) => setState(() => _idle = v ?? 10),
                ),
              ],
            ),
            FilledButton.tonal(onPressed: _saveRunPod, child: const Text('RunPod ayarlarını kaydet')),
            if (_rpStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_rpStatus!, style: TextStyle(color: _rpStatus!.startsWith('Bağlandı') ? Colors.greenAccent : Colors.amber)),
              ),
            const Divider(height: 32),
            const Text('Elle sunucu adresi (bilgisayar için)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Sunucu adresi', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _addr,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'http://192.168.1.107:8765', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            Text('RunPod kullanıyorsan buraya dokunma; pod açılınca adres ve kod otomatik dolar. Bilgisayar sunucusu için: pencerede yazan "Adres" satırı.', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
            const SizedBox(height: 12),
            const Text('Erişim kodu (RunPod için)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _tok,
              decoration: const InputDecoration(hintText: 'runpod.ps1 ac çıktısındaki kod; bilgisayarda boş bırak', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: _testing ? null : _test,
              child: Text(_testing ? 'Deneniyor…' : 'Kaydet ve bağlantıyı dene'),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status!, style: TextStyle(color: _status!.startsWith('Bağlandı') ? Colors.greenAccent : Colors.redAccent)),
              ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('"AI" etiketi ekle'),
              subtitle: const Text('Sonuç videonun sağ alt köşesine küçük bir AI işareti koyar.'),
              value: _wm,
              onChanged: (v) async {
                await Api.I.save(wm: v);
                setState(() => _wm = v);
              },
            ),
            const Divider(height: 32),
            const Text('Varsayılan kalite', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [for (final k in const ['hizli', 'kaliteli', 'ultra']) ButtonSegment(value: k, label: Text(presetLabels[k]!))],
              selected: {_preset},
              onSelectionChanged: (s) async {
                await Api.I.save(preset: s.first);
                setState(() => _preset = s.first);
              },
            ),
            const SizedBox(height: 32),
            Center(child: Text('FaceSwap · created by Ozgur Gokce', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)))),
          ],
        ),
      ),
    );
  }
}
