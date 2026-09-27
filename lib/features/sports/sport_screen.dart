import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/router.dart';
import '../../core/charts/session_trend.dart';
import '../../core/charts/week_bars.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/analysis.dart';
import '../../domain/sport.dart';
import '../../domain/sport_stats.dart';
import '../../state/providers.dart';
import '../activity/zone_breakdown.dart';
import '../common/activity_row.dart';
import 'widgets.dart';

/// One sport in depth: what it gives you, how it is changing, when you play.
class SportScreen extends ConsumerStatefulWidget {
  const SportScreen({super.key, required this.sport});
  final Sport sport;

  @override
  ConsumerState<SportScreen> createState() => _SportScreenState();
}

class _SportScreenState extends ConsumerState<SportScreen> {
  SessionMetric? _metric;
  int? _selected;
  int? _month;

  static final _monthLabel = DateFormat('MMM');

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final summaries = ref.watch(sportSummariesProvider);
    final s = switch (summaries) {
      AsyncData(:final value) => value.where((x) => x.sport == widget.sport).firstOrNull,
      _ => null,
    };
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: s == null
            ? Center(child: Text('No ${widget.sport.label.toLowerCase()} sessions', style: Tx.body(t, color: t.textMuted)))
            : _body(s),
      ),
    );
  }

  Widget _body(SportSummary s) {
    final t = context.tk;
    final zones = ref.watch(zonesProvider);
    final metrics = SessionMetric.forSport(s.sport);
    final metric = _metric ?? metrics.first;
    final values = [for (final x in s.sessions) metric.of(x)];
    final smooth = rollingMean(values, 5);
    final change = firstVsLast(values);
    final sel = _selected != null && _selected! < s.sessions.length ? _selected : null;
    final months = s.byMonth;
    final monthSel = _month ?? months.length - 1;
    final (mornings, afternoons, evenings) = (s.byDaypart[0], s.byDaypart[1], s.byDaypart[2]);
    final busiest = [('mornings', mornings), ('afternoons', afternoons), ('evenings', evenings)]
      ..sort((a, b) => b.$2.compareTo(a.$2));

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.sm, Sp.gutter, Sp.xxxl),
      children: [
        _TopBar(sport: s.sport),
        const SizedBox(height: Sp.lg),
        Eyebrow('${s.count} sessions · since ${Fmt.monthYear(s.first)}'),
        const SizedBox(height: Sp.sm),
        Text(s.sport.label.toUpperCase(), style: Tx.pageTitle(t)),
        const SizedBox(height: Sp.md),
        Text(_headline(s), style: Tx.title(t)),
        const SizedBox(height: Sp.xl),

        ReadoutGrid(children: [
          Readout(label: 'Sessions', value: '${s.count}'),
          Readout(label: 'Hours', value: s.hours.toStringAsFixed(s.hours < 10 ? 1 : 0)),
          Readout(label: 'Typical', value: Fmt.durationShort(s.avgSessionS)),
          Readout(label: 'Load / h', value: s.loadPerHour.round().toString(), color: t.gold),
          Readout(label: 'Hard time', value: '${(s.hardShare * 100).round()}', unit: '%'),
          Readout(label: 'Avg HR', value: s.avgHr.round().toString(), unit: 'bpm'),
        ]),

        if (s.sport.stopStart && s.efforts > 0) ...[
          const SectionHeader('Match intensity', trailing: 'zone 4+ bursts'),
          ReadoutGrid(children: [
            Readout(label: 'Efforts / h', value: s.effortsPerHour.toStringAsFixed(1)),
            Readout(label: 'Recovery', value: s.recovery?.round().toString() ?? '—', unit: 'bpm'),
            Readout(label: 'Best session', value: '${s.mostEfforts.efforts.length}', unit: 'efforts'),
          ]),
          const SizedBox(height: Sp.md),
          Text(
            'An effort is 10 s or more in zone 4 or above, such as a long rally or a sprint to the net. '
            'Recovery is how many beats your heart drops in the minute after one.',
            style: Tx.small(t, color: t.textFaint),
          ),
        ],

        SectionHeader('Over time', trailing: sel == null ? 'tap a session' : null),
        ChipRow<SessionMetric>(
          options: metrics,
          value: metric,
          label: (m) => m.label,
          onChanged: (m) => setState(() {
            _metric = m;
            _selected = null;
          }),
        ),
        const SizedBox(height: Sp.md),
        _SelectedLine(x: sel == null ? null : s.sessions[sel], metric: metric),
        const SizedBox(height: Sp.sm),
        SessionTrend(
          dates: [for (final x in s.sessions) x.activity.start],
          values: values,
          smooth: smooth,
          selected: sel,
          onSelect: (i) => setState(() => _selected = i),
          axisLabel: (v) => v.round().toString(),
        ),
        const SizedBox(height: Sp.sm),
        Text(
          '${metric.explainer} Gold line: average of the last five sessions.'
          '${change == null ? '' : ' First five ${change.from.round()}, last five ${change.to.round()}${metric.unit.isEmpty ? '' : ' ${metric.unit}'}.'}',
          style: Tx.small(t, color: t.textFaint),
        ),

        const SectionHeader('Heart-rate zones', trailing: 'all sessions'),
        ZoneBreakdown(zones: zones, seconds: s.zoneSeconds),

        SectionHeader('When you play', trailing: 'mostly ${busiest.first.$1}'),
        WeekdayBars(s.byWeekday),
        const SizedBox(height: Sp.md),
        Text(
          '$mornings morning, $afternoons afternoon and $evenings evening sessions.',
          style: Tx.small(t, color: t.textFaint),
        ),

        if (months.length > 1) ...[
          SectionHeader(
            'Sessions per month',
            trailing: '${DateFormat('MMM yyyy').format(months[monthSel].$1)} · ${months[monthSel].$2}',
          ),
          WeekBars(
            values: [for (final m in months) m.$2.toDouble()],
            labels: [for (final m in months) _monthLabel.format(m.$1)],
            selected: monthSel,
            onSelect: (i) => setState(() => _month = i),
            height: 110,
          ),
        ],

        const SectionHeader('Bests'),
        _Best('Longest', s.longest),
        _Best('Most load', s.hardest),
        if (s.sport.stopStart && s.efforts > 0) _Best('Most efforts', s.mostEfforts),

        SectionHeader('Recent', trailing: '${s.count} in total'),
        for (final x in s.sessions.reversed.take(5)) ActivityRow(x),
      ],
    );
  }

  /// One sentence that says what the numbers mean, from the data itself.
  String _headline(SportSummary s) {
    if (s.sport.stopStart) {
      final r = firstVsLast([for (final x in s.sessions) x.recovery]);
      if (r != null && (r.to - r.from).abs() >= 2) {
        return r.to > r.from
            ? 'You recover faster than when you started: ${r.from.round()} → ${r.to.round()} bpm dropped in the minute after a hard effort.'
            : 'Recovery after hard efforts has slipped lately: ${r.from.round()} → ${r.to.round()} bpm.';
      }
    }
    final d = firstVsLast([for (final x in s.sessions) x.activity.durationS / 60]);
    if (d != null && (d.to - d.from).abs() >= 10) {
      return 'Sessions have got ${d.to < d.from ? 'shorter' : 'longer'}: about ${d.from.round()} min at first, ${d.to.round()} min lately.';
    }
    return 'About ${Fmt.durationShort(s.avgSessionS)} a session, ${s.loadPerHour.round()} load an hour.';
  }
}

