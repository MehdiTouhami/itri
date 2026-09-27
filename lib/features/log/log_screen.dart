import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/page_title.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/analysis.dart';
import '../../domain/sport.dart';
import '../../state/providers.dart';
import '../common/activity_row.dart';
import '../common/states.dart';

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  Sport? _filter;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ref.watch(analysesProvider).when(
              loading: () => const LoadingState(),
              error: (e, _) => ErrorState(e),
              data: (all) {
                final list = _filter == null ? all : all.where((x) => x.activity.sport == _filter).toList();
                final items = _group(list);
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.lg, Sp.gutter, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PageTitle(eyebrow: '${all.length} sessions', title: 'LOG'),
                            const SizedBox(height: Sp.lg),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(child: _filters(t, all)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(Sp.gutter, 0, Sp.gutter, Sp.xxxl),
                      sliver: SliverList.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) => switch (items[i]) {
                          final _Month m => _MonthHeader(m),
                          final _Row r => ActivityRow(r.x),
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
      ),
    );
  }

  /// Only sports that appear in the data, most frequent first.
  Widget _filters(ItriTokens t, List<ActivityAnalysis> all) {
    final counts = <Sport, int>{};
    for (final x in all) {
      counts[x.activity.sport] = (counts[x.activity.sport] ?? 0) + 1;
    }
    final sports = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final options = <Sport?>[null, ...sports];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.gutter),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: Sp.sm),
        itemBuilder: (context, i) {
          final s = options[i];
          final on = s == _filter;
          return Pressable(
            onTap: () => setState(() => _filter = s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: Sp.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? t.text : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: on ? t.text : t.line),
              ),
              child: Text(
                (s?.label ?? 'All').toUpperCase(),
                style: Tx.eyebrow(t, color: on ? t.ground : t.textMuted),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Flattens activities into month headers followed by their rows.
  List<_Item> _group(List<ActivityAnalysis> list) {
    final out = <_Item>[];
    _Month? current;
    for (final x in list) {
      final a = x.activity;
      if (current == null || current.year != a.start.year || current.month != a.start.month) {
        current = _Month(a.start.year, a.start.month);
        out.add(current);
      }
      current.add(x);
      out.add(_Row(x));
    }
    return out;
  }
}

sealed class _Item {
  const _Item();
}

class _Row extends _Item {
  const _Row(this.x);
  final ActivityAnalysis x;
}

class _Month extends _Item {
  _Month(this.year, this.month);
  final int year, month;
  int count = 0, seconds = 0;
  double load = 0;

  void add(ActivityAnalysis x) {
    count++;
    seconds += x.activity.durationS;
    load += x.load;
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader(this.m);
  final _Month m;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Padding(
      padding: const EdgeInsets.only(top: Sp.xl, bottom: Sp.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(Fmt.monthYear(DateTime(m.year, m.month)), style: Tx.heading(t))),
              Flexible(
                child: Text(
                  '${m.count} · ${Fmt.durationShort(m.seconds)} · load ${m.load.round()}',
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
  }
}
