import 'package:material_ui/material_ui.dart';

class XiaomiFitnessLogo extends StatelessWidget {
  const XiaomiFitnessLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final color =
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox.square(
      dimension: 24,
      child: CustomPaint(painter: _XiaomiFitnessLogoPainter(color: color)),
    );
  }
}

class _XiaomiFitnessLogoPainter extends CustomPainter {
  const _XiaomiFitnessLogoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - ring.strokeWidth) / 2;
    canvas.drawCircle(center, radius, ring);
  }

  @override
  bool shouldRepaint(covariant _XiaomiFitnessLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
