import 'dart:math';
import 'package:flutter/material.dart';

class SpherePainter extends CustomPainter {
  final double phase;
  final Color accentColor;

  SpherePainter({required this.phase, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.4;

    // Outer glow
    final glowPaint = Paint()
      ..color = accentColor.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    final glowR = radius + 2 + 3 * sin(phase * 2);
    canvas.drawCircle(center, glowR, glowPaint);

    // Main sphere body
    final spherePaint = Paint()
      ..color = const Color(0xFF0D0D1A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, spherePaint);

    final borderPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);

    // Longitudes
    final linePaint = Paint()
      ..color = accentColor.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < 2; i++) {
      double angle = phase + (i * pi / 2);
      double w = radius * cos(angle);
      if (w.abs() > 1) {
        canvas.drawOval(
          Rect.fromCenter(center: center, width: w * 2, height: radius * 2),
          linePaint,
        );
      }
    }

    // Latitudes
    for (int i = -2; i <= 2; i++) {
      double h = i * radius / 3;
      double w = sqrt(max(0, radius * radius - h * h));
      double y = center.dy + h;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(center.dx, y), width: w * 2, height: w * 0.4),
        linePaint,
      );
    }

    // Highlight
    final highlightPaint = Paint()..color = Colors.white;
    final hx = center.dx - radius * 0.4;
    final hy = center.dy - radius * 0.4;
    canvas.drawCircle(Offset(hx, hy), radius * 0.2, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant SpherePainter oldDelegate) => 
    oldDelegate.phase != phase || oldDelegate.accentColor != accentColor;
}
