import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../domain/hr_zones.dart';

/// Z5 on top, down to Z1: label, name, bpm range, bar, time, share.
class ZoneBreakdown extends StatelessWidget {
  const ZoneBreakdown({super.key, required this.zones, required this.seconds});
  final HrZoneModel zones;
  final List<int> seconds;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final total = seconds.fold<int>(0, (a, b) => a + b);
    final most = seconds.fold<int>(1, (a, b) => b > a ? b : a);
    return Column(
      children: [
        for (final z in zones.zones.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(z.label, style: Tx.data(t, size: 12, weight: FontWeight.w500, color: t.zones[z.index])),
                ),
                SizedBox(
                  width: 92,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(z.name, style: Tx.small(t, color: t.text)),
                      Text('${z.range} bpm', style: Tx.data(t, size: 10, color: t.textFaint)),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        height: 8,
                        width: box.maxWidth * seconds[z.index] / most,
                        decoration: BoxDecoration(
                          color: t.zones[z.index],
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Sp.md),
                SizedBox(
                  width: 48,
                  child: Text(Fmt.duration(seconds[z.index]), textAlign: TextAlign.right, style: Tx.data(t, size: 12)),
                ),
                SizedBox(
                  width: 38,
                  child: Text(
                    total == 0 ? '—' : '${(seconds[z.index] * 100 / total).round()}%',
                    textAlign: TextAlign.right,
                    style: Tx.data(t, size: 11, color: t.textMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
