import 'dart:math';
import 'package:flutter/material.dart';

class PulseButton extends StatefulWidget {
  final bool isListening;
  final VoidCallback onTap;
  final Color activeColor;
  final Color inactiveColor;

  const PulseButton({
    super.key,
    required this.isListening,
    required this.onTap,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  State<PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<PulseButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _PulsePainter(
              progress: _controller.value,
              isListening: widget.isListening,
              activeColor: widget.activeColor,
              inactiveColor: widget.inactiveColor,
            ),
            size: const Size(80, 80),
          );
        },
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double progress;
  final bool isListening;
  final Color activeColor;
  final Color inactiveColor;

  _PulsePainter({
    required this.progress,
    required this.isListening,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2.5;

    if (isListening) {
      final pulsePaint = Paint()
        ..color = activeColor.withOpacity(1.0 - progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius + (progress * 15), pulsePaint);
    }

    final bodyPaint = Paint()
      ..color = isListening ? activeColor : inactiveColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bodyPaint);

    // Mic Icon (Simplified)
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    
    // Draw stylized 'U'
    canvas.drawArc(
      Rect.fromCenter(center: center, width: 20, height: 20),
      0, pi, false, iconPaint
    );
    canvas.drawLine(center + const Offset(-10, -5), center + const Offset(-10, 0), iconPaint);
    canvas.drawLine(center + const Offset(10, -5), center + const Offset(10, 0), iconPaint);
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) => true;
}
