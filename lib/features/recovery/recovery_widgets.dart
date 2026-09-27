import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/readiness.dart';
import '../../domain/sleep.dart';
import '../sports/widgets.dart';

Color levelColor(ItriTokens t, ReadinessLevel l) => switch (l) {
      ReadinessLevel.ready => t.up,
      ReadinessLevel.steady => t.text,
      ReadinessLevel.easy => t.gold,
      ReadinessLevel.recover => t.down,
    };

Color signalColor(ItriTokens t, Signal s) => switch (s) {
      Signal.good => t.up,
      Signal.neutral => t.textFaint,
      Signal.bad => t.down,
    };

Color scoreColor(ItriTokens t, int score) => score >= 80 ? t.up : (score < 60 ? t.down : t.text);

String hm(int seconds) => '${seconds ~/ 3600}h ${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}m';

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

String clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// The morning verdict with every factor that produced it.
class ReadinessBlock extends StatelessWidget {
  const ReadinessBlock(this.r, {super.key});
  final Readiness r;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Readiness'),
        const SizedBox(height: Sp.sm),
        FadeSwap(
          child: Text(
            r.level.label.toUpperCase(),
            key: ValueKey(r.level),
            style: Tx.hero(t, size: 64, color: levelColor(t, r.level)),
          ),
        ),
        const SizedBox(height: Sp.xs),
        Text(r.level.advice, style: Tx.body(t, color: t.textMuted)),
        const SizedBox(height: Sp.lg),
        for (final f in r.factors) _FactorRow(f),
      ],
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow(this.f);
  final ReadinessFactor f;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: signalColor(t, f.signal))),
          const SizedBox(width: Sp.md),
          SizedBox(width: 86, child: Text(f.label, style: Tx.body(t))),
          SizedBox(width: 78, child: Text(f.value, style: Tx.data(t, color: t.text, weight: FontWeight.w500))),
          Expanded(child: Text(f.note, style: Tx.small(t), maxLines: 2)),
        ],
      ),
    );
  }
}

/// One line on the Training side that says how recovered you are.
class ReadinessStrip extends StatelessWidget {
  const ReadinessStrip(this.r, {super.key});
  final Readiness r;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final reason = r.factors.where((f) => f.signal == Signal.bad).firstOrNull ??
        r.factors.where((f) => f.signal == Signal.good).firstOrNull;
    return Pressable(
      onTap: () => context.go('/recovery'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Sp.md),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line), bottom: BorderSide(color: t.line))),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: levelColor(t, r.level))),
            const SizedBox(width: Sp.md),
            Text(r.level.label, style: Tx.heading(t)),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(
                reason == null ? 'Readiness' : '${reason.label} ${reason.note.toLowerCase()}',
                style: Tx.small(t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: t.textFaint),
          ],
        ),
      ),
    );
  }
}

