import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../core/charts/session_trend.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/page_title.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/analysis.dart';
import '../../domain/sleep.dart';
import '../../domain/sleep_stats.dart';
import '../../domain/sport_stats.dart';
import '../../state/providers.dart';
import '../common/states.dart';
import '../sports/widgets.dart';
import 'recovery_widgets.dart';

/// Nights over time, and how training shows up in them.
class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  NightMetric _metric = NightMetric.score;
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (ref.watch(recoveryProvider)) {
          AsyncData(:final value) => value.isEmpty ? const EmptyRecovery() : _body(value),
          AsyncError(:final error) => ErrorState(error),
          _ => const LoadingState(),
        },
      ),
    );
  }

  Widget _body(RecoveryData rec) {
    final t = context.tk;
    final asOf = ref.watch(asOfProvider);
    final sessions = switch (ref.watch(analysesProvider)) {
      AsyncData(:final value) => value,
      _ => const <ActivityAnalysis>[],
    };
    final nights = rec.nights;
    final values = [for (final n in nights) _metric.of(n)];
    final smooth = rollingMean(values, 7);
    final sel = _selected != null && _selected! < nights.length ? _selected : null;
    final recent = rec.window(asOf, 28);
    final before = rec.window(DateTime(asOf.year, asOf.month, asOf.day - 28), 28);
    final after = sleepAfterTraining(rec, sessions);
    final bed = bedtimeStats(recent);
    final byDay = asleepByWeekday(recent.length >= 14 ? recent : nights);
    final hrvCounts = {for (final s in HrvStatus.values) s: recent.where((n) => n.hrvStatus == s).length};
    final hrvTotal = hrvCounts.values.fold<int>(0, (a, b) => a + b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.lg, Sp.gutter, Sp.xxxl),
      children: [
        PageTitle(eyebrow: '${nights.length} nights · since ${Fmt.monthYear(nights.first.evening)}', title: 'TRENDS'),
        const SizedBox(height: Sp.md),
        Text(_headline(recent, before), style: Tx.title(t)),

        const SectionHeader('Over time', trailing: 'tap a night'),
        ChipRow<NightMetric>(
          options: NightMetric.values,
          value: _metric,
          label: (m) => m.label,
          onChanged: (m) => setState(() {
            _metric = m;
            _selected = null;
          }),
        ),
        const SizedBox(height: Sp.md),
        _Selected(n: sel == null ? null : nights[sel], metric: _metric),
        const SizedBox(height: Sp.sm),
        SessionTrend(
          dates: [for (final n in nights) n.date],
          values: values,
          smooth: smooth,
          selected: sel,
          onSelect: (i) => setState(() => _selected = i),
          axisLabel: _metric.format,
        ),
        const SizedBox(height: Sp.sm),
        Text('${_metric.explainer} Line: 7-night average.', style: Tx.small(t, color: t.textFaint)),

        if (after.isNotEmpty) ...[
          const SectionHeader('Training and sleep', trailing: 'the night after'),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              for (final h in const ['NIGHTS', 'SCORE', 'ASLEEP', 'HRV'])
                SizedBox(width: 52, child: Text(h, textAlign: TextAlign.right, style: Tx.eyebrow(t))),
            ],
          ),
          const SizedBox(height: Sp.sm),
          for (final g in after)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(child: Text(g.label, style: Tx.body(t))),
                  _Cell('${g.nights}', faint: true),
                  _Cell(g.score.toStringAsFixed(1), bold: true),
                  _Cell(NightMetric.asleep.format(g.asleepH)),
                  _Cell(g.hrv?.round().toString() ?? '—'),
                ],
              ),
            ),
          const SizedBox(height: Sp.sm),
          Text(
            'Patterns in your own nights, not proof of cause: other things change on training days too. '
            'A hard day is your top third of training days by load.',
            style: Tx.small(t, color: t.textFaint),
          ),
        ],

        if (bed != null) ...[
          const SectionHeader('Bedtime', trailing: 'last 4 weeks'),
          Text(
            'You usually fall asleep around ${clockFromEvening(bed.mean)}, give or take '
            '${NightMetric.asleep.format(bed.spread / 60)}.',
            style: Tx.body(t),
          ),
          const SizedBox(height: Sp.lg),
          WeekdayBars(byDay, format: (v) => v == 0 ? '–' : v.toStringAsFixed(1)),
          const SizedBox(height: Sp.sm),
          Text('Average hours asleep, by the evening you went to bed.', style: Tx.small(t, color: t.textFaint)),
        ],

        if (hrvTotal >= 5) ...[
          const SectionHeader('HRV against your usual', trailing: 'last 4 weeks'),
          ShareRow(
            label: 'Above',
            value: '${hrvCounts[HrvStatus.above]}',
            fraction: hrvCounts[HrvStatus.above]! / hrvTotal,
          ),
          ShareRow(
            label: 'Within',
            value: '${hrvCounts[HrvStatus.within]}',
            fraction: hrvCounts[HrvStatus.within]! / hrvTotal,
            highlight: true,
          ),
          ShareRow(
            label: 'Below',
            value: '${hrvCounts[HrvStatus.below]}',
            fraction: hrvCounts[HrvStatus.below]! / hrvTotal,
          ),
          const SizedBox(height: Sp.sm),
          Text(
            'Your usual range is Garmin\'s rolling baseline for you. A run of nights below it is the '
            'clearest sign to ease off.',
            style: Tx.small(t, color: t.textFaint),
          ),
        ],
      ],
    );
  }

  String _headline(List<SleepNight> recent, List<SleepNight> before) {
    if (recent.length < 7) return 'Keep wearing the watch to bed: trends appear after a week.';
    double mean(List<SleepNight> ns) => ns.fold<int>(0, (a, n) => a + n.score) / ns.length;
    final now = mean(recent);
    if (before.length < 7) return 'Sleep score averaging ${now.round()} over the last four weeks.';
    final d = now - mean(before);
    if (d.abs() < 1.5) return 'Sleep score steady at about ${now.round()} over the last four weeks.';
    return 'Sleep score averaging ${now.round()} over the last four weeks, '
        '${d > 0 ? 'up' : 'down'} ${d.abs().round()} on the four before.';
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.bold = false, this.faint = false});
  final String text;
  final bool bold, faint;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return SizedBox(
      width: 52,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: Tx.data(t, color: faint ? t.textFaint : t.text, weight: bold ? FontWeight.w600 : null),
      ),
    );
  }
}

class _Selected extends StatelessWidget {
  const _Selected({required this.n, required this.metric});
  final SleepNight? n;
  final NightMetric metric;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final x = n;
    if (x == null) {
      return Text('${metric.label}${metric.unit.isEmpty ? '' : ' · ${metric.unit}'}', style: Tx.data(t, color: t.textFaint));
    }
    final v = metric.of(x);
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: v == null ? '—' : metric.format(v), style: Tx.numeral(t, size: 22)),
              TextSpan(
                text: '${metric.unit.isEmpty || metric == NightMetric.asleep ? '' : ' ${metric.unit}'}  ·  ${Fmt.dayMonth(x.evening)}',
                style: Tx.data(t, size: 11, color: t.textMuted),
              ),
            ]),
          ),
        ),
        Pressable(
          onTap: () => openNight(context, x.date),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.xs),
            child: Text('OPEN  →', style: Tx.eyebrow(t, color: t.gold)),
          ),
        ),
      ],
    );
  }
}
