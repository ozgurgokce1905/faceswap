import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/runpod_card.dart';
import '../widgets/face_overlay.dart';
import 'progress.dart';

/// Düzenleme ekranı: karede kişiye dokun -> kütüphaneden yüz seç -> kalite -> Değiştir.
class EditorScreen extends StatefulWidget {
  final VideoMeta video;
  final ServerHealth health;
  const EditorScreen({super.key, required this.video, required this.health});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  int _frame = 0;
  double _sliderFrame = 0;
  FrameFaces? _faces;
  bool _loadingFaces = false;
  String? _facesError;
  int? _selectedFace; // karedeki kişi (index)
  List<LibraryFace> _library = [];
  String? _selectedLib; // kütüphane yüz id
  late String _preset;
  String _mode = 'yuz'; // 'yuz' | 'vucut'
  late RangeValues _range; // saniye
  Timer? _debounce;
  bool _starting = false;

  VideoMeta get v => widget.video;

  @override
  void initState() {
    super.initState();
    _preset = Api.I.defaultPreset;
    _range = RangeValues(0, v.duration);
    _loadFaces();
    _loadLibrary();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadFaces() async {
    setState(() {
      _loadingFaces = true;
      _facesError = null;
    });
    try {
      final f = await Api.I.faces(v.id, _frame);
      if (!mounted) return;
      setState(() {
        _faces = f;
        _loadingFaces = false;
        if (_selectedFace != null && !f.faces.any((x) => x.index == _selectedFace)) _selectedFace = null;
        if (_selectedFace == null && f.faces.length == 1) _selectedFace = f.faces.first.index;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFaces = false;
        _facesError = Api.err(e);
      });
    }
  }

  Future<void> _loadLibrary() async {
    try {
      final l = await Api.I.listFaces();
      if (!mounted) return;
      setState(() {
        _library = l;
        _selectedLib ??= l.isNotEmpty ? l.first.id : null;
      });
    } catch (e) {
      if (mounted) snack(context, Api.err(e), error: true);
    }
  }

  void _onSlider(double value) {
    setState(() => _sliderFrame = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _frame = value.round();
      _loadFaces();
      setState(() {});
    });
  }

