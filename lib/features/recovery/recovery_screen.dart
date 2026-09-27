import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/live_sync.dart';
import '../../app/router.dart';
import '../../core/charts/week_bars.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/page_title.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/sleep.dart';
import '../../state/providers.dart';
import '../common/states.dart';
import 'recovery_widgets.dart';

/// Recovery home: this morning's verdict, then the night behind it.
class RecoveryScreen extends ConsumerStatefulWidget {
  const RecoveryScreen({super.key});

  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  int? _sel;

  static const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (ref.watch(recoveryProvider)) {
          AsyncData(:final value) => value.isEmpty ? const EmptyRecovery() : LiveRefresh(child: _body(value)),
          AsyncError(:final error) => ErrorState(error),
          _ => const LoadingState(),
        },
      ),
    );
  }

  Widget _body(RecoveryData rec) {
    final t = context.tk;
    final asOf = ref.watch(asOfProvider);
    final real = ref.watch(effectiveSourceProvider) == DataSource.garmin;
    final readiness = ref.watch(readinessProvider);
    final labels = sourceLabels(ref, asOf);
    final night = rec.nightFor(asOf);
    final week = rec.window(asOf, 7);
    final sel = _sel ?? week.length - 1;

    double avg(Iterable<num> v) => v.isEmpty ? 0 : v.fold<double>(0, (a, b) => a + b) / v.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.lg, Sp.gutter, Sp.xxxl),
      children: [
        PageTitle(
          eyebrow: labels.eyebrow,
          title: 'RECOVERY',
          tag: labels.tag,
          tagColor: real ? t.gold : null,
        ),
        const SizedBox(height: Sp.xl),
        if (readiness != null) ReadinessBlock(readiness),
        if (night != null) ...[
          SectionHeader('Last night', trailing: Fmt.dayMonth(night.evening)),
          NightSummary(night),
          const SizedBox(height: Sp.md),
          _Link('Night in detail', () => openNight(context, night.date)),
        ],
        if (week.length > 1) ...[
          SectionHeader(
            'Past 7 nights',
            trailing: 'avg ${avg(week.map((n) => n.score)).round()} · ${hm(avg(week.map((n) => n.asleepS)).round())}',
          ),
          WeekBars(
            values: [for (final n in week) n.asleepS / 3600],
            labels: [for (final n in week) _wd[n.evening.weekday - 1]],
            selected: sel.clamp(0, week.length - 1),
            onSelect: (i) => setState(() => _sel = i),
            height: 110,
          ),
          const SizedBox(height: Sp.sm),
          Builder(builder: (context) {
            final n = week[sel.clamp(0, week.length - 1)];
            return Pressable(
              onTap: () => openNight(context, n.date),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${Fmt.dayMonth(n.evening)} · ${hm(n.asleepS)} asleep · score ${n.score}',
                      style: Tx.small(t, color: t.text),
                    ),
                  ),
                  Text('OPEN  →', style: Tx.eyebrow(t, color: t.gold)),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: Sp.lg),
        _Link('All nights', () => context.go('/nights')),
        _Link('Trends and patterns', () => context.go('/trends')),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.sm),
          child: Text('${label.toUpperCase()}  →', style: Tx.eyebrow(context.tk, color: context.tk.gold)),
        ),
      ),
    );
  }
}
