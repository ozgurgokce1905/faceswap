import 'package:flutter/material.dart';

import '../models.dart';

/// Kare görüntüsünün üstüne yüz kutularını çizer; seçili olan vurgulanır.
class FaceOverlayPainter extends CustomPainter {
  final List<DetectedFace> faces;
  final int? selectedIndex;
  FaceOverlayPainter({required this.faces, required this.selectedIndex});

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in faces) {
      final r = Rect.fromLTRB(f.bboxNorm[0] * size.width, f.bboxNorm[1] * size.height, f.bboxNorm[2] * size.width, f.bboxNorm[3] * size.height);
      final selected = f.index == selectedIndex;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 4 : 2.5
        ..color = selected ? const Color(0xFF00E676) : Colors.white.withOpacity(0.9);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(10));
      if (selected) {
        canvas.drawRRect(rr, Paint()..color = const Color(0xFF00E676).withOpacity(0.12));
      }
      canvas.drawRRect(rr, paint);
      // numara etiketi
      final tp = TextPainter(
        text: TextSpan(text: '${f.index + 1}', style: TextStyle(color: selected ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      final badge = Rect.fromLTWH(r.left, r.top - 22, tp.width + 14, 20);
      canvas.drawRRect(RRect.fromRectAndRadius(badge, const Radius.circular(6)), Paint()..color = selected ? const Color(0xFF00E676) : Colors.black54);
      tp.paint(canvas, Offset(badge.left + 7, badge.top + 3));
    }
  }

  @override
  bool shouldRepaint(covariant FaceOverlayPainter old) => old.faces != faces || old.selectedIndex != selectedIndex;
}
