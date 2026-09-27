import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/charts/route_trace.dart';
import '../../core/charts/scrub.dart';
import '../../core/charts/trace_chart.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/analysis.dart';
import '../../domain/athlete.dart';
import '../../domain/hr_zones.dart';
import '../../domain/sample.dart';
import '../../domain/sport.dart';
import '../../state/providers.dart';
import 'splits_table.dart';
import 'zone_breakdown.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _cursor = ValueNotifier<double?>(null);

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final x = ref.watch(analysisByIdProvider(widget.id));
    final athlete = ref.watch(athleteProvider);
    final zones = ref.watch(zonesProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: x == null
            ? Center(child: Text('Session not found', style: Tx.body(t, color: t.textMuted)))
            : _body(x, athlete, zones),
      ),
    );
  }

  Widget _body(ActivityAnalysis x, Athlete athlete, HrZoneModel zones) {
    final t = context.tk;
    final a = x.activity;
    final u = athlete.units;
    final pts = downsample(a.samples, 240);
    final pace = a.sport.usesPace;
    // Court and gym sessions still log distance, but pace and splits mean nothing there.
    final dist = a.sport.hasGps && a.distanceM > 0;
    final hasAlt = a.samples.any((s) => s.altitudeM != null);

    final primary = <Widget>[
      if (dist) Readout(label: 'Distance', value: Fmt.distance(a.distanceM, u), unit: Fmt.distUnit(u), size: 34),
      Readout(label: 'Time', value: Fmt.duration(a.durationS), size: 34),
      if (dist)
        pace
            ? Readout(label: 'Avg pace', value: Fmt.pace(a.avgSpeedMs, u), unit: Fmt.paceUnit(u), size: 34)
            : Readout(label: 'Avg speed', value: Fmt.speed(a.avgSpeedMs, u), unit: Fmt.speedUnit(u), size: 34)
      else
        Readout(label: 'Avg HR', value: '${a.avgHr}', unit: 'bpm', size: 34),
    ];

    final secondary = <Widget>[
      if (dist) Readout(label: 'Avg HR', value: '${a.avgHr}', unit: 'bpm'),
      Readout(label: 'Max HR', value: '${a.maxHr}', unit: 'bpm'),
      Readout(label: 'Load', value: x.load.round().toString(), color: t.gold),
      if (a.deviceLoad != null) Readout(label: 'Garmin load', value: a.deviceLoad!.round().toString()),
      if (a.aerobicTE != null) Readout(label: 'Aerobic effect', value: a.aerobicTE!.toStringAsFixed(1), unit: '/ 5'),
      if (a.anaerobicTE != null) Readout(label: 'Anaerobic', value: a.anaerobicTE!.toStringAsFixed(1), unit: '/ 5'),
      if (!a.sport.hasGps && a.distanceM > 100)
        Readout(label: 'Covered', value: Fmt.distance(a.distanceM, u, decimals: 1), unit: Fmt.distUnit(u)),
      if (dist && hasAlt) Readout(label: 'Climb', value: Fmt.elevation(a.elevationGainM, u), unit: Fmt.elevUnit(u)),
      Readout(label: 'Energy', value: '${a.calories}', unit: 'kcal'),
      if (a.avgPower != null) Readout(label: 'Avg power', value: '${a.avgPower}', unit: 'W'),
      if (a.avgCadence != null)
        Readout(label: 'Cadence', value: '${a.avgCadence}', unit: a.sport == Sport.ride ? 'rpm' : 'spm'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.sm, Sp.gutter, Sp.xxxl),
      children: [
        _TopBar(sport: a.sport),
        const SizedBox(height: Sp.lg),
        Eyebrow('${a.sport.label}${a.indoor ? ' · indoor' : ''} · ${Fmt.dayMonth(a.start)} · ${Fmt.time(a.start)}'),
        const SizedBox(height: Sp.sm),
        Text(a.name, style: Tx.title(t).copyWith(fontSize: 26)),
        const SizedBox(height: Sp.xs),
        if (a.locality.isNotEmpty && !a.name.contains(a.locality)) Text(a.locality, style: Tx.small(t)),
        const SizedBox(height: Sp.xl),
        ReadoutGrid(children: primary),
        const SizedBox(height: Sp.xl),
        Container(height: 1, color: t.line),
        const SizedBox(height: Sp.lg),
        ReadoutGrid(children: secondary),

        if (a.hasRoute) ...[
          const SectionHeader('Route', trailing: 'coloured by HR zone'),
          RouteTrace(points: pts, zoneOf: zones.indexOf, cursor: _cursor),
          const SizedBox(height: Sp.md),
          _ZoneKey(zones: zones),
        ],

        const SectionHeader('Telemetry', trailing: 'drag across to inspect'),
        _CursorReadout(points: pts, cursor: _cursor, units: u, sport: a.sport),
        const SizedBox(height: Sp.lg),
        ScrubArea(
          position: _cursor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TrackLabel('Heart rate', 'bpm'),
              TraceChart(
                values: [for (final p in pts) p.heartRate?.toDouble()],
                cursor: _cursor,
                color: t.zones[2],
                bands: ValueBands(
                  [for (final z in zones.zones.skip(1)) z.lower.toDouble()],
                  t.zones,
                ),
                axisLabel: (v) => v.round().toString(),
                height: 104,
              ),
              if (dist) ...[
                const SizedBox(height: Sp.lg),
                _TrackLabel(pace ? 'Pace' : 'Speed', pace ? Fmt.paceUnit(u) : Fmt.speedUnit(u)),
                TraceChart(
                  values: [
                    for (final p in pts)
                      pace
                          ? ((p.speedMs ?? 0) > 0.5 ? Fmt.unitM(u) / p.speedMs! : null)
                          : (p.speedMs == null ? null : p.speedMs! * 3600 / Fmt.unitM(u)),
                  ],
                  cursor: _cursor,
                  color: t.text,
                  invert: pace,
                  axisLabel: (v) => pace ? Fmt.paceFromSeconds(v) : v.toStringAsFixed(0),
                ),
              ],
              if (dist && hasAlt) ...[
                const SizedBox(height: Sp.lg),
                _TrackLabel('Elevation', Fmt.elevUnit(u)),
                TraceChart(
                  values: [
                    for (final p in pts)
                      p.altitudeM == null ? null : (u == Units.metric ? p.altitudeM! : p.altitudeM! * 3.28084),
                  ],
                  cursor: _cursor,
                  color: t.textMuted,
                  axisLabel: (v) => v.round().toString(),
                  height: 64,
                ),
              ],
              if (a.avgPower != null) ...[
                const SizedBox(height: Sp.lg),
                const _TrackLabel('Power', 'W'),
                TraceChart(
                  values: [for (final p in pts) p.power?.toDouble()],
                  cursor: _cursor,
                  color: t.gold,
                  floor: 0,
                  axisLabel: (v) => v.round().toString(),
                ),
              ],
              const SizedBox(height: Sp.sm),
              _TimeAxis(durationS: a.durationS),
            ],
          ),
        ),

        const SectionHeader('Time in zones', trailing: '% of max HR model'),
        ZoneBreakdown(zones: zones, seconds: x.zoneSeconds),

        if (a.sport.stopStart && x.efforts.isNotEmpty) ...[
          const SectionHeader('Efforts', trailing: '10 s+ in zone 4 or above'),
          ReadoutGrid(children: [
            Readout(label: 'Efforts', value: '${x.efforts.length}'),
            Readout(label: 'Per hour', value: x.effortsPerHour.toStringAsFixed(1)),
            Readout(label: 'Recovery', value: x.recovery?.round().toString() ?? '—', unit: 'bpm'),
          ]),
          const SizedBox(height: Sp.md),
          Builder(builder: (context) {
            final longest = x.efforts.reduce((p, q) => q.seconds > p.seconds ? q : p);
            return Text(
              'Longest effort: ${Fmt.duration(longest.seconds)} from ${Fmt.duration(longest.startS)} in, '
              'peaking at ${longest.peakHr} bpm. Recovery is how far your heart rate falls in the minute after each peak.',
              style: Tx.small(t),
            );
          }),
          const SizedBox(height: Sp.sm),
          Pressable(
            onTap: () => openSport(context, a.sport),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.sm),
              child: Text('ALL ${a.sport.label.toUpperCase()}  →', style: Tx.eyebrow(t, color: t.gold)),
            ),
          ),
        ],

        if (dist && a.distanceM > Fmt.unitM(u)) ...[
          SectionHeader('Splits', trailing: 'every ${pace ? 1 : 5} ${Fmt.distUnit(u)}'),
          SplitsTable(
            splits: splitsOf(a.samples, unitM: Fmt.unitM(u) * (pace ? 1 : 5)),
            units: u,
            usesPace: pace,
            every: pace ? 1 : 5,
          ),
        ],

        const SizedBox(height: Sp.xl),
        const SectionHeader('How to read this'),
        Text(
          'Load is minutes weighted by how hard your heart worked (Banister TRIMP): '
          'an hour easy scores far less than an hour near max.'
          '${a.aerobicTE == null ? '' : ' Aerobic and anaerobic effect are Garmin\'s 0–5 scores for how much the session built your endurance and your top-end.'}',
          style: Tx.small(t),
        ),
        const SizedBox(height: Sp.lg),
        Text(
          a.deviceLoad != null
              ? 'Imported from Garmin FIT · ${a.samples.length} samples at 5 s'
              : 'Synthetic session · ${a.samples.length} samples at 5 s · parsed like a FIT file',
          style: Tx.data(t, size: 10.5, color: t.textFaint),
        ),
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
          onTap: () => context.canPop() ? context.pop() : context.go('/log'),
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

