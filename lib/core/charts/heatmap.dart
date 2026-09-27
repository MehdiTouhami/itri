import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/type.dart';

/// Consistency calendar: weeks as columns, Mon–Sun as rows. One hue (gold)
/// stepped by load quartile; empty days sit on the raised tone.
class LoadHeatmap extends StatelessWidget {
  const LoadHeatmap({
    super.key,
    required this.end,
    required this.weeks,
    required this.loadOn,
    required this.selected,
    required this.onSelect,
  });

  final DateTime end; // today
  final int weeks;
  final double Function(DateTime day) loadOn;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    // Column 0 starts on the Monday `weeks-1` weeks before this week's Monday.
    final thisMonday = DateTime(end.year, end.month, end.day - (end.weekday - 1));
    final first = DateTime(thisMonday.year, thisMonday.month, thisMonday.day - 7 * (weeks - 1));
    final loads = <double>[];
    for (var i = 0; i < weeks * 7; i++) {
      final d = DateTime(first.year, first.month, first.day + i);
      if (!d.isAfter(end)) loads.add(loadOn(d));
    }
    final nonZero = loads.where((v) => v > 0).toList()..sort();
    double q(double p) => nonZero.isEmpty ? 1 : nonZero[((nonZero.length - 1) * p).round()];
    final cuts = [q(0.25), q(0.5), q(0.75)];

    return LayoutBuilder(builder: (context, box) {
      const labelW = 16.0, gap = 3.0, monthH = 16.0;
      final cell = math.min(((box.maxWidth - labelW) / weeks) - gap, 18.0);
      final pitch = cell + gap;

      DateTime dayAt(Offset p) {
        final col = ((p.dx - labelW) / pitch).floor().clamp(0, weeks - 1);
        final row = ((p.dy - monthH) / pitch).floor().clamp(0, 6);
        final d = DateTime(first.year, first.month, first.day + col * 7 + row);
        return d.isAfter(end) ? end : d;
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onSelect(dayAt(d.localPosition)),
        onPanUpdate: (d) => onSelect(dayAt(d.localPosition)),
        child: SizedBox(
          height: monthH + pitch * 7,
          width: double.infinity,
          child: CustomPaint(
            painter: _HeatPainter(
              first: first,
              end: end,
              weeks: weeks,
              cell: cell,
              pitch: pitch,
              labelW: labelW,
              monthH: monthH,
              loadOn: loadOn,
              cuts: cuts,
              selected: selected,
              t: t,
              label: Tx.data(t, size: 9, color: t.textFaint),
            ),
          ),
        ),
      );
    });
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter({
    required this.first,
    required this.end,
    required this.weeks,
    required this.cell,
    required this.pitch,
    required this.labelW,
    required this.monthH,
    required this.loadOn,
    required this.cuts,
    required this.selected,
    required this.t,
    required this.label,
  });

  final DateTime first, end;
  final int weeks;
  final double cell, pitch, labelW, monthH;
  final double Function(DateTime) loadOn;
  final List<double> cuts;
  final DateTime? selected;
  final ItriTokens t;
  final TextStyle label;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  Color _shade(double v) {
    if (v <= 0) return t.raised;
    final step = v <= cuts[0] ? 0 : v <= cuts[1] ? 1 : v <= cuts[2] ? 2 : 3;
    const alphas = [0.28, 0.5, 0.74, 1.0];
    return Color.alphaBlend(t.gold.withValues(alpha: alphas[step]), t.raised);
  }

  void _text(Canvas c, String s, Offset o) {
    final tp = TextPainter(text: TextSpan(text: s, style: label), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, o);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final (row, s) in const [(0, 'M'), (2, 'W'), (4, 'F')]) {
      _text(canvas, s, Offset(0, monthH + row * pitch + cell / 2 - 6));
    }
    var lastMonth = -1;
    for (var w = 0; w < weeks; w++) {
      final x = labelW + w * pitch;
      final monday = DateTime(first.year, first.month, first.day + w * 7);
      if (monday.month != lastMonth) {
        if (lastMonth != -1 || w == 0) _text(canvas, _months[monday.month - 1], Offset(x, 0));
        lastMonth = monday.month;
      }
      for (var r = 0; r < 7; r++) {
        final d = DateTime(first.year, first.month, first.day + w * 7 + r);
        if (d.isAfter(end)) continue;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, monthH + r * pitch, cell, cell),
          const Radius.circular(2.5),
        );
        canvas.drawRRect(rect, Paint()..color = _shade(loadOn(d)));
        final isToday = d.year == end.year && d.month == end.month && d.day == end.day;
        final isSel = selected != null && d.year == selected!.year && d.month == selected!.month && d.day == selected!.day;
        if (isToday || isSel) {
          canvas.drawRRect(
            rect.inflate(1.5),
            Paint()
              ..color = isSel ? t.text : t.textMuted
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HeatPainter old) => old.selected != selected || old.t != t || old.cuts != cuts;
}
