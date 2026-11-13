import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/runpod_card.dart';

/// Sonuç: videoyu indir, oynat, galeriye kaydet, paylaş.
class ResultScreen extends StatefulWidget {
  final String jobId;
  const ResultScreen({super.key, required this.jobId});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  Job? _job;
  File? _file;
  double _dl = 0;
  String? _error;
  VideoPlayerController? _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _job = await Api.I.job(widget.jobId);
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/faceswap_${widget.jobId}.mp4';
      final f = File(path);
      if (!await f.exists() || await f.length() == 0) {
        await Api.I.downloadResult(widget.jobId, path, onProgress: (p) {
          if (mounted) setState(() => _dl = p);
        });
      }
      final c = VideoPlayerController.file(f);
      await c.initialize();
      c.setLooping(true);
      c.play();
      if (!mounted) return;
      setState(() {
        _file = f;
        _ctrl = c;
      });
    } catch (e) {
      if (mounted) setState(() => _error = Api.err(e));
    }
  }

  Future<void> _save() async {
    if (_file == null) return;
    setState(() => _saving = true);
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putVideo(_file!.path, album: 'FaceSwap');
      if (mounted) snack(context, 'Galeriye kaydedildi (FaceSwap albümü).');
    } catch (e) {
      if (mounted) snack(context, 'Kaydedilemedi: $e', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _share() async {
    if (_file == null) return;
    await Share.shareXFiles([XFile(_file!.path)], text: 'FaceSwap');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _ctrl;
    return Scaffold(
      appBar: AppBar(title: const Text('Sonuç'), actions: const [BalanceChip()]),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center))
                    : c == null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              Text('İndiriliyor  %${(_dl * 100).round()}'),
                            ],
                          )
                        : GestureDetector(
                            onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
                            child: AspectRatio(
                              aspectRatio: c.value.aspectRatio,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  VideoPlayer(c),
                                  if (!c.value.isPlaying) const Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
                                ],
                              ),
                            ),
                          ),
              ),
            ),
            if (_job != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${presetLabels[_job!.preset] ?? _job!.preset}${_job!.elapsed != null ? ' · ${fmtSeconds(_job!.elapsed!)} sürdü' : ''}',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _file == null || _saving ? null : _save,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Galeriye kaydet'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _file == null ? null : _share,
                      icon: const Icon(Icons.share),
                      label: const Text('Paylaş'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
