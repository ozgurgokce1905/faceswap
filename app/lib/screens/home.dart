import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../models.dart';
import '../runpod.dart';
import '../widgets/common.dart';
import '../widgets/runpod_card.dart';
import 'editor.dart';
import 'progress.dart';
import 'result.dart';
import 'settings.dart';

/// Ana ekran: sunucu durumu + büyük "Video Seç" + son işler.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ServerHealth? _health;
  String? _healthError;
  List<Job> _jobs = [];
  bool _uploading = false;
  double _uploadPct = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh(silent: true));
    RunPod.I.startPolling();
    RunPod.I.addListener(_onRunPod);
  }

  @override
  void dispose() {
    _timer?.cancel();
    RunPod.I.removeListener(_onRunPod);
    RunPod.I.stopPolling();
    super.dispose();
  }

  bool _wasReady = false;
  void _onRunPod() {
    // Pod hazır olunca adres otomatik değişti; sunucu durumunu hemen yenile
    final r = RunPod.I.ready;
    if (r != _wasReady) {
      _wasReady = r;
      _refresh(silent: true);
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final h = await Api.I.health();
      final j = await Api.I.jobs();
      if (!mounted) return;
      setState(() {
        _health = h;
        _healthError = null;
        _jobs = j;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _health = null;
        _healthError = Api.err(e);
      });
    }
  }

  Future<void> _pickVideo() async {
    if (_health == null) {
      snack(context, RunPod.I.configured ? 'Önce "Sunucuyu Aç" düğmesine bas ve HAZIR olmasını bekle.' : 'Önce sunucuya bağlan (sağ üstteki ayarlar).', error: true);
      return;
    }
    final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    setState(() {
      _uploading = true;
      _uploadPct = 0;
    });
    try {
      final meta = await Api.I.uploadVideo(File(x.path), onProgress: (p) {
        if (mounted) setState(() => _uploadPct = p);
      });
      if (!mounted) return;
      setState(() => _uploading = false);
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(video: meta, health: _health!)));
      _refresh(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      snack(context, Api.err(e), error: true);
    }
  }

  Future<void> _openJob(Job j) async {
    if (j.status == 'done') {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultScreen(jobId: j.id)));
    } else if (j.status == 'queued' || j.status == 'running') {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProgressScreen(jobId: j.id)));
    } else {
      snack(context, j.error ?? j.stage, error: j.status == 'error');
    }
    _refresh(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final connected = _health != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FaceSwap', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          const BalanceChip(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
              _refresh();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // Sunucu durumu
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: connected ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(connected ? Icons.check_circle : Icons.error_outline, color: connected ? Colors.greenAccent : Colors.redAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        connected
                            ? 'Sunucu bağlı · ${_health!.provider}${_health!.busy ? ' · meşgul' : ''}'
                            : 'Sunucu yok: ${_healthError ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              RunPodCard(onOpenSettings: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
                _refresh();
              }),
              const SizedBox(height: 14),
              // Ana aksiyon
              InkWell(
                onTap: _uploading ? null : _pickVideo,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: 150,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _uploading
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Video yükleniyor  %${(_uploadPct * 100).round()}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 40),
                              child: LinearProgressIndicator(value: _uploadPct, color: Colors.white, backgroundColor: Colors.white24),
                            ),
                          ],
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.video_library_outlined, size: 44, color: Colors.white),
                            SizedBox(height: 10),
                            Text('Video Seç', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                            SizedBox(height: 4),
                            Text('Galeriden bir video seç, kişiye dokun, yüzü değiştir', style: TextStyle(fontSize: 13, color: Colors.white70)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Son işler', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.85))),
              const SizedBox(height: 8),
              if (_jobs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Henüz iş yok.', style: TextStyle(color: cs.onSurface.withOpacity(0.5)))),
                ),
              for (final j in _jobs) _JobTile(job: j, onTap: () => _openJob(j), onDelete: () async {
                await Api.I.deleteJob(j.id);
                _refresh(silent: true);
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _JobTile({required this.job, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    IconData icon;
    Color color;
    String sub;
    switch (job.status) {
      case 'done':
        icon = Icons.check_circle;
        color = Colors.greenAccent;
        sub = 'Tamamlandı · ${presetLabels[job.preset] ?? job.preset}${job.elapsed != null ? ' · ${fmtSeconds(job.elapsed!)}' : ''}';
        break;
      case 'running':
        icon = Icons.autorenew;
        color = cs.primary;
        sub = '${job.stage} · %${job.percent.round()}';
        break;
      case 'queued':
        icon = Icons.schedule;
        color = Colors.amber;
        sub = 'Sırada';
        break;
      case 'cancelled':
        icon = Icons.cancel;
        color = Colors.grey;
        sub = 'İptal edildi';
        break;
      default:
        icon = Icons.error;
        color = Colors.redAccent;
        sub = job.error ?? 'Hata';
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color),
        title: Text('${job.mode == 'vucut' ? '[Tüm vücut] ' : ''}${job.videoName ?? job.id}', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
      ),
    );
  }
}
