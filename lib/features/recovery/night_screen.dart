import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/page_title.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/analysis.dart';
import '../../domain/sleep.dart';
import '../../state/providers.dart';
import '../common/activity_row.dart';
import 'recovery_widgets.dart';

/// One night in full, with the training day that came before it.
class NightScreen extends ConsumerWidget {
  const NightScreen({super.key, required this.date});

  /// Morning of waking up.
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tk;
    final rec = switch (ref.watch(recoveryProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final night = rec?.byDate(date);
    final sessions = switch (ref.watch(analysesProvider)) {
      AsyncData(:final value) => value,
      _ => const <ActivityAnalysis>[],
    };
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: night == null
            ? Center(child: Text('Night not found', style: Tx.body(t, color: t.textMuted)))
            : _body(context, night, rec!, sessions),
      ),
    );
  }

  Widget _body(BuildContext context, SleepNight n, RecoveryData rec, List<ActivityAnalysis> all) {
    final t = context.tk;
    final dayBefore = all.where((x) => x.activity.day == n.evening).toList().reversed.toList();
    final load = dayBefore.fold<double>(0, (a, x) => a + x.load);
    final base = rec.restingBaseline(n.date);
    final status = n.hrvStatus;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.sm, Sp.gutter, Sp.xxxl),
      children: [
        const BackBar(icon: Icons.bedtime_outlined, fallback: '/nights'),
        const SizedBox(height: Sp.lg),
        Eyebrow('Night of ${Fmt.dayMonth(n.evening)}'),
        const SizedBox(height: Sp.sm),
        Text('NIGHT', style: Tx.pageTitle(t)),
        const SizedBox(height: Sp.xl),
        NightSummary(n),

        const SectionHeader('Score breakdown', trailing: 'Garmin sub-scores'),
        SubScores(n),

        const SectionHeader('Body overnight'),
        if (status != null)
          Text(
            'HRV ${n.hrv!.round()} ms: ${switch (status) {
              HrvStatus.below => 'below',
              HrvStatus.within => 'within',
              HrvStatus.above => 'above',
            }} your usual ${n.hrvLow!.round()}–${n.hrvHigh!.round()}. '
            'HRV is the small variation between heartbeats; higher than your usual generally means better recovered.',
            style: Tx.body(t),
          ),
        if (n.restingHr != null && base != null) ...[
          const SizedBox(height: Sp.sm),
          Text(
            'Resting heart rate ${n.restingHr} bpm against a 30-day average of ${base.round()}.',
            style: Tx.body(t),
          ),
        ],
        if (n.awakenings != null || n.restless != null) ...[
          const SizedBox(height: Sp.sm),
          Text(
            '${n.awakenings ?? 0} awakenings and ${n.restless ?? 0} restless moments.',
            style: Tx.body(t),
          ),
        ],

        SectionHeader('The day before', trailing: dayBefore.isEmpty ? 'rest day' : 'load ${load.round()}'),
        if (dayBefore.isEmpty)
          Text('No training logged. Nights after rest days are your baseline for comparison.', style: Tx.small(t))
        else
          for (final x in dayBefore) ActivityRow(x),
      ],
    );
  }
}