  Future<void> _addFace(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 95);
    if (x == null) return;
    try {
      final f = await Api.I.addFace(File(x.path));
      if (!mounted) return;
      setState(() {
        _library.insert(0, f);
        _selectedLib = f.id;
      });
    } catch (e) {
      if (mounted) snack(context, Api.err(e), error: true);
    }
  }

  Future<void> _deleteFace(LibraryFace f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Yüzü sil?'),
        content: const Text('Bu yüz kütüphaneden kaldırılacak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true) return;
    await Api.I.deleteFace(f.id);
    setState(() {
      _library.removeWhere((x) => x.id == f.id);
      if (_selectedLib == f.id) _selectedLib = _library.isNotEmpty ? _library.first.id : null;
    });
  }

  int get _trimStartFrame => (_range.start * v.fps).round();
  int get _trimEndFrame => (_range.end * v.fps).round().clamp(_trimStartFrame + 1, v.frameCount).toInt();
  int get _frameTotal => _trimEndFrame - _trimStartFrame;
  double get _estimateSeconds => _mode == 'vucut'
      ? (_frameTotal / v.fps * 30) * (widget.health.body.secondsPerFrame[_preset] ?? 2.5) + 120
      : _frameTotal * (widget.health.secondsPerFrame[_preset] ?? 2.0) + 30;

  bool get _canStart => _selectedFace != null && _selectedLib != null && !_starting && (_mode != 'vucut' || widget.health.body.available);

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      final job = await Api.I.createJob(
        videoId: v.id,
        frameNumber: _frame,
        faceIndex: _selectedFace!,
        faceIds: [_selectedLib!],
        preset: _preset,
        mode: _mode,
        trimStart: _trimStartFrame == 0 ? null : _trimStartFrame,
        trimEnd: _trimEndFrame >= v.frameCount ? null : _trimEndFrame,
      );
      if (!mounted) return;
      setState(() => _starting = false);
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProgressScreen(jobId: job.id)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      snack(context, Api.err(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final aspect = v.width > 0 && v.height > 0 ? v.width / v.height : 16 / 9;
    // Kare alanı: ekranın en fazla %42'si (dikey videolarda da sığsın)
    final maxFrameH = size.height * 0.42;
    double frameW = size.width - 32;
    double frameH = frameW / aspect;
    if (frameH > maxFrameH) {
      frameH = maxFrameH;
      frameW = frameH * aspect;
    }
    final faces = _faces?.faces ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Kişiyi seç'), actions: const [BalanceChip()]),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                children: [
                  // ---- Kare + yüz kutuları
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: frameW,
                        height: frameH,
                        child: GestureDetector(
                          onTapUp: (d) {
                            final nx = d.localPosition.dx / frameW;
                            final ny = d.localPosition.dy / frameH;
                            for (final f in faces) {
                              final b = f.bboxNorm;
                              if (nx >= b[0] - 0.02 && nx <= b[2] + 0.02 && ny >= b[1] - 0.02 && ny <= b[3] + 0.02) {
                                setState(() => _selectedFace = f.index);
                                return;
                              }
                            }
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(color: Colors.black),
                              Image.network(
                                Api.I.frameUrl(v.id, _frame),
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white38)),
                              ),
                              CustomPaint(painter: FaceOverlayPainter(faces: faces, selectedIndex: _selectedFace)),
                              if (_loadingFaces)
                                const Positioned(top: 8, right: 8, child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
                              if (!_loadingFaces && faces.isEmpty)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 8,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                      child: Text(_facesError ?? 'Bu karede yüz yok — çubuğu kaydır', style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // ---- Zaman çubuğu
                  Row(
                    children: [
                      Text(fmtClock(_sliderFrame / v.fps), style: const TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _sliderFrame.clamp(0.0, (v.frameCount - 1).toDouble()).toDouble(),
                          min: 0,
                          max: (v.frameCount - 1).toDouble(),
                          onChanged: _onSlider,
                        ),
                      ),
                      Text(fmtClock(v.duration), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  // ---- Karedeki kişiler
                  _SectionTitle('1. Kim değişsin?  (kutuya dokun)'),
                  SizedBox(
                    height: 72,
                    child: faces.isEmpty
                        ? Center(child: Text('Kişi bulunamadı', style: TextStyle(color: cs.onSurface.withOpacity(0.5))))
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: faces.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 10),
                            itemBuilder: (_, i) {
                              final f = faces[i];
                              final sel = f.index == _selectedFace;
                              return GestureDetector(
                                onTap: () => setState(() => _selectedFace = f.index),
                                child: Column(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: sel ? const Color(0xFF00E676) : Colors.transparent, width: 3),
                                      ),
                                      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: B64Image(f.thumbB64, size: 50)),
                                    ),
                                    Text('${f.index + 1}', style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  // ---- Kütüphane
                  _SectionTitle('2. Hangi yüz gelsin?'),
                  SizedBox(
                    height: 80,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _AddChip(icon: Icons.photo_library_outlined, label: 'Galeri', onTap: () => _addFace(ImageSource.gallery)),
                        const SizedBox(width: 8),
                        _AddChip(icon: Icons.photo_camera_outlined, label: 'Kamera', onTap: () => _addFace(ImageSource.camera)),
                        const SizedBox(width: 12),
                        for (final f in _library) ...[
                          GestureDetector(
                            onTap: () => setState(() => _selectedLib = f.id),
                            onLongPress: () => _deleteFace(f),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _selectedLib == f.id ? cs.primary : Colors.transparent, width: 3),
                              ),
                              child: ClipRRect(borderRadius: BorderRadius.circular(10), child: B64Image(f.thumbB64, size: 64)),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  // ---- Mod
                  _SectionTitle('3. Ne değişsin?'),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'yuz', label: Text('Sadece yüz'), icon: Icon(Icons.face_retouching_natural, size: 18)),
                      ButtonSegment(value: 'vucut', label: Text('Tüm vücut'), icon: Icon(Icons.accessibility_new, size: 18)),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _mode == 'vucut'
                          ? (widget.health.body.available
                              ? 'Yüz + saç + sakal + kıyafet + vücut değişir; hareket ve arka plan kalır. Boydan fotoğraf en iyi sonucu verir. '
                                  '${widget.health.body.ready ? 'Hazır.' : widget.health.body.status == 'installing' ? 'Sunucu şu an kuruyor: ${widget.health.body.stage} — iş kuyruğa girer, kurulum bitince başlar.' : 'İlk kullanımda sunucu ~15 dk kurulum yapar.'}'
                              : 'Bu sunucuda tüm vücut modu yok (RunPod H100/A100 gerekir).')
                          : 'Sadece yüz değişir; saç, kıyafet ve vücut aynı kalır. Hızlı.',
                      style: TextStyle(fontSize: 12, color: _mode == 'vucut' && !widget.health.body.available ? Colors.redAccent : cs.onSurface.withOpacity(0.7)),
                    ),
                  ),
                  // ---- Kalite
                  _SectionTitle('4. Kalite'),
                  SegmentedButton<String>(
                    segments: [
                      for (final k in const ['hizli', 'kaliteli', 'ultra']) ButtonSegment(value: k, label: Text(presetLabels[k]!)),
                    ],
                    selected: {_preset},
                    onSelectionChanged: (s) => setState(() => _preset = s.first),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${_mode == 'vucut' ? (bodyPresetHints[_preset] ?? '') : presetHints[_preset]}  Tahmini süre: ~${fmtSeconds(_estimateSeconds)}',
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                  ),
                  // ---- Aralık
                  _SectionTitle('5. Aralık  (${fmtClock(_range.start)} – ${fmtClock(_range.end)}, ${fmtSeconds(_range.end - _range.start)})'),
                  RangeSlider(
                    values: _range,
                    min: 0,
                    max: v.duration,
                    divisions: v.duration > 1 ? (v.duration * 2).round() : null,
                    onChanged: (r) {
                      if (r.end - r.start < 0.5) return;
                      setState(() => _range = r);
                    },
                  ),
                ],
              ),
            ),
            // ---- Sabit alt buton
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.icon(
                onPressed: _canStart ? _start : null,
                icon: _starting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_fix_high),
                label: Text(_selectedFace == null
                    ? 'Önce kişiye dokun'
                    : _selectedLib == null
                        ? 'Bir yüz ekle'
                        : 'Değiştir'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );
}

class _AddChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AddChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 64,
          height: 70,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon, size: 24), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 11))],
          ),
        ),
      );
}
