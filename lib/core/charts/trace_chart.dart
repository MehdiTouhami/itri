import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/type.dart';

/// Horizontal colour bands keyed on value, e.g. HR zones. [lowerBounds] are
/// the lower edge of each band after the first.
class ValueBands {
  const ValueBands(this.lowerBounds, this.colors);
  final List<double> lowerBounds;
  final List<Color> colors;

  Color colorFor(double v) {
    var i = 0;
    while (i < lowerBounds.length && v >= lowerBounds[i]) {
      i++;
    }
    return colors[i];
  }
}

/// One telemetry channel drawn against a shared 0–1 x axis. Values may be
/// null (paused / no signal). Several tracks share one scrub position.
class TraceChart extends StatelessWidget {
  const TraceChart({
    super.key,
    required this.values,
    required this.cursor,
    required this.color,
    this.bands,
    this.invert = false,
    this.height = 88,
    this.axisLabel,
    this.floor,
  });

  final List<double?> values;
  final ValueNotifier<double?> cursor;
  final Color color;
  final ValueBands? bands;

  /// Draw larger values lower (pace: faster sits higher).
  final bool invert;
  final double height;
  final String Function(double)? axisLabel;

  /// Force the axis to include this value (e.g. 0 for power).
  final double? floor;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _TracePainter(
            values: values,
            cursor: cursor,
            color: color,
            bands: bands,
            invert: invert,
            axisLabel: axisLabel,
            floor: floor,
            line: t.line,
            ground: t.ground,
            labelStyle: Tx.data(t, size: 9.5, color: t.textFaint),
            cursorColor: t.text,
          ),
        ),
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter({
    required this.values,
    required this.cursor,
    required this.color,
    required this.bands,
    required this.invert,
    required this.axisLabel,
    required this.floor,
    required this.line,
    required this.ground,
    required this.labelStyle,
    required this.cursorColor,
  }) : super(repaint: cursor);

  final List<double?> values;
  final ValueNotifier<double?> cursor;
  final Color color;
  final ValueBands? bands;
  final bool invert;
  final String Function(double)? axisLabel;
  final double? floor;
  final Color line, ground, cursorColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>();
    if (present.isEmpty || values.length < 2) return;
    var lo = present.reduce(math.min), hi = present.reduce(math.max);
    if (floor != null) lo = math.min(lo, floor!);
    if (hi - lo < 1e-6) hi = lo + 1;
    final pad = (hi - lo) * 0.12;
    lo -= floor != null && lo == floor ? 0 : pad;
    hi += pad;

    const top = 4.0;
    final bottom = size.height - 2;
    double y(double v) {
      final f = (v - lo) / (hi - lo);
      return invert ? top + f * (bottom - top) : bottom - f * (bottom - top);
    }

    double x(int i) => i / (values.length - 1) * size.width;

    // Grid: three recessive rules with labels sitting just above them.
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final f in const [0.2, 0.5, 0.8]) {
      final v = lo + (hi - lo) * f;
      final gy = y(v);
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
      if (axisLabel != null) {
        final tp = TextPainter(text: TextSpan(text: axisLabel!(v), style: labelStyle), textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(0, gy - tp.height - 1));
      }
    }

    // Build the line as runs of consecutive non-null points.
    final path = Path();
    final area = Path();
    var open = false;
    double? runStartX;
    double lastX = 0;
    final base = invert ? top : bottom;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        if (open) {
          area
            ..lineTo(lastX, base)
            ..lineTo(runStartX!, base)
            ..close();
        }
        open = false;
        continue;
      }
      final p = Offset(x(i), y(v));
      if (!open) {
        path.moveTo(p.dx, p.dy);
        area
          ..moveTo(p.dx, base)
          ..lineTo(p.dx, p.dy);
        runStartX = p.dx;
        open = true;
      } else {
        path.lineTo(p.dx, p.dy);
        area.lineTo(p.dx, p.dy);
      }
      lastX = p.dx;
    }
    if (open) {
      area
        ..lineTo(lastX, base)
        ..lineTo(runStartX!, base)
        ..close();
    }

    final rect = Offset.zero & size;
    final Shader stroke = bands == null ? _solid(rect) : _banded(rect, y);
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: invert ? Alignment.bottomCenter : Alignment.topCenter,
          end: invert ? Alignment.topCenter : Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.0)],
        ).createShader(rect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Cursor: hairline + ringed dot on the value.
    final c = cursor.value;
    if (c != null) {
      final i = (c * (values.length - 1)).round().clamp(0, values.length - 1);
      final cx = x(i);
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, size.height),
        Paint()
          ..color = cursorColor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      final v = values[i];
      if (v != null) {
        final dot = Offset(cx, y(v));
        final dotColor = bands?.colorFor(v) ?? color;
        canvas.drawCircle(dot, 6, Paint()..color = ground);
        canvas.drawCircle(dot, 4, Paint()..color = dotColor);
      }
    }
  }

  Shader _solid(Rect r) => LinearGradient(colors: [color, color]).createShader(r);

  /// Hard-stop vertical gradient so the line takes the colour of the band
  /// it is in at every height.
  Shader _banded(Rect r, double Function(double) y) {
    final b = bands!;
    final colors = <Color>[];
    final stops = <double>[];
    double stopFor(double v) => (y(v) / r.height).clamp(0.0, 1.0);
    // Walk bands from top of the canvas downward.
    final order = invert ? List<int>.generate(b.colors.length, (i) => i) : List<int>.generate(b.colors.length, (i) => b.colors.length - 1 - i);
    var prev = 0.0;
    for (final i in order) {
      // Canvas-space edge where this band ends (going down).
      double end;
      if (invert) {
        end = i < b.lowerBounds.length ? stopFor(b.lowerBounds[i]) : 1.0;
      } else {
        end = i > 0 ? stopFor(b.lowerBounds[i - 1]) : 1.0;
      }
      end = math.max(prev, end);
      colors
        ..add(b.colors[i])
        ..add(b.colors[i]);
      stops
        ..add(prev)
        ..add(end);
      prev = end;
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    ).createShader(r);
  }

  @override
  bool shouldRepaint(_TracePainter old) =>
      old.values != values || old.color != color || old.invert != invert || old.line != line;
}
