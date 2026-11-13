import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// base64 JPEG -> widget (sunucudan gelen küçük resimler)
class B64Image extends StatelessWidget {
  final String b64;
  final double size;
  final BoxFit fit;
  const B64Image(this.b64, {super.key, this.size = 56, this.fit = BoxFit.cover});

  static final Map<String, Uint8List> _cache = {};

  @override
  Widget build(BuildContext context) {
    if (b64.isEmpty) {
      return Container(width: size, height: size, color: Colors.white10, child: const Icon(Icons.person, color: Colors.white38));
    }
    final bytes = _cache.putIfAbsent(b64.length > 64 ? b64.substring(0, 64) + b64.length.toString() : b64, () => base64Decode(b64));
    return Image.memory(bytes, width: size, height: size, fit: fit, gaplessPlayback: true);
  }
}

String fmtSeconds(num s) {
  final t = s.round();
  if (t < 60) return '$t sn';
  final m = t ~/ 60;
  final r = t % 60;
  if (m < 60) return r == 0 ? '$m dk' : '$m dk $r sn';
  return '${m ~/ 60} sa ${m % 60} dk';
}

String fmtClock(double seconds) {
  final t = seconds.floor();
  final m = (t ~/ 60).toString().padLeft(2, '0');
  final s = (t % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

void snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Colors.red.shade700 : null,
    behavior: SnackBarBehavior.floating,
  ));
}

const presetLabels = {'hizli': 'Hızlı', 'kaliteli': 'Kaliteli', 'ultra': 'Ultra'};
const bodyPresetHints = {
  'hizli': '480p, 12 adım. Deneme için.',
  'kaliteli': '720p, 20 adım. Önerilen.',
  'ultra': '720p, 30 adım. En iyi, en yavaş.',
};
const presetHints = {
  'hizli': 'Önizleme için. Sadece yüz değişir.',
  'kaliteli': 'Yüz değişir + netleştirme.',
  'ultra': 'En gerçekçi: mimikler korunur + netleştirme. En yavaş.',
};
