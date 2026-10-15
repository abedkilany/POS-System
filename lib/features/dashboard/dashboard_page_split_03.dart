part of 'dashboard_page.dart';

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({
    required this.items,
    required this.color,
    required this.gridColor,
  });

  final List<DashboardChartItem> items;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty || size.width <= 0 || size.height <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final values = items.map((item) => item.value).toList();
    final maxValue =
        values.fold<double>(values.first, (a, b) => math.max(a, b).toDouble());
    final minValue = values.reduce(math.min);
    final span = math.max(1.0, maxValue - minValue).toDouble();
    final dx = items.length <= 1 ? size.width : size.width / (items.length - 1);
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final normalized = (values[i] - minValue) / span;
      final y =
          size.height - (normalized * size.height * 0.72) - size.height * 0.14;
      points.add(Offset(dx * i, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final controlX = (previous.dx + current.dx) / 2;
      path.cubicTo(
          controlX, previous.dy, controlX, current.dy, current.dx, current.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.20),
          color.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = color;
    final dotBorder = Paint()..color = Colors.white;
    for (final point in points) {
      canvas.drawCircle(point, 5.5, dotBorder);
      canvas.drawCircle(point, 3.4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.items != items ||
        oldDelegate.color != color ||
        oldDelegate.gridColor != gridColor;
  }
}

List<BoxShadow> _softShadow(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.055),
      blurRadius: 30,
      offset: const Offset(0, 14),
    ),
  ];
}
