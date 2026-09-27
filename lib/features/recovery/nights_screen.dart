import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/page_title.dart';
import '../../domain/sleep.dart';
import '../../state/providers.dart';
import '../common/states.dart';
import 'recovery_widgets.dart';

/// Every night, newest first, grouped by month with the month's averages.
class NightsScreen extends ConsumerWidget {
  const NightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (ref.watch(recoveryProvider)) {
          AsyncData(:final value) => value.isEmpty ? const EmptyRecovery() : _body(context, value),
          AsyncError(:final error) => ErrorState(error),
          _ => const LoadingState(),
        },
      ),
    );
  }

  Widget _body(BuildContext context, RecoveryData rec) {
    final t = context.tk;
    final nights = rec.nights.reversed.toList();
    final items = <Object>[];
    DateTime? month;
    for (final n in nights) {
      final m = DateTime(n.evening.year, n.evening.month);
      if (m != month) {
        month = m;
        items.add(m);
      }
      items.add(n);
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.lg, Sp.gutter, 0),
          sliver: SliverToBoxAdapter(child: PageTitle(eyebrow: '${nights.length} nights', title: 'NIGHTS')),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Sp.gutter, 0, Sp.gutter, Sp.xxxl),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              if (item is SleepNight) return NightRow(item, onTap: () => openNight(context, item.date));
              final m = item as DateTime;
              final inMonth = nights.where((n) => n.evening.year == m.year && n.evening.month == m.month).toList();
              final score = inMonth.fold<int>(0, (a, n) => a + n.score) / inMonth.length;
              final asleep = inMonth.fold<int>(0, (a, n) => a + n.asleepS) ~/ inMonth.length;
              return Padding(
                padding: const EdgeInsets.only(top: Sp.xl, bottom: Sp.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(child: Text(Fmt.monthYear(m), style: Tx.heading(t))),
                        Flexible(
                          child: Text(
                            '${inMonth.length} · avg ${score.round()} · ${hm(asleep)}',
                            textAlign: TextAlign.right,
                            style: Tx.data(t, size: 11, color: t.textMuted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Sp.sm),
                    Container(height: 1, color: t.line),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
