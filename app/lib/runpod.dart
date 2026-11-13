import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// RunPod'u telefondan yönetir: bakiye, pod aç/kapat, kalıcı disk.
/// runpod.ps1 ile aynı API'yi kullanır; bilgisayara gerek kalmaz.
class RunPod extends ChangeNotifier {
  RunPod._();
  static final RunPod I = RunPod._();

  static const _rest = 'https://rest.runpod.io/v1';
  static const _gql = 'https://api.runpod.io/graphql';
  static const baseImage = 'runpod/pytorch:1.5.0-cu1281-torch280-ubuntu2404'; // kurulumlu açılış (10 dk)
  static const readyImage = 'ghcr.io/ozgurgokce1905/faceswap:latest'; // hazır imaj (kurulum yok, ~2 dk)

  /// Kart seçenekleri: anahtar -> (görünen ad, gpuTypeIds, yaklaşık $/saat)
  static const gpuOptions = <String, GpuOption>{
    'h100': GpuOption('H100 80 GB (en hızlı)', ['NVIDIA H100 80GB HBM3', 'NVIDIA H100 PCIe', 'NVIDIA H100 NVL'], 3.99),
    'a100': GpuOption('A100 80 GB', ['NVIDIA A100 80GB PCIe', 'NVIDIA A100-SXM4-80GB'], 2.2),
    'l40s': GpuOption('L40S 48 GB', ['NVIDIA L40S'], 1.1),
    'a6000': GpuOption('RTX A6000 48 GB', ['NVIDIA RTX A6000', 'NVIDIA RTX 6000 Ada Generation'], 0.8),
    '4090': GpuOption('RTX 4090 24 GB (ucuz)', ['NVIDIA GeForce RTX 4090', 'NVIDIA RTX A5000', 'NVIDIA GeForce RTX 3090'], 0.89),
  };

  // ---- ayarlar (SharedPreferences)
  String apiKey = '';
  String gpu = 'h100';
  bool useVolume = false; // H100 bulunan merkezlerde kalıcı disk çoğu zaman yok; varsayılan kapalı
  String dc = 'US-MO-1'; // H100'ün bulunduğu merkez (3 Kasım 2026 testleri)
  int idleMinutes = 10;
  int volumeGb = 30;
  bool useReadyImage = true; // hazır imajla aç (kurulum yok)
  Map<String, String> volumes = {}; // dc -> volume id

