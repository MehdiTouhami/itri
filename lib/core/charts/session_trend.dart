import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../theme/tokens.dart';
import '../theme/type.dart';

/// One dot per session on a real time axis, with a gold rolling mean through
/// them. Gaps in the calendar stay visible as gaps. Tap or drag to select.
class SessionTrend extends StatelessWidget {
  const SessionTrend({
    super.key,
    required this.dates,
    required this.values,
    required this.smooth,
    required this.selected,
    required this.onSelect,
    this.axisLabel,
    this.height = 160,
  });

  final List<DateTime> dates;
  final List<double?> values;
  final List<double?> smooth;
  final int? selected;
  final ValueChanged<int> onSelect;
  final String Function(double)? axisLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return LayoutBuilder(builder: (context, box) {
      final geo = _Geometry(dates, box.maxWidth);
      void pick(Offset p) {
        final i = geo.nearest(p.dx, values);
        if (i != null) onSelect(i);
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => pick(d.localPosition),
        onHorizontalDragUpdate: (d) => pick(d.localPosition),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(
              geo: geo,
              values: values,
              smooth: smooth,
              selected: selected,
              axisLabel: axisLabel,
              t: t,
              label: Tx.data(t, size: 9.5, color: t.textFaint),
            ),
          ),
        ),
      );
    });
  }
}

/// Maps dates to x. Shared by painting and hit-testing so they always agree.
class _Geometry {
  _Geometry(this.dates, this.width);
  final List<DateTime> dates;
  final double width;
  static const inset = 6.0;

  double x(int i) {
    if (dates.length < 2) return width / 2;
    final t0 = dates.first.millisecondsSinceEpoch, t1 = dates.last.millisecondsSinceEpoch;
    final f = t1 == t0 ? 0.5 : (dates[i].millisecondsSinceEpoch - t0) / (t1 - t0);
    return inset + f * (width - 2 * inset);
  }

  int? nearest(double dx, List<double?> values) {
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < dates.length; i++) {
      if (values[i] == null) continue;
      final d = (x(i) - dx).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.geo,
    required this.values,
    required this.smooth,
    required this.selected,
    required this.axisLabel,
    required this.t,
    required this.label,
  });

  final _Geometry geo;
  final List<double?> values, smooth;
  final int? selected;
  final String Function(double)? axisLabel;
  final ItriTokens t;
  final TextStyle label;

  static final _month = DateFormat('MMM yy');

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>();
    if (present.isEmpty) return;
    var lo = present.reduce(math.min), hi = present.reduce(math.max);
    if (hi - lo < 1e-6) hi = lo + 1;
    final pad = (hi - lo) * 0.12;
    lo -= pad;
    hi += pad;

    const labelH = 18.0, top = 4.0;
    final bottom = size.height - labelH;
    double y(double v) => bottom - (v - lo) / (hi - lo) * (bottom - top);

    final grid = Paint()
      ..color = t.line
      ..strokeWidth = 1;
    for (final f in const [0.2, 0.5, 0.8]) {
      final v = lo + (hi - lo) * f;
      canvas.drawLine(Offset(0, y(v)), Offset(size.width, y(v)), grid);
      if (axisLabel != null) {
        final tp = TextPainter(text: TextSpan(text: axisLabel!(v), style: label), textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(0, y(v) - tp.height - 1));
      }
    }

    // Selection rule sits behind the marks.
    final sel = selected;
    if (sel != null && sel < values.length) {
      canvas.drawLine(
        Offset(geo.x(sel), top),
        Offset(geo.x(sel), bottom),
        Paint()
          ..color = t.text.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }

    final dot = Paint()..color = t.textMuted.withValues(alpha: 0.75);
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null || i == sel) continue;
      canvas.drawCircle(Offset(geo.x(i), y(v)), 2.4, dot);
    }

    final path = Path();
    var open = false;
    for (var i = 0; i < smooth.length; i++) {
      final v = smooth[i];
      if (v == null) continue;
      final p = Offset(geo.x(i), y(v));
      if (open) {
        path.lineTo(p.dx, p.dy);
      } else {
        path.moveTo(p.dx, p.dy);
        open = true;
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = t.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    if (sel != null && sel < values.length && values[sel] != null) {
      final p = Offset(geo.x(sel), y(values[sel]!));
      canvas.drawCircle(p, 6, Paint()..color = t.ground);
      canvas.drawCircle(p, 4, Paint()..color = t.text);
    }

    // First and last month under the axis ends.
    void month(DateTime d, {required bool right}) {
      final tp = TextPainter(text: TextSpan(text: _month.format(d), style: label), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(right ? size.width - tp.width : 0, bottom + 5));
    }

    month(geo.dates.first, right: false);
    if (geo.dates.length > 1) month(geo.dates.last, right: true);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.selected != selected || old.values != values || old.smooth != smooth || old.t != t;
}
