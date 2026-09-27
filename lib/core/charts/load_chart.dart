import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/training_load.dart';
import '../theme/tokens.dart';
import '../theme/type.dart';

/// Fitness and fatigue as two lines on one scale, with daily form as a
/// diverging strip underneath. Month ticks along the bottom.
class LoadChart extends StatelessWidget {
  const LoadChart({super.key, required this.days, required this.cursor, this.height = 190});

  final List<DayLoad> days;
  final ValueNotifier<double?> cursor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _LoadPainter(days, cursor, t, Tx.data(t, size: 9.5, color: t.textFaint)),
        ),
      ),
    );
  }
}

class _LoadPainter extends CustomPainter {
  _LoadPainter(this.days, this.cursor, this.t, this.label) : super(repaint: cursor);

  final List<DayLoad> days;
  final ValueNotifier<double?> cursor;
  final ItriTokens t;
  final TextStyle label;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void paint(Canvas canvas, Size size) {
    if (days.length < 2) return;
    const axisH = 16.0, formH = 34.0, gap = 10.0;
    final lineBottom = size.height - axisH - formH - gap;
    final formTop = lineBottom + gap;
    final formMid = formTop + formH / 2;

    var hi = 0.0;
    var formMax = 1.0;
    for (final d in days) {
      hi = math.max(hi, math.max(d.fitness, d.fatigue));
      formMax = math.max(formMax, d.form.abs());
    }
    hi *= 1.1;
    double x(int i) => i / (days.length - 1) * size.width;
    double y(double v) => lineBottom - v / hi * (lineBottom - 6);

    // Gridlines with their values.
    final grid = Paint()
      ..color = t.line
      ..strokeWidth = 1;
    for (final f in const [0.33, 0.66]) {
      final v = hi * f;
      canvas.drawLine(Offset(0, y(v)), Offset(size.width, y(v)), grid);
      _text(canvas, v.round().toString(), Offset(0, y(v) - 12));
    }
    canvas.drawLine(Offset(0, formMid), Offset(size.width, formMid), grid);

    // Form strip: one thin bar per day, colour by polarity.
    final barW = math.max(1.0, size.width / days.length - 1);
    for (var i = 0; i < days.length; i++) {
      final f = days[i].form / formMax * (formH / 2);
      final r = Rect.fromLTRB(x(i) - barW / 2, math.min(formMid, formMid - f), x(i) + barW / 2, math.max(formMid, formMid - f));
      canvas.drawRect(r, Paint()..color = (f >= 0 ? t.up : t.down).withValues(alpha: 0.85));
    }

    Path series(double Function(DayLoad) v) {
      final p = Path()..moveTo(0, y(v(days.first)));
      for (var i = 1; i < days.length; i++) {
        p.lineTo(x(i), y(v(days[i])));
      }
      return p;
    }

    final fatigue = series((d) => d.fatigue);
    final fitness = series((d) => d.fitness);
    final fill = Path.from(fitness)
      ..lineTo(size.width, lineBottom)
      ..lineTo(0, lineBottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [t.gold.withValues(alpha: 0.16), t.gold.withValues(alpha: 0)],
        ).createShader(Rect.fromLTRB(0, 0, size.width, lineBottom)),
    );
    canvas.drawPath(
      fatigue,
      Paint()
        ..color = t.textMuted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawPath(
      fitness,
      Paint()
        ..color = t.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Month ticks.
    for (var i = 0; i < days.length; i++) {
      if (days[i].day.day == 1) {
        canvas.drawLine(Offset(x(i), size.height - axisH), Offset(x(i), size.height - axisH + 4), grid);
        _text(canvas, _months[days[i].day.month - 1], Offset(x(i) + 3, size.height - axisH + 2));
      }
    }

    // Cursor, or the latest day when idle.
    final c = cursor.value;
    final idx = c == null ? days.length - 1 : (c * (days.length - 1)).round().clamp(0, days.length - 1);
    final cx = x(idx);
    if (c != null) {
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, formTop + formH),
        Paint()
          ..color = t.text.withValues(alpha: 0.45)
          ..strokeWidth = 1,
      );
    }
    final p = Offset(cx, y(days[idx].fitness));
    canvas.drawCircle(p, 6, Paint()..color = t.ground);
    canvas.drawCircle(p, 4, Paint()..color = t.gold);
    final q = Offset(cx, y(days[idx].fatigue));
    canvas.drawCircle(q, 5, Paint()..color = t.ground);
    canvas.drawCircle(q, 3, Paint()..color = t.textMuted);
  }

  void _text(Canvas canvas, String s, Offset at) {
    final tp = TextPainter(text: TextSpan(text: s, style: label), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_LoadPainter old) => old.days != days || old.t != t;
}
