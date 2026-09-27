import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/page_title.dart';
import '../../core/widgets/primitives.dart';
import '../../data/garmin/garmin_bundle.dart';
import '../../domain/athlete.dart';
import '../../state/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tk;
    final athlete = ref.watch(athleteProvider);
    final zones = ref.watch(zonesProvider);
    final mode = ref.watch(themeModeProvider);
    final notifier = ref.read(athleteProvider.notifier);
    final source = ref.watch(effectiveSourceProvider);
    final bundle = switch (ref.watch(garminBundleProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final count = switch (ref.watch(activitiesProvider)) {
      AsyncData(:final value) => value.length,
      _ => 0,
    };

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.lg, Sp.gutter, Sp.xxxl),
          children: [
            const BackBar(),
            const SizedBox(height: Sp.lg),
            const Eyebrow('Athlete'),
            const SizedBox(height: Sp.sm),
            Text('PROFILE', style: Tx.pageTitle(t)),

            const SectionHeader('Heart rate', trailing: 'drives zones and load'),
            _Stepper(
              label: 'Max HR',
              value: athlete.maxHr,
              unit: 'bpm',
              onChanged: (v) => notifier.update((a) => a.copyWith(maxHr: v.clamp(a.restHr + 40, 230))),
            ),
            const SizedBox(height: Sp.md),
            _Stepper(
              label: 'Resting HR',
              value: athlete.restHr,
              unit: 'bpm',
              onChanged: (v) => notifier.update((a) => a.copyWith(restHr: v.clamp(30, a.maxHr - 40))),
            ),

            const SectionHeader('Zones', trailing: '% of max HR'),
            for (final z in zones.zones.reversed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(width: 3, height: 18, color: t.zones[z.index]),
                    const SizedBox(width: Sp.md),
                    SizedBox(width: 28, child: Text(z.label, style: Tx.data(t, weight: FontWeight.w500))),
                    Expanded(child: Text(z.name, style: Tx.body(t))),
                    Text('${z.range} bpm', style: Tx.data(t, color: t.textMuted)),
                  ],
                ),
              ),

            const SectionHeader('Units'),
            _Segmented<Units>(
              value: athlete.units,
              options: const [(Units.metric, 'Kilometres'), (Units.imperial, 'Miles')],
              onChanged: (u) => notifier.update((a) => a.copyWith(units: u)),
            ),

            const SectionHeader('Appearance'),
            _Segmented<ThemeMode>(
              value: mode,
              options: const [(ThemeMode.dark, 'Dark'), (ThemeMode.light, 'Light'), (ThemeMode.system, 'System')],
              onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
            ),

            const SectionHeader('Data'),
            if (bundle != null) ...[
              _Segmented<DataSource>(
                value: source,
                options: const [(DataSource.garmin, 'My Garmin'), (DataSource.sample, 'Sample')],
                onChanged: (s) => ref.read(dataSourceProvider.notifier).set(s),
              ),
              const SizedBox(height: Sp.md),
            ],
            if (source == DataSource.garmin && bundle != null) ...[
              _InfoRow('Source', '${bundle.source} · $count sessions'),
              _InfoRow('Data until', Fmt.dayMonth(bundle.dataUntil)),
              _InfoRow('Resting HR', '${bundle.athlete.restHr} bpm · median of last 60 days'),
              if (bundle.check.n > 0) ...[
                const SectionHeader('Model check', trailing: 'our load vs Garmin'),
                _ModelCheck(bundle.check),
              ],
            ] else ...[
              _InfoRow('Source', 'Synthetic sample · $count sessions'),
              _InfoRow(
                'Garmin export',
                bundle == null ? 'Not found · run tools/garmin_import.py' : 'Available',
                faint: bundle == null,
              ),
            ],

            const SectionHeader('Live sync', trailing: 'Garmin via intervals.icu'),
            const _LiveSync(),

            const SectionHeader('About'),
            Text(
              'Itri 0.4 — training and recovery in one app. Training from your Garmin sessions, recovery from your nights, one coach across both.',
              style: Tx.small(t),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.unit, required this.onChanged});
  final String label;
  final int value;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    Widget btn(IconData icon, int delta) => Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(value + delta);
          },
          child: Container(
            width: 40,
            height: 36,
            decoration: BoxDecoration(
              border: Border.all(color: t.line),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(icon, size: 16, color: t.text),
          ),
        );
    return Row(
      children: [
        Expanded(child: Text(label, style: Tx.body(t))),
        btn(Icons.remove_rounded, -1),
        SizedBox(
          width: 76,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$value', style: Tx.numeral(t, size: 26)),
              TextSpan(text: ' $unit', style: Tx.data(t, size: 10.5, color: t.textMuted)),
            ]),
            textAlign: TextAlign.center,
          ),
        ),
        btn(Icons.add_rounded, 1),
      ],
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (final (v, label) in options)
            Expanded(
              child: Pressable(
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == value ? t.text : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    label.toUpperCase(),
                    style: Tx.eyebrow(t, color: v == value ? t.ground : t.textMuted),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.faint = false});
  final String label, value;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(label, style: Tx.body(t)),
          const SizedBox(width: Sp.lg),
          // Value takes the remaining width and wraps rather than overflowing.
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Tx.data(t, color: faint ? t.textFaint : t.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// How well our heart-rate load agrees with Garmin's, overall and per sport.
class _ModelCheck extends StatelessWidget {
  const _ModelCheck(this.check);
  final LoadCheck check;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final sports = check.bySport.entries.toList()..sort((a, b) => b.value.r.compareTo(a.value.r));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: 'r = ${check.pearson.toStringAsFixed(2)}', style: Tx.numeral(t, size: 34, color: t.gold)),
          TextSpan(text: '  across ${check.n} sessions', style: Tx.data(t, size: 11, color: t.textMuted)),
        ])),
        const SizedBox(height: Sp.sm),
        Text(
          'How closely the app\'s load score tracks Garmin\'s own, session by session. '
          '1.0 would be identical. Ours is built from heart rate alone, so it agrees best on '
          'steady efforts and least on short bursts, where Garmin also uses its own model of '
          'post-exercise oxygen use (EPOC).',
          style: Tx.small(t),
        ),
        const SizedBox(height: Sp.md),
        for (final e in sports)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(width: 84, child: Text(e.key.label, style: Tx.body(t))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: LinearProgressIndicator(
                      value: e.value.r.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: t.raised,
                      color: e.value.r >= 0.8 ? t.gold : t.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 76,
                  child: Text(
                    '${e.value.r.toStringAsFixed(2)} · ${e.value.n}',
                    textAlign: TextAlign.right,
                    style: Tx.data(t, color: t.textMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Connect intervals.icu once; after that sessions and nights arrive on their own.
class _LiveSync extends ConsumerStatefulWidget {
  const _LiveSync();

  @override
  ConsumerState<_LiveSync> createState() => _LiveSyncState();
}

class _LiveSyncState extends ConsumerState<_LiveSync> {
  final _key = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _connecting = true;
      _error = null;
    });
    final error = await ref.read(liveProvider.notifier).connect(_key.text);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = error;
    });
    if (error == null) _key.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final live = switch (ref.watch(liveProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final status = ref.watch(syncStatusProvider);
    if (live == null) return Text('Loading…', style: Tx.small(t));

    if (!live.connected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sessions and nights arrive on their own after your watch syncs, with no export to run. '
            'intervals.icu makes the Garmin link: create a free account there, connect Garmin under '
            'Settings → Connections, then copy the API key from Settings → Developer Settings.',
            style: Tx.small(t),
          ),
          const SizedBox(height: Sp.md),
          TextField(
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            style: Tx.data(t),
            cursorColor: t.gold,
            onSubmitted: (_) => _connect(),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'intervals.icu API key',
              hintStyle: Tx.data(t, color: t.textFaint),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.line),
                borderRadius: BorderRadius.circular(4),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.text),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: Sp.md),
          _Button(_connecting ? 'Checking…' : 'Connect', primary: true, onTap: _connecting ? null : _connect),
          if (_error != null) ...[
            const SizedBox(height: Sp.sm),
            Text(_error!, style: Tx.small(t, color: t.down)),
          ],
        ],
      );
    }

    final line = status.busy || status.message != null ? status.message! : 'Synced ${syncedAgo(live.syncedAt)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoRow('Status', line),
        if (status.busy) ...[
          const SizedBox(height: Sp.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: LinearProgressIndicator(
              value: status.total == 0 ? null : status.done / status.total,
              minHeight: 3,
              backgroundColor: t.raised,
              color: t.gold,
            ),
          ),
        ],
        _InfoRow('Last sync', syncedAgo(live.syncedAt)),
        _InfoRow('Synced', '${live.sessions} sessions · ${live.nights} nights'),
        if (status.error) Text('Last sync failed. Your data is unchanged.', style: Tx.small(t, color: t.down)),
        const SizedBox(height: Sp.md),
        Row(
          children: [
            Expanded(
              child: _Button(
                'Sync now',
                primary: true,
                onTap: status.busy ? null : () => ref.read(liveProvider.notifier).sync(force: true),
              ),
            ),
            const SizedBox(width: Sp.md),
            Expanded(child: _Button('Disconnect', onTap: status.busy ? null : () => ref.read(liveProvider.notifier).disconnect())),
          ],
        ),
        const SizedBox(height: Sp.md),
        Text(
          'Syncs when the app opens and whenever you come back to it; pull down on Today or Recovery to sync '
          'straight away. Live nights have the score, time asleep, HRV and resting heart rate, but no stages or '
          'bed times. Disconnect removes the key and the synced copy from this phone.',
          style: Tx.small(t),
        ),
      ],
    );
  }
}

class _Button extends StatelessWidget {
  const _Button(this.label, {required this.onTap, this.primary = false});
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final enabled = onTap != null;
    return Pressable(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.5,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? t.text : Colors.transparent,
            border: Border.all(color: primary ? t.text : t.line),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label.toUpperCase(), style: Tx.eyebrow(t, color: primary ? t.ground : t.text)),
        ),
      ),
    );
  }
}