class _TrackLabel extends StatelessWidget {
  const _TrackLabel(this.label, this.unit);
  final String label, unit;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.xs),
      child: Row(
        children: [
          Eyebrow(label),
          const SizedBox(width: Sp.sm),
          Text(unit, style: Tx.data(t, size: 10, color: t.textFaint)),
        ],
      ),
    );
  }
}

class _TimeAxis extends StatelessWidget {
  const _TimeAxis({required this.durationS});
  final int durationS;

  @override
  Widget build(BuildContext context) {
    final style = Tx.data(context.tk, size: 9.5, color: context.tk.textFaint);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final f in const [0.0, 0.25, 0.5, 0.75, 1.0]) Text(Fmt.duration(durationS * f), style: style),
      ],
    );
  }
}

/// Values under the cursor. Idle, it tells the reader what to do.
class _CursorReadout extends StatelessWidget {
  const _CursorReadout({required this.points, required this.cursor, required this.units, required this.sport});
  final List<Sample> points;
  final ValueNotifier<double?> cursor;
  final Units units;
  final Sport sport;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return ValueListenableBuilder<double?>(
      valueListenable: cursor,
      builder: (context, c, _) {
        final s = c == null ? null : points[scrubIndex(c, points.length)];
        String v(String Function(Sample) f) => s == null ? '—' : f(s);
        final cells = <(String, String)>[
          ('At', v((s) => Fmt.duration(s.t))),
          if (sport.hasGps) ('Dist', v((s) => Fmt.distance(s.distanceM ?? 0, units))),
          ('HR', v((s) => '${s.heartRate ?? '—'}')),
          if (sport.hasGps)
            sport.usesPace ? ('Pace', v((s) => Fmt.pace(s.speedMs, units))) : ('Speed', v((s) => Fmt.speed(s.speedMs, units))),
          if (sport.hasGps) ('Elev', v((s) => s.altitudeM == null ? '—' : Fmt.elevation(s.altitudeM!, units))),
        ];
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: c == null ? 0.55 : 1,
          child: Row(
            children: [
              for (final (label, value) in cells)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(label),
                      const SizedBox(height: Sp.xs),
                      Text(value, style: Tx.numeral(t, size: 20)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ZoneKey extends StatelessWidget {
  const _ZoneKey({required this.zones});
  final HrZoneModel zones;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Wrap(
      spacing: Sp.md,
      runSpacing: Sp.xs,
      children: [
        for (final z in zones.zones)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 3, color: t.zones[z.index]),
              const SizedBox(width: 5),
              Text(z.label, style: Tx.data(t, size: 10.5, color: t.textMuted)),
            ],
          ),
      ],
    );
  }
}
