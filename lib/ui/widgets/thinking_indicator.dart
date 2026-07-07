import 'package:flutter/material.dart';

class ThinkingIndicator extends StatefulWidget {
  final bool isThinking;

  const ThinkingIndicator({super.key, required this.isThinking});

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isThinking) _controller.repeat();
  }

  @override
  void didUpdateWidget(ThinkingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isThinking && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isThinking && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isThinking) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final value = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
            final size = 6.0 + 4.0 * (1.0 - (value * 2 - 1).abs());
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF2A5E).withOpacity(0.4 + 0.6 * value),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
