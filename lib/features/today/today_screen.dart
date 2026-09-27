import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/live_sync.dart';
import '../../app/router.dart';
import '../../core/charts/heatmap.dart';
import '../../core/charts/load_chart.dart';
import '../../core/charts/scrub.dart';
import '../../core/charts/week_bars.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/page_title.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/aggregates.dart';
import '../../domain/analysis.dart';
import '../../domain/readiness.dart';
import '../../domain/sport.dart';
import '../../domain/training_load.dart';
import '../../state/providers.dart';
import '../common/activity_row.dart';
import '../common/states.dart';
import '../recovery/recovery_widgets.dart';
import '../sports/widgets.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  final _cursor = ValueNotifier<double?>(null);
  int? _week;
  DateTime? _day;

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analyses = ref.watch(analysesProvider);
    final series = ref.watch(loadSeriesProvider);
    final asOf = ref.watch(asOfProvider);
    final real = ref.watch(effectiveSourceProvider) == DataSource.garmin;
    final readiness = ref.watch(readinessProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch ((analyses, series)) {
          (AsyncData(value: final list), AsyncData(value: final days)) =>
            LiveRefresh(child: _content(list, days, asOf, real, readiness)),
          (AsyncError(:final error), _) || (_, AsyncError(:final error)) => ErrorState(error),
          _ => const LoadingState(),
        },
      ),
    );
  }

  Widget _content(List<ActivityAnalysis> list, List<DayLoad> allDays, DateTime today, bool real, Readiness? readiness) {
    final t = context.tk;
    final days = allDays.length > 90 ? allDays.sublist(allDays.length - 90) : allDays;
    final weeks = weeklyTotals(list, today, 12);
    final byDay = loadByDay(list);
    final thisWeek = weeks.last, lastWeek = weeks[weeks.length - 2];
    final selWeek = weeks[_week ?? weeks.length - 1];
    final loads = <Sport, double>{};
    for (final x in list) {
      if (x.activity.day.isBefore(thisWeek.monday)) continue;
      loads[x.activity.sport] = (loads[x.activity.sport] ?? 0) + x.load;
    }
    final weekBySport = [for (final e in loads.entries) (e.key, e.value)]..sort((a, b) => b.$2.compareTo(a.$2));
    final labels = sourceLabels(ref, today);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.lg, Sp.gutter, Sp.xxxl),
      children: [
        PageTitle(
          eyebrow: labels.eyebrow,
          title: 'TODAY',
          tag: labels.tag,
          tagColor: real ? t.gold : null,
        ),
        if (readiness != null) ...[
          const SizedBox(height: Sp.lg),
          ReadinessStrip(readiness),
        ],
        const SizedBox(height: Sp.xl),

        // ── Form hero: follows the chart cursor, else today ────────────────
        ValueListenableBuilder<double?>(
          valueListenable: _cursor,
          builder: (context, c, _) {
            final d = c == null ? days.last : days[scrubIndex(c, days.length)];
            return _FormHero(day: d, rampPerWeek: _ramp(days, d), isToday: c == null);
          },
        ),

        const SectionHeader('Fitness & fatigue', trailing: '90 days · drag to inspect'),
        Wrap(
          spacing: Sp.lg,
          runSpacing: Sp.sm,
          children: [
            _Key(color: t.gold, label: 'Fitness', thick: true),
            _Key(color: t.textMuted, label: 'Fatigue'),
            _Key(color: t.up, label: 'Form +', bar: true),
            _Key(color: t.down, label: 'Form −', bar: true),
          ],
        ),
        const SizedBox(height: Sp.md),
        ScrubArea(position: _cursor, child: LoadChart(days: days, cursor: _cursor)),

        const SectionHeader('This week', trailing: 'Mon–Sun'),
        ReadoutGrid(columns: 2, children: [
          _DeltaReadout('Sessions', '${thisWeek.sessions}', null, thisWeek.sessions - lastWeek.sessions, 0),
          _DeltaReadout('Time', Fmt.durationShort(thisWeek.seconds), null,
              (thisWeek.seconds - lastWeek.seconds) / 60, 0, suffix: 'm'),
          _DeltaReadout('Hard time', '${_hard(thisWeek)}', 'min', _hard(thisWeek) - _hard(lastWeek), 0, suffix: 'm'),
          _DeltaReadout('Load', thisWeek.load.round().toString(), null, thisWeek.load - lastWeek.load, 0),
        ]),
        const SizedBox(height: Sp.md),
        Text(
          'Hard time is minutes in zones 4–5. Load weights every minute by how hard your heart '
          'was working, so one hard hour can outscore three easy ones.',
          style: Tx.small(t, color: t.textFaint),
        ),

        if (weekBySport.isNotEmpty) ...[
          const SectionHeader('Load by sport', trailing: 'this week · tap for detail'),
          for (final e in weekBySport)
            ShareRow(
              label: e.$1.label,
              value: e.$2.round().toString(),
              fraction: e.$2 / weekBySport.first.$2,
              highlight: e == weekBySport.first,
              onTap: () => openSport(context, e.$1),
            ),
        ],

        SectionHeader('Weekly load', trailing: 'wk of ${Fmt.shortDate(selWeek.monday)} · load ${selWeek.load.round()}'),
        WeekBars(
          values: [for (final w in weeks) w.load],
          labels: [for (final w in weeks) '${w.monday.day}/${w.monday.month}'],
          selected: _week ?? weeks.length - 1,
          onSelect: (i) => setState(() => _week = i),
        ),
        const SizedBox(height: Sp.sm),
        Text('Dashed line: 12-week average. Gold: this week.', style: Tx.small(t, color: t.textFaint)),

        SectionHeader(
          'Consistency',
          trailing: _day == null
              ? '22 weeks · tap a day'
              : '${Fmt.dayMonth(_day!)} · load ${(byDay[_day] ?? 0).round()}',
        ),
        LoadHeatmap(
          end: today,
          weeks: 22,
          loadOn: (d) => byDay[d] ?? 0,
          selected: _day,
          onSelect: (d) => setState(() => _day = d),
        ),

        SectionHeader('Recent', trailing: '${list.length} sessions logged'),
        for (final x in list.take(4)) ActivityRow(x),
        const SizedBox(height: Sp.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: Pressable(
            onTap: () => context.go('/log'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.sm),
              child: Text('ALL SESSIONS  →', style: Tx.eyebrow(t, color: t.gold)),
            ),
          ),
        ),
      ],
    );
  }

  static int _hard(WeekTotals w) => ((w.zoneSeconds[3] + w.zoneSeconds[4]) / 60).round();

  /// Fitness change over the 7 days before [d].
  double _ramp(List<DayLoad> days, DayLoad d) {
    final i = days.indexOf(d);
    if (i < 7) return 0;
    return d.fitness - days[i - 7].fitness;
  }
}

