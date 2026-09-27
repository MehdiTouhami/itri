import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../domain/analysis.dart';
import '../../domain/athlete.dart';

/// Per-unit splits. Bar length encodes speed (longer = faster); the fastest
/// full split is the only gold one.
class SplitsTable extends StatelessWidget {
  const SplitsTable({super.key, required this.splits, required this.units, required this.usesPace, this.every = 1});
  final List<KmSplit> splits;

  /// Split length in display units (1 km, or 5 km for rides).
  final int every;
  final Units units;
  final bool usesPace;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    if (splits.isEmpty) return const SizedBox.shrink();
    final unit = Fmt.unitM(units);
    final paces = [for (final s in splits) s.pacePerUnit(unit)];
    final full = [for (var i = 0; i < splits.length; i++) if (splits[i].distanceM >= unit * every * 0.99) i];
    final fastest = full.isEmpty ? -1 : full.reduce((a, b) => paces[a] <= paces[b] ? a : b);
    final slow = paces.reduce(math.max), fast = paces.reduce(math.min);

    final head = Tx.eyebrow(t, color: t.textFaint);
    return Column(
      children: [
        Row(children: [
          SizedBox(width: 34, child: Text(Fmt.distUnit(units).toUpperCase(), style: head)),
          SizedBox(width: 52, child: Text(usesPace ? 'PACE' : Fmt.speedUnit(units).toUpperCase(), style: head)),
          const Expanded(child: SizedBox()),
          SizedBox(width: 40, child: Text('HR', textAlign: TextAlign.right, style: head)),
          SizedBox(width: 44, child: Text('ELEV', textAlign: TextAlign.right, style: head)),
        ]),
        const SizedBox(height: 6),
        for (var i = 0; i < splits.length; i++)
          _row(t, splits[i], paces[i], i == fastest, slow, fast, unit),
      ],
    );
  }

  Widget _row(ItriTokens t, KmSplit s, double pace, bool best, double slow, double fast, double unit) {
    final partial = s.distanceM < unit * every * 0.99;
    // Map pace to 35–100 % bar width, faster = longer.
    final span = slow - fast;
    final f = span < 1e-6 ? 1.0 : 0.35 + 0.65 * (slow - pace) / span;
    final label = usesPace ? Fmt.paceFromSeconds(pace) : (3600 / pace).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              partial ? (s.index * every + s.distanceM / unit).toStringAsFixed(1) : '${(s.index + 1) * every}',
              style: Tx.data(t, size: 12, color: t.textMuted),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(label, style: Tx.data(t, size: 12.5, weight: FontWeight.w500, color: best ? t.gold : t.text)),
          ),
          Expanded(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: f.clamp(0.05, 1.0),
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: best ? t.gold : t.raised,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text('${s.avgHr}', textAlign: TextAlign.right, style: Tx.data(t, size: 12, color: t.textMuted)),
          ),
          SizedBox(
            width: 44,
            child: Text(
              Fmt.signed(units == Units.metric ? s.elevDeltaM : s.elevDeltaM * 3.28084),
              textAlign: TextAlign.right,
              style: Tx.data(t, size: 12, color: t.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
