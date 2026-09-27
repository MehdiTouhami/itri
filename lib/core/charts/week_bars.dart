import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/type.dart';

/// Weekly totals. The current (last) week is the only coloured bar; tapping
/// another bar selects it and the caller shows its value.
class WeekBars extends StatelessWidget {
  const WeekBars({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.height = 132,
  });

  final List<double> values;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return LayoutBuilder(builder: (context, box) {
      int indexAt(double dx) => (dx / box.maxWidth * values.length).floor().clamp(0, values.length - 1);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onSelect(indexAt(d.localPosition.dx)),
        onHorizontalDragUpdate: (d) => onSelect(indexAt(d.localPosition.dx)),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _BarsPainter(
              values: values,
              labels: labels,
              selected: selected,
              t: t,
              label: Tx.data(t, size: 9.5, color: t.textFaint),
            ),
          ),
        ),
      );
    });
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.labels,
    required this.selected,
    required this.t,
    required this.label,
  });

  final List<double> values;
  final List<String> labels;
  final int selected;
  final ItriTokens t;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const labelH = 18.0;
    final plotH = size.height - labelH;
    final maxV = math.max(values.reduce(math.max), 1.0);
    final slot = size.width / values.length;
    final barW = math.min(slot - 6, 22.0);

    // Average line: context without a y-axis.
    final avg = values.reduce((a, b) => a + b) / values.length;
    final ay = plotH - avg / maxV * (plotH - 6);
    final dash = Paint()
      ..color = t.textFaint
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, ay), Offset(math.min(x + 3, size.width), ay), dash);
    }

    for (var i = 0; i < values.length; i++) {
      final h = values[i] / maxV * (plotH - 6);
      final cx = slot * i + slot / 2;
      final isLast = i == values.length - 1;
      final isSel = i == selected;
      final color = isLast ? t.gold : (isSel ? t.textMuted : t.raised);
      if (h > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(cx - barW / 2, plotH - h, barW, h),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()..color = color,
        );
      }
      if (isSel) {
        canvas.drawLine(
          Offset(cx - barW / 2, plotH + 2),
          Offset(cx + barW / 2, plotH + 2),
          Paint()
            ..color = t.text
            ..strokeWidth = 1.5,
        );
      }
      // Label every other week to avoid crowding, always the last.
      if (i % 2 == (values.length - 1) % 2) {
        final tp = TextPainter(
          text: TextSpan(text: labels[i], style: isSel ? label.copyWith(color: t.text) : label),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, plotH + 5));
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.selected != selected || old.values != values || old.t != t;
}