  // ---- canlı durum
  double? balance; // $
  double? spendPerHr; // $/saat (RunPod hesabı geneli)
  PodInfo? pod; // açık pod (faceswap adlı)
  String stage = ''; // açılış aşaması / mesaj
  bool working = false; // aç/kapat işlemi sürüyor
  String? lastError; // son aç/kapat hatası (kullanıcı kapatana kadar kalır)
  String? apiError; // bakiye/pod sorgusu hatası
  String? volumeNote; // kalıcı disk açılamadıysa açıklama
  bool ready = false; // sunucu /ping ok
  int retryCount = 0;
  bool _cancelOpen = false;
  Timer? _timer;

  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 60)));
  final Dio _plain = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 20)));

  bool get configured => apiKey.isNotEmpty;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    apiKey = p.getString('rp_key') ?? '';
    gpu = p.getString('rp_gpu') ?? 'h100';
    useVolume = p.getBool('rp_volume') ?? false;
    dc = p.getString('rp_dc') ?? 'US-MO-1';
    idleMinutes = p.getInt('rp_idle') ?? 10;
    volumeGb = p.getInt('rp_volume_gb') ?? 30;
    useReadyImage = p.getBool('rp_ready_image') ?? true;
    final v = p.getString('rp_volumes');
    if (v != null && v.isNotEmpty) {
      volumes = (jsonDecode(v) as Map).map((k, val) => MapEntry(k as String, val as String));
    }
  }

  Future<void> save({String? key, String? gpuKey, bool? volume, String? dataCenter, int? idle, bool? readyImage}) async {
    final p = await SharedPreferences.getInstance();
    if (key != null) {
      apiKey = key.trim();
      await p.setString('rp_key', apiKey);
    }
    if (gpuKey != null) {
      gpu = gpuKey;
      await p.setString('rp_gpu', gpu);
    }
    if (volume != null) {
      useVolume = volume;
      await p.setBool('rp_volume', volume);
    }
    if (dataCenter != null) {
      dc = dataCenter.trim().toUpperCase();
      await p.setString('rp_dc', dc);
    }
    if (idle != null) {
      idleMinutes = idle;
      await p.setInt('rp_idle', idle);
    }
    if (readyImage != null) {
      useReadyImage = readyImage;
      await p.setBool('rp_ready_image', readyImage);
    }
    notifyListeners();
  }

  Future<void> _saveVolumes() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('rp_volumes', jsonEncode(volumes));
  }

  Options get _auth => Options(headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'});

  /// Periyodik yenileme (ana ekran açıkken). Bakiye + pod durumu.
  void startPolling() {
    _timer?.cancel();
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    if (!configured) return;
    try {
      final r = await _dio.post(_gql,
          data: jsonEncode({
            'query': 'query { myself { clientBalance currentSpendPerHr pods { id name costPerHr desiredStatus machine { gpuDisplayName } runtime { uptimeInSeconds } } } }'
          }),
          options: _auth);
      final data = r.data is String ? jsonDecode(r.data as String) : r.data;
      final me = (data['data']?['myself'] ?? {}) as Map;
      balance = (me['clientBalance'] as num?)?.toDouble();
      spendPerHr = (me['currentSpendPerHr'] as num?)?.toDouble();
      final pods = (me['pods'] ?? []) as List;
      final mine = pods.cast<Map>().where((p) => p['name'] == 'faceswap').toList();
      if (mine.isEmpty) {
        pod = null;
        ready = false;
        if (!working) stage = '';
      } else {
        final m = mine.first;
        pod = PodInfo(
          id: m['id'] as String,
          costPerHr: (m['costPerHr'] as num?)?.toDouble() ?? 0,
          gpuName: ((m['machine'] ?? {}) as Map)['gpuDisplayName']?.toString() ?? '?',
          uptimeSeconds: ((m['runtime'] ?? {}) as Map?)?['uptimeInSeconds'] as int? ?? 0,
          status: m['desiredStatus']?.toString() ?? '',
        );
        if (!working) await _checkPing();
      }
      apiError = null;
    } catch (e) {
      apiError = _err(e);
    }
    notifyListeners();
  }

  String urlFor(String podId) => 'https://$podId-8765.proxy.runpod.net';

  Future<void> _checkPing() async {
    if (pod == null) return;
    try {
      final r = await _plain.get('${urlFor(pod!.id)}/ping');
      final d = r.data is String ? jsonDecode(r.data as String) : r.data;
      if (d['ok'] == true) {
        if (!ready) await _adopt();
        ready = true;
        stage = '';
      } else {
        ready = false;
        stage = d['stage']?.toString() ?? 'Başlıyor';
      }
    } catch (_) {
      ready = false;
      stage = 'Pod başlıyor…';
    }
  }

  /// Hazır pod'un adresini ve erişim kodunu uygulama ayarına yazar.
  Future<void> _adopt() async {
    final url = urlFor(pod!.id);
    if (Api.I.baseUrl != url) await Api.I.save(base: url);
    if (Api.I.token.isEmpty) await Api.I.save(tok: _newToken());
  }

  String _newToken() {
    final r = Random.secure();
    return List.generate(32, (_) => '0123456789abcdef'[r.nextInt(16)]).join();
  }

  /// Kalıcı disk yoksa oluşturur (seçili veri merkezinde). Disk id döner.
  Future<String> ensureVolume() async {
    final existing = volumes[dc];
    if (existing != null) return existing;
    // Hesaptaki diskleri de kontrol et (bilgisayardan kurulmuş olabilir)
    try {
      final r = await _dio.get('$_rest/networkvolumes', options: _auth);
      for (final v in (r.data as List).cast<Map>()) {
        if (v['name'] == 'faceswap' && v['dataCenterId'] == dc) {
          volumes[dc] = v['id'] as String;
          await _saveVolumes();
          return volumes[dc]!;
        }
      }
    } catch (_) {}
    final r = await _dio.post('$_rest/networkvolumes', data: jsonEncode({'name': 'faceswap', 'size': volumeGb, 'dataCenterId': dc}), options: _auth);
    final id = r.data['id'] as String;
    volumes[dc] = id;
    await _saveVolumes();
    return id;
  }

  /// Pod açar, kodu yükler, HAZIR olana kadar bekler. İlerleme `stage` ile.
  Future<void> open() async {
    if (working) return;
    working = true;
    _cancelOpen = false;
    retryCount = 0;
    lastError = null;
    volumeNote = null;
    stage = 'Hazırlanıyor…';
    notifyListeners();
    try {
      await refresh();
      if (pod == null) {
        if (Api.I.token.isEmpty) await Api.I.save(tok: _newToken());
        final boot = useReadyImage ? 'bash /opt/fs/runpod/image_start.sh' : await rootBundle.loadString('assets/runpod/bootstrap.sh');
        final opt = gpuOptions[gpu] ?? gpuOptions['h100']!;
        final body = <String, dynamic>{
          'name': 'faceswap',
          'imageName': useReadyImage ? readyImage : baseImage,
          'computeType': 'GPU',
          'gpuTypeIds': opt.ids,
          'gpuTypePriority': 'custom',
          'gpuCount': 1,
          'containerDiskInGb': 30,
          'volumeMountPath': '/workspace',
          'ports': ['8765/http'],
          'env': {
            'FACESWAP_TOKEN': Api.I.token,
            'RUNPOD_API_KEY': apiKey,
            'FACESWAP_IDLE_MINUTES': '$idleMinutes',
            'FACESWAP_THREADS': '8',
          },
          'dockerEntrypoint': ['bash', '-c'],
          'dockerStartCmd': [boot],
          'cloudType': 'SECURE',
        };
        var volOk = false;
        if (useVolume) {
          stage = 'Kalıcı disk kontrol ediliyor…';
          notifyListeners();
          try {
            final vol = await ensureVolume();
            body['networkVolumeId'] = vol;
            body['dataCenterIds'] = [dc];
            volOk = true;
          } catch (e) {
            volumeNote = 'Kalıcı disk açılamadı ($dc): ${_err(e)} — disksiz devam ediliyor.';
          }
        }
        if (!volOk) body['volumeInGb'] = 100; // tüm vücut modelleri (~50 GB) de buraya iner
        stage = 'Pod isteniyor (${opt.label})…';
        notifyListeners();
        String? podId;
        while (podId == null) {
          if (_cancelOpen) throw 'İptal edildi';
          try {
            final r = await _dio.post('$_rest/pods', data: jsonEncode(body), options: _auth);
            podId = r.data['id'] as String;
          } catch (e) {
            final msg = _err(e).toLowerCase();
            final noStock = msg.contains('no instances') || msg.contains('instances available') || msg.contains('no longer');
            if (!noStock) rethrow;
            retryCount++;
            if (retryCount > 60) throw 'Bir saattir boş kart yok. Ayarlardan başka kart seç.';
            for (var i = 60; i > 0 && !_cancelOpen; i--) {
              stage = 'Boş kart yok (${opt.label}). $retryCount. deneme, $i sn sonra tekrar…';
              notifyListeners();
              await Future.delayed(const Duration(seconds: 1));
            }
          }
        }
        pod = PodInfo(id: podId, costPerHr: opt.pricePerHr, gpuName: opt.label, uptimeSeconds: 0, status: 'RUNNING');
        stage = 'Pod başlıyor (1-2 dk)…';
        notifyListeners();
      }
      await _waitReady();
    } catch (e) {
      lastError = 'Açılamadı: ${_err(e)}';
      stage = '';
    } finally {
      working = false;
      notifyListeners();
      refresh();
    }
  }

  void clearError() {
    lastError = null;
    notifyListeners();
  }

  void cancelOpen() => _cancelOpen = true;

  Future<void> _waitReady() async {
    final url = urlFor(pod!.id);
    var uploaded = false;
    final t0 = DateTime.now();
    while (DateTime.now().difference(t0).inMinutes < 30) {
      if (_cancelOpen) throw 'İptal edildi';
      await Future.delayed(const Duration(seconds: 4));
      Map d;
      try {
        final r = await _plain.get('$url/ping');
        d = r.data is String ? jsonDecode(r.data as String) : r.data as Map;
      } catch (_) {
        continue;
      }
      if (d['ok'] == true) {
        await _adopt();
        ready = true;
        stage = '';
        return;
      }
      final s = d['stage']?.toString() ?? '';
      if (s.startsWith('HATA')) throw s;
      if (!uploaded && s.startsWith('Kod')) {
        stage = 'Kod yükleniyor…';
        notifyListeners();
        try {
          final bytes = await rootBundle.load('assets/runpod/code.tar.gz');
          await _plain.post('$url/code',
              data: bytes.buffer.asUint8List(),
              options: Options(headers: {'Content-Type': 'application/octet-stream'}, sendTimeout: const Duration(minutes: 2)));
          uploaded = true;
        } catch (e) {
          stage = 'Kod yüklenemedi, tekrar denenecek';
        }
        continue;
      }
      final secs = DateTime.now().difference(t0).inSeconds;
      stage = '$s  (${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')})';
      notifyListeners();
    }
    throw 'Zaman aşımı: pod 30 dakikada hazır olmadı';
  }

  /// Açık pod'a yeni sunucu kodunu gönderir (kurulum tekrarlanmaz).
  Future<void> updateCode() async {
    if (pod == null) throw 'Açık pod yok';
    final url = urlFor(pod!.id);
    final bytes = await rootBundle.load('assets/runpod/code.tar.gz');
    await _plain.post('$url/code',
        data: bytes.buffer.asUint8List(),
        options: Options(headers: {'Content-Type': 'application/octet-stream', 'X-Token': Api.I.token}, sendTimeout: const Duration(minutes: 2)));
    working = true;
    stage = 'Sunucu yeniden başlıyor…';
    notifyListeners();
    try {
      await _waitReady();
    } finally {
      working = false;
      notifyListeners();
    }
  }

  Future<void> close() async {
    if (pod == null) return;
    working = true;
    stage = 'Kapatılıyor…';
    notifyListeners();
    try {
      await _dio.delete('$_rest/pods/${pod!.id}', options: _auth);
      pod = null;
      ready = false;
      stage = '';
    } catch (e) {
      lastError = _err(e);
    } finally {
      working = false;
      notifyListeners();
      refresh();
    }
  }

  static String _err(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d != null) {
        if (d is Map && d['error'] != null) return d['error'].toString();
        if (d is Map && d['detail'] != null) return d['detail'].toString();
        final s = d.toString();
        if (s.trim().isNotEmpty) return s.length > 300 ? s.substring(0, 300) : s;
      }
      if (e.response?.statusCode == 401) return 'API anahtarı geçersiz (401)';
      return e.message ?? e.toString();
    }
    return e.toString();
  }
}

class GpuOption {
  final String label;
  final List<String> ids;
  final double pricePerHr;
  const GpuOption(this.label, this.ids, this.pricePerHr);
}

class PodInfo {
  final String id;
  final double costPerHr;
  final String gpuName;
  final int uptimeSeconds;
  final String status;
  PodInfo({required this.id, required this.costPerHr, required this.gpuName, required this.uptimeSeconds, required this.status});

  /// Bu açılışta harcanan tahmini tutar.
  double get spent => costPerHr * uptimeSeconds / 3600;
}