class _SelectedLine extends StatelessWidget {
  const _SelectedLine({required this.x, required this.metric});
  final ActivityAnalysis? x;
  final SessionMetric metric;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final a = x;
    if (a == null) {
      return Text('${metric.label}${metric.unit.isEmpty ? '' : ' · ${metric.unit}'}', style: Tx.data(t, color: t.textFaint));
    }
    final v = metric.of(a);
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: v == null ? '—' : v.round().toString(), style: Tx.numeral(t, size: 22)),
              TextSpan(
                text: '${metric.unit.isEmpty ? '' : ' ${metric.unit}'}  ·  ${Fmt.dayMonth(a.activity.start)}',
                style: Tx.data(t, size: 11, color: t.textMuted),
              ),
            ]),
          ),
        ),
        Pressable(
          onTap: () => openActivity(context, a.activity.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.xs),
            child: Text('OPEN  →', style: Tx.eyebrow(t, color: t.gold)),
          ),
        ),
      ],
    );
  }
}

class _Best extends StatelessWidget {
  const _Best(this.label, this.x);
  final String label;
  final ActivityAnalysis x;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Sp.sm),
        Eyebrow(label, color: context.tk.gold),
        ActivityRow(x),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.sport});
  final Sport sport;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Row(
      children: [
        Pressable(
          onTap: () => context.canPop() ? context.pop() : context.go('/sports'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.sm),
            child: Row(
              children: [
                Icon(Icons.arrow_back_rounded, size: 18, color: t.text),
                const SizedBox(width: Sp.sm),
                Text('BACK', style: Tx.eyebrow(t, color: t.text)),
              ],
            ),
          ),
        ),
        const Spacer(),
        Icon(sport.icon, size: 18, color: t.textMuted),
      ],
    );
  }
}