class _FormHero extends StatelessWidget {
  const _FormHero({required this.day, required this.rampPerWeek, required this.isToday});
  final DayLoad day;
  final double rampPerWeek;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final state = day.state;
    final verdictColor = switch (state) {
      FormStatus.fresh => t.up,
      FormStatus.overreaching => t.down,
      _ => t.text,
    };
    final ramp = rampPerWeek.abs() < 0.5
        ? 'Fitness held steady over the past week.'
        : 'Fitness ${rampPerWeek > 0 ? 'up' : 'down'} ${rampPerWeek.abs().toStringAsFixed(1)} over the past week.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(isToday ? 'Training form' : 'Training form · ${Fmt.dayMonth(day.day)}'),
        const SizedBox(height: Sp.sm),
        // The answer first; the numbers behind it second.
        FadeSwap(
          child: Text(
            state.label.toUpperCase(),
            key: ValueKey(state),
            style: Tx.hero(t, size: 64, color: verdictColor),
          ),
        ),
        const SizedBox(height: Sp.xs),
        Text('${state.advice} $ramp', style: Tx.body(t, color: t.textMuted)),
        const SizedBox(height: Sp.xl),
        ReadoutGrid(children: [
          Readout(label: 'Form', value: Fmt.signed(day.form), color: day.form >= 0 ? t.up : t.down),
          Readout(label: 'Fitness', value: day.fitness.round().toString(), color: t.gold),
          Readout(label: 'Fatigue', value: day.fatigue.round().toString()),
        ]),
        const SizedBox(height: Sp.md),
        Text(
          'Fitness is your six-week training base, fatigue is roughly the last week\'s strain, '
          'and form is the gap between them. Positive form means fresh.',
          style: Tx.small(t, color: t.textFaint),
        ),
      ],
    );
  }
}

/// Legend key: a short line or bar swatch beside a text label.
class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label, this.thick = false, this.bar = false});
  final Color color;
  final String label;
  final bool thick, bar;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: bar ? 4 : 14, height: bar ? 10 : (thick ? 2 : 1.2), color: color),
        const SizedBox(width: 6),
        Text(label, style: Tx.small(context.tk)),
      ],
    );
  }
}

class _DeltaReadout extends StatelessWidget {
  const _DeltaReadout(this.label, this.value, this.unit, this.delta, this.decimals, {this.suffix = ''});
  final String label, value;
  final String? unit;
  final num delta;
  final int decimals;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final flat = delta.abs() < (decimals == 0 ? 0.5 : 0.05);
    // Neutral on purpose: less volume in a recovery week is not a failure.
    final c = flat ? t.textFaint : t.textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Readout(label: label, value: value, unit: unit),
        const SizedBox(height: Sp.xs),
        Text(flat ? 'same as last week' : '${Fmt.signed(delta, decimals: decimals)}$suffix vs last week', style: Tx.data(t, size: 11, color: c)),
      ],
    );
  }
}