/// Stages as one proportional bar with a labelled legend underneath.
class StageBar extends StatelessWidget {
  const StageBar(this.n, {super.key, this.height = 10, this.legend = true});
  final SleepNight n;
  final double height;
  final bool legend;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final parts = [('Deep', n.deepS), ('Light', n.lightS), ('REM', n.remS ?? 0), ('Awake', n.awakeS)];
    final total = parts.fold<int>(0, (a, p) => a + p.$2);
    if (total == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                for (var i = 0; i < parts.length; i++)
                  if (parts[i].$2 > 0) Expanded(flex: parts[i].$2, child: Container(color: t.stages[i])),
              ],
            ),
          ),
        ),
        if (legend) ...[
          const SizedBox(height: Sp.md),
          Wrap(
            spacing: Sp.lg,
            runSpacing: Sp.sm,
            children: [
              for (var i = 0; i < parts.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: t.stages[i], borderRadius: BorderRadius.circular(1))),
                    const SizedBox(width: 6),
                    Text(parts[i].$1, style: Tx.small(t, color: t.text)),
                    const SizedBox(width: 4),
                    Text(
                      i == 2 && n.remS == null ? '—' : '${hm(parts[i].$2)} · ${(parts[i].$2 / total * 100).round()}%',
                      style: Tx.data(t, size: 10.5, color: t.textMuted),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Score, Garmin's one-line verdict, stages and the key overnight numbers.
class NightSummary extends StatelessWidget {
  const NightSummary(this.n, {super.key});
  final SleepNight n;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${n.score}', style: Tx.hero(t, size: 72, color: scoreColor(t, n.score))),
            const SizedBox(width: Sp.lg),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Sleep score'),
                    const SizedBox(height: 2),
                    Text(n.feedbackText.isEmpty ? 'Synced live' : n.feedbackText, style: Tx.title(t)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.xl),
        if (n.hasStages)
          StageBar(n)
        else
          Text(
            'Live nights come without stages or bed times: intervals.icu receives the score, '
            'time asleep, HRV and resting heart rate from Garmin, not the full night.',
            style: Tx.small(t),
          ),
        const SizedBox(height: Sp.xl),
        ReadoutGrid(children: [
          Readout(label: 'Asleep', value: hm(n.asleepS)),
          Readout(
            label: 'Bed → up',
            value: n.start == null || n.end == null ? '—' : '${clock(n.start!)}–${clock(n.end!)}',
            size: 22,
          ),
          Readout(label: 'Efficiency', value: n.efficiency == null ? '—' : '${(n.efficiency! * 100).round()}', unit: '%'),
          Readout(label: 'HRV', value: n.hrv?.round().toString() ?? '—', unit: 'ms'),
          Readout(label: 'Resting HR', value: n.restingHr?.toString() ?? '—', unit: 'bpm'),
          Readout(label: 'Breathing', value: n.respiration?.toStringAsFixed(1) ?? '—', unit: '/min'),
        ]),
      ],
    );
  }
}

/// Garmin's sub-scores as bars; the weakest is highlighted because that is
/// the part worth fixing.
class SubScores extends StatelessWidget {
  const SubScores(this.n, {super.key});
  final SleepNight n;

  static const _names = {
    'durationScore': 'Duration',
    'qualityScore': 'Quality',
    'recoveryScore': 'Recovery',
    'deepScore': 'Deep',
    'remScore': 'REM',
    'lightScore': 'Light',
    'restfulnessScore': 'Restfulness',
    'interruptionsScore': 'Interruptions',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final entries = [
      for (final k in _names.keys)
        if (n.subScores[k] != null) (_names[k]!, n.subScores[k]!),
    ];
    if (entries.isEmpty) return Text('No breakdown for this night.', style: Tx.small(t));
    final weakest = entries.reduce((a, b) => b.$2 < a.$2 ? b : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries) ShareRow(label: e.$1, value: '${e.$2}', fraction: e.$2 / 100, highlight: e == weakest),
        const SizedBox(height: Sp.sm),
        Text('Weakest part of the night: ${weakest.$1.toLowerCase()} (${weakest.$2} of 100).', style: Tx.small(t)),
      ],
    );
  }
}

/// Compact night row for lists.
class NightRow extends StatelessWidget {
  const NightRow(this.n, {super.key, required this.onTap});
  final SleepNight n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(Fmt.dayMonth(n.evening), style: Tx.heading(t)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (n.start != null && n.end != null) '${clock(n.start!)} → ${clock(n.end!)}',
                          if (n.feedbackText.isNotEmpty) n.feedbackText,
                        ].join(' · ').ifEmpty('Score, time asleep and HRV'),
                        style: Tx.small(t),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${n.score}', style: Tx.numeral(t, size: 24, color: scoreColor(t, n.score))),
                    Text(hm(n.asleepS), style: Tx.data(t, size: 10.5, color: t.textMuted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Sp.sm),
            FractionallySizedBox(
              widthFactor: 0.6,
              alignment: Alignment.centerLeft,
              child: StageBar(n, height: 4, legend: false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when there is nothing to read yet.
class EmptyRecovery extends StatelessWidget {
  const EmptyRecovery({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xl),
        child: Text(
          'No nights yet. Recovery reads sleep, HRV and resting heart rate from your Garmin export.',
          textAlign: TextAlign.center,
          style: Tx.body(t, color: t.textMuted),
        ),
      ),
    );
  }
}
