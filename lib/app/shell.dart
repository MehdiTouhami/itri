import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import '../core/theme/type.dart';
import '../state/providers.dart';
import 'router.dart';

typedef _TabSpec = (int branch, IconData icon, String label);

/// Tab scaffold. Two tabs either side of the mode switch; the switch swaps
/// the tabs and the palette together, so Training and Recovery read as two
/// sides of one app rather than two apps.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const List<_TabSpec> _training = [
    (Tabs.today, Icons.show_chart_rounded, 'Today'),
    (Tabs.log, Icons.format_list_bulleted_rounded, 'Log'),
    (Tabs.sports, Icons.sports_tennis_rounded, 'Sports'),
    (Tabs.coach, Icons.forum_outlined, 'Coach'),
  ];
  static const List<_TabSpec> _recovery = [
    (Tabs.recovery, Icons.bedtime_outlined, 'Recovery'),
    (Tabs.nights, Icons.view_agenda_outlined, 'Nights'),
    (Tabs.trends, Icons.insights_rounded, 'Trends'),
    (Tabs.coach, Icons.forum_outlined, 'Coach'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tk;
    final idx = shell.currentIndex;
    final stored = ref.watch(appModeProvider);
    // The branch decides the mode, except on Coach, which belongs to both.
    final mode = idx >= Tabs.recovery ? AppMode.recovery : (idx == Tabs.coach ? stored : AppMode.training);
    if (mode != stored) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(appModeProvider.notifier).set(mode));
    }
    final tabs = mode == AppMode.training ? _training : _recovery;

    void go(int branch) {
      HapticFeedback.selectionClick();
      shell.goBranch(branch, initialLocation: branch == idx);
    }

    void toggle() {
      HapticFeedback.mediumImpact();
      final next = mode == AppMode.training ? AppMode.recovery : AppMode.training;
      final pos = tabs.indexWhere((s) => s.$1 == idx);
      final target = (next == AppMode.training ? _training : _recovery)[pos < 0 ? 0 : pos].$1;
      ref.read(appModeProvider.notifier).set(next);
      shell.goBranch(target);
    }

    Widget tab(_TabSpec s) => Expanded(
          child: _Tab(icon: s.$2, label: s.$3, active: idx == s.$1, onTap: () => go(s.$1)),
        );

    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: t.ground,
          border: Border(top: BorderSide(color: t.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                tab(tabs[0]),
                tab(tabs[1]),
                _ModeSwitch(mode: mode, onTap: toggle),
                tab(tabs[2]),
                tab(tabs[3]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final c = active ? t.text : t.textFaint;
    return Semantics(
      selected: active,
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              height: 2,
              width: active ? 18 : 0,
              color: t.gold,
            ),
            const Spacer(),
            Icon(icon, size: 20, color: c),
            const SizedBox(height: 4),
            Text(label.toUpperCase(), style: Tx.eyebrow(t, color: c).copyWith(fontSize: 9.5)),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// A capsule with a sliding knob: bolt for Training, moon for Recovery.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onTap});
  final AppMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final training = mode == AppMode.training;
    // Halves are flexible so borders and padding can never push them over.
    Widget icon(IconData i, bool on) => Expanded(
          child: Icon(i, size: 15, color: on ? t.ground : t.textFaint),
        );
    return Semantics(
      button: true,
      label: training ? 'Switch to Recovery' : 'Switch to Training',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 62,
                height: 28,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  border: Border.all(color: t.line),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Stack(
                  children: [
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      alignment: training ? Alignment.centerLeft : Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: 0.5,
                        child: Container(
                          height: 22,
                          decoration: BoxDecoration(color: t.gold, borderRadius: BorderRadius.circular(11)),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Row(
                        children: [
                          icon(Icons.bolt_rounded, training),
                          icon(Icons.dark_mode_outlined, !training),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                training ? 'TRAINING' : 'RECOVERY',
                style: Tx.eyebrow(t, color: t.gold).copyWith(fontSize: 9.5),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
