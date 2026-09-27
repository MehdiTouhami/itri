import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/page_title.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/sport_stats.dart';
import '../../state/providers.dart';
import '../common/states.dart';
import 'widgets.dart';

/// Every sport side by side: where the time goes, what each hour is worth,
/// and how the stop-start sports compare.
class SportsScreen extends ConsumerWidget {
  const SportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (ref.watch(sportSummariesProvider)) {
          AsyncData(:final value) => _body(context, value),
          AsyncError(:final error) => ErrorState(error),
          _ => const LoadingState(),
        },
      ),
    );
  }

  Widget _body(BuildContext context, List<SportSummary> all) {
    final t = context.tk;
    if (all.isEmpty) {
      return Center(child: Text('No sessions yet', style: Tx.body(t, color: t.textMuted)));
    }
    final totalS = all.fold(0, (s, x) => s + x.seconds);
    final sessions = all.fold(0, (s, x) => s + x.count);
    final top = all.first;
    final first = all.map((s) => s.first).reduce((a, b) => a.isBefore(b) ? a : b);
    final byRate = [...all.where((s) => s.count >= 3)]..sort((a, b) => b.loadPerHour.compareTo(a.loadPerHour));
    final maxRate = byRate.isEmpty ? 1.0 : byRate.first.loadPerHour;
    final stopStart = all.where((s) => s.sport.stopStart && s.recovery != null).toList();
    final share = (top.seconds / totalS * 100).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.lg, Sp.gutter, Sp.xxxl),
      children: [
        PageTitle(eyebrow: '${all.length} sports · $sessions sessions', title: 'SPORTS'),
        const SizedBox(height: Sp.xl),

        // The headline is a sentence, not a number.
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '${top.sport.label} ', style: Tx.hero(t, size: 44, color: t.gold).copyWith(height: 1.05)),
            TextSpan(text: 'is $share% of your training time.', style: Tx.hero(t, size: 44).copyWith(height: 1.05)),
          ]),
        ),
        const SizedBox(height: Sp.sm),
        Text(
          '${(totalS / 3600).round()} hours across $sessions sessions since ${Fmt.monthYear(first)}.',
          style: Tx.body(t, color: t.textMuted),
        ),

        const SectionHeader('Where your time goes', trailing: 'hours · tap for detail'),
        for (final s in all)
          ShareRow(
            label: s.sport.label,
            value: '${s.hours.toStringAsFixed(s.hours < 10 ? 1 : 0)} h',
            fraction: s.seconds / top.seconds,
            highlight: s == top,
            onTap: () => openSport(context, s.sport),
          ),

        if (byRate.isNotEmpty) ...[
          const SectionHeader('Hardest per hour', trailing: 'load per hour'),
          for (final s in byRate)
            ShareRow(
              label: s.sport.label,
              value: s.loadPerHour.round().toString(),
              fraction: s.loadPerHour / maxRate,
              highlight: s == byRate.first,
              onTap: () => openSport(context, s.sport),
            ),
          const SizedBox(height: Sp.sm),
          Text(
            'Per hour puts a 45-minute squash match and a two-hour tennis session on the same scale. '
            '${byRate.first.sport.label} works you hardest; '
            '${byRate.last.sport.label} is the lightest hour.',
            style: Tx.small(t),
          ),
        ],

        if (stopStart.length > 1) ...[
          const SectionHeader('Stop-start sports', trailing: 'efforts / h · recovery'),
          for (final s in stopStart)
            Pressable(
              onTap: () => openSport(context, s.sport),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(s.sport.icon, size: 16, color: t.textMuted),
                    const SizedBox(width: Sp.md),
                    Expanded(child: Text(s.sport.label, style: Tx.body(t))),
                    SizedBox(
                      width: 72,
                      child: Text(s.effortsPerHour.toStringAsFixed(1),
                          textAlign: TextAlign.right, style: Tx.numeral(t, size: 22)),
                    ),
                    SizedBox(
                      width: 88,
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: s.recovery!.round().toString(), style: Tx.numeral(t, size: 22)),
                          TextSpan(text: ' bpm', style: Tx.data(t, size: 10.5, color: t.textMuted)),
                        ]),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Sp.sm),
          Text(
            'An effort is 10 s or more in zone 4 or above: a long rally, a sprint, a hard point. '
            'Recovery is how many beats your heart drops in the minute after one. Bigger usually means fitter.',
            style: Tx.small(t),
          ),
        ],
      ],
    );
  }
}
