import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/sample.dart';
import '../theme/tokens.dart';
import '../theme/type.dart';

/// The route drawn on survey-paper, coloured by HR zone. No map tiles: the
/// shape of the effort is the point. A scale bar keeps it honest.
class RouteTrace extends StatelessWidget {
  const RouteTrace({
    super.key,
    required this.points,
    required this.zoneOf,
    required this.cursor,
    this.height = 260,
  });

  /// Downsampled samples with lat/lon.
  final List<Sample> points;
  final int Function(int hr) zoneOf;
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
          painter: _RoutePainter(
            points: points.where((p) => p.lat != null && p.lon != null).toList(),
            zoneOf: zoneOf,
            cursor: cursor,
            tokens: t,
            label: Tx.data(t, size: 9.5, color: t.textMuted),
          ),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.points,
    required this.zoneOf,
    required this.cursor,
    required this.tokens,
    required this.label,
  }) : super(repaint: cursor);

  final List<Sample> points;
  final int Function(int) zoneOf;
  final ValueNotifier<double?> cursor;
  final ItriTokens tokens;
  final TextStyle label;

  static const _mPerDeg = 111320.0;

  @override
  void paint(Canvas canvas, Size size) {
    _paper(canvas, size);
    if (points.length < 2) return;

    // Project to local metres, then fit with equal aspect.
    final lat0 = points.first.lat!;
    final k = math.cos(lat0 * math.pi / 180);
    final xs = [for (final p in points) (p.lon! - points.first.lon!) * _mPerDeg * k];
    final ys = [for (final p in points) (p.lat! - lat0) * _mPerDeg];
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    const pad = 28.0;
    final spanX = math.max(maxX - minX, 1.0), spanY = math.max(maxY - minY, 1.0);
    final scale = math.min((size.width - 2 * pad) / spanX, (size.height - 2 * pad) / spanY);
    final offX = (size.width - spanX * scale) / 2, offY = (size.height - spanY * scale) / 2;
    Offset at(int i) => Offset(offX + (xs[i] - minX) * scale, size.height - (offY + (ys[i] - minY) * scale));

    // Ground-coloured underlay so crossings stay legible.
    final all = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      all.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      all,
      Paint()
        ..color = tokens.ground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Runs of the same zone share one stroke.
    var i = 0;
    while (i < points.length - 1) {
      final z = zoneOf(points[i].heartRate ?? 0);
      final run = Path()..moveTo(at(i).dx, at(i).dy);
      var j = i + 1;
      while (j < points.length) {
        run.lineTo(at(j).dx, at(j).dy);
        if (zoneOf(points[j].heartRate ?? 0) != z) break;
        j++;
      }
      canvas.drawPath(
        run,
        Paint()
          ..color = tokens.zones[z]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      i = j;
    }

    // Start: hollow ring. Finish: solid dot.
    final s = at(0), f = at(points.length - 1);
    canvas.drawCircle(s, 6, Paint()..color = tokens.ground);
    canvas.drawCircle(
      s,
      4.5,
      Paint()
        ..color = tokens.text
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(f, 3, Paint()..color = tokens.text);

    final c = cursor.value;
    if (c != null) {
      final p = at((c * (points.length - 1)).round().clamp(0, points.length - 1));
      canvas.drawCircle(p, 9, Paint()..color = tokens.gold.withValues(alpha: 0.25));
      canvas.drawCircle(p, 5, Paint()..color = tokens.ground);
      canvas.drawCircle(p, 3.5, Paint()..color = tokens.gold);
    }

    _scaleBar(canvas, size, scale);
  }

  /// Faint dot grid, like survey paper.
  void _paper(Canvas canvas, Size size) {
    final dot = Paint()..color = tokens.line;
    const step = 18.0;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }
  }

  void _scaleBar(Canvas canvas, Size size, double pxPerM) {
    const nice = [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];
    final target = size.width * 0.22;
    var metres = nice.first;
    for (final n in nice) {
      if (n * pxPerM <= target) metres = n;
    }
    final w = metres * pxPerM;
    final y = size.height - 12;
    const x = 12.0;
    final p = Paint()
      ..color = tokens.textMuted
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x, y), Offset(x + w, y), p);
    canvas.drawLine(Offset(x, y - 4), Offset(x, y), p);
    canvas.drawLine(Offset(x + w, y - 4), Offset(x + w, y), p);
    final tp = TextPainter(
      text: TextSpan(text: metres >= 1000 ? '${metres ~/ 1000} km' : '$metres m', style: label),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x + w + 6, y - tp.height + 2));
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.points.length != points.length || old.tokens != tokens;
}
