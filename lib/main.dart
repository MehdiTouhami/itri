import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/live_sync.dart';
import 'app/router.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'state/providers.dart';

void main() => runApp(const ProviderScope(child: ItriFitnessApp()));

class ItriFitnessApp extends ConsumerWidget {
  const ItriFitnessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(appModeProvider) == AppMode.recovery;
    return MaterialApp.router(
      title: 'Itri',
      debugShowCheckedModeBanner: false,
      // Same design system in both modes; only the palette changes, and it
      // cross-fades because every token lerps.
      theme: ItriTheme.light(recovery ? ItriTokens.recoveryLight : ItriTokens.light),
      darkTheme: ItriTheme.dark(recovery ? ItriTokens.recoveryDark : ItriTokens.dark),
      themeAnimationDuration: const Duration(milliseconds: 380),
      themeAnimationCurve: Curves.easeInOut,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: appRouter,
      builder: (context, child) => LiveSyncHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
