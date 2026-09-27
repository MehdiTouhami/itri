import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/analysis.dart';
import '../../state/providers.dart';

/// One session in a list: what, when, where, the headline number, and a
/// zone strip showing how hard it was at a glance.
class ActivityRow extends ConsumerWidget {
  const ActivityRow(this.x, {super.key});
  final ActivityAnalysis x;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tk;
    final a = x.activity;
    final units = ref.watch(athleteProvider.select((p) => p.units));
    final dist = a.sport.hasGps && a.distanceM > 0;
    final headline = dist
        ? (Fmt.distance(a.distanceM, units), Fmt.distUnit(units))
        : (Fmt.durationShort(a.durationS), '');
    final sub = dist ? Fmt.durationShort(a.durationS) : '${a.avgHr} bpm avg';

    return Pressable(
      onTap: () => openActivity(context, a.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(a.sport.icon, size: 18, color: t.textMuted),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name, style: Tx.heading(t), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [Fmt.dayMonth(a.start), Fmt.time(a.start), if (a.locality.isNotEmpty && !a.name.contains(a.locality)) a.locality].join(' · '),
                    style: Tx.small(t),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Sp.sm),
                  FractionallySizedBox(
                    widthFactor: 0.6,
                    alignment: Alignment.centerLeft,
                    child: ZoneStrip(x.zoneSeconds),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Sp.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: headline.$1, style: Tx.numeral(t, size: 22)),
                  if (headline.$2.isNotEmpty)
                    TextSpan(text: ' ${headline.$2}', style: Tx.data(t, size: 10.5, color: t.textMuted)),
                ])),
                const SizedBox(height: 2),
                Text(sub, style: Tx.data(t, size: 11, color: t.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
