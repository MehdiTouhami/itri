import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../data/coach/coach_client.dart';
import '../core/theme/tokens.dart';
import '../state/providers.dart';

/// Keeps the live data current without any user action: syncs on launch and
/// every time the app returns to the foreground (throttled to one sync per
/// two minutes). Pull-to-refresh on Today and Recovery forces one.
class LiveSyncHost extends ConsumerStatefulWidget {
  const LiveSyncHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LiveSyncHost> createState() => _LiveSyncHostState();
}

class _LiveSyncHostState extends ConsumerState<LiveSyncHost> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    // Wake the coach server now, so it's up by the time the Coach tab opens.
    if (!Platform.environment.containsKey('FLUTTER_TEST')) unawaited(CoachClient().wake());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  Future<void> _sync() async {
    await ref.read(liveProvider.future); // wait for the stored key and data to load
    if (!mounted) return;
    await ref.read(liveProvider.notifier).sync();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Page-title eyebrow and tag: sample data, the export, or live with freshness.
({String eyebrow, String tag, bool real}) sourceLabels(WidgetRef ref, DateTime asOf) {
  if (ref.watch(effectiveSourceProvider) != DataSource.garmin) {
    return (eyebrow: Fmt.dayMonth(asOf), tag: 'Sample', real: false);
  }
  final live = switch (ref.watch(liveProvider)) {
    AsyncData(:final value) => value,
    _ => null,
  };
  if (live == null || !live.connected) return (eyebrow: 'As of ${Fmt.dayMonth(asOf)}', tag: 'Garmin', real: true);
  final busy = ref.watch(syncStatusProvider).busy;
  return (eyebrow: busy ? 'Syncing…' : 'Synced ${syncedAgo(live.syncedAt)}', tag: 'Live', real: true);
}

/// Pull down to sync, once live sync is connected.
class LiveRefresh extends ConsumerWidget {
  const LiveRefresh({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = switch (ref.watch(liveProvider)) {
      AsyncData(:final value) => value.connected,
      _ => false,
    };
    if (!connected) return child;
    final t = context.tk;
    return RefreshIndicator(
      color: t.gold,
      backgroundColor: t.raised,
      onRefresh: () => ref.read(liveProvider.notifier).sync(force: true),
      child: child,
    );
  }
}
