import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/primitives.dart';

/// Label · proportional bar · value. The comparison is the bar length, so
/// there is no axis; [highlight] marks the one row the text is talking about.
class ShareRow extends StatelessWidget {
  const ShareRow({
    super.key,
    required this.label,
    required this.value,
    required this.fraction,
    this.highlight = false,
    this.onTap,
  });

  final String label, value;
  final double fraction;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(label, style: Tx.body(t))),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  Container(height: 6, decoration: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(1))),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    height: 6,
                    width: box.maxWidth * fraction.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: highlight ? t.gold : t.textMuted,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(value, textAlign: TextAlign.right, style: Tx.data(t, color: highlight ? t.text : t.textMuted)),
          ),
          if (onTap != null) ...[
            const SizedBox(width: Sp.xs),
            Icon(Icons.chevron_right_rounded, size: 16, color: t.textFaint),
          ],
        ],
      ),
    );
    return onTap == null ? row : Pressable(onTap: onTap, child: row);
  }
}

/// Seven small columns, Monday first. The biggest is in the accent colour.
class WeekdayBars extends StatelessWidget {
  const WeekdayBars(this.values, {super.key, this.height = 64, this.format});
  final List<num> values;
  final double height;
  final String Function(num)? format;

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final most = values.fold<num>(0, (a, b) => b > a ? b : a);
    final top = most <= 0 ? 1 : most;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Column(
              children: [
                Text(format?.call(values[i]) ?? '${values[i]}', style: Tx.data(t, size: 10, color: t.textFaint)),
                const SizedBox(height: Sp.xs),
                Container(
                  height: height * values[i] / top,
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: values[i] == most && most > 0 ? t.gold : t.raised,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ),
                const SizedBox(height: Sp.xs),
                Text(_days[i], style: Tx.data(t, size: 10, color: t.textMuted)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Horizontal set of mono chips; one is active.
class ChipRow<T> extends StatelessWidget {
  const ChipRow({super.key, required this.options, required this.value, required this.label, required this.onChanged});
  final List<T> options;
  final T value;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: Sp.sm),
        itemBuilder: (context, i) {
          final o = options[i];
          final on = o == value;
          return Pressable(
            onTap: () => onChanged(o),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: Sp.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? t.text : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: on ? t.text : t.line),
              ),
              child: Text(label(o).toUpperCase(), style: Tx.eyebrow(t, color: on ? t.ground : t.textMuted)),
            ),
          );
        },
      ),
    );
  }
}
