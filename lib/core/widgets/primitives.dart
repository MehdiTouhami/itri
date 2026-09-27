import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/type.dart';

/// Mono uppercase label that opens a section.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: Tx.eyebrow(context.tk, color: color));
}

/// Section opener: eyebrow on the left, optional detail on the right,
/// sitting on a hairline. Sections are separated by rules, not boxes.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.trailing});
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Padding(
      padding: const EdgeInsets.only(top: Sp.xxl, bottom: Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 1, color: t.line),
          const SizedBox(height: Sp.md),
          Row(
            children: [
              Expanded(child: Eyebrow(label)),
              if (trailing != null)
                Flexible(
                  child: Text(
                    trailing!,
                    textAlign: TextAlign.right,
                    style: Tx.data(t, size: 11, color: t.textFaint),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Label above a large condensed number with a small unit.
class Readout extends StatelessWidget {
  const Readout({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.size = 28,
    this.color,
  });

  final String label;
  final String value;
  final String? unit;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Eyebrow(label),
        const SizedBox(height: Sp.sm),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: value, style: Tx.numeral(t, size: size, color: color)),
            if (unit != null) TextSpan(text: ' $unit', style: Tx.data(t, size: 11, color: t.textMuted)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
        ),
      ],
    );
  }
}

/// Lays readouts out in equal columns with hairline dividers between rows.
class ReadoutGrid extends StatelessWidget {
  const ReadoutGrid({super.key, required this.children, this.columns = 3});
  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.sublist(i, (i + columns).clamp(0, children.length));
      if (i > 0) rows.add(Container(height: 1, color: context.tk.line, margin: const EdgeInsets.symmetric(vertical: Sp.lg)));
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var j = 0; j < columns; j++)
            Expanded(child: j < slice.length ? slice[j] : const SizedBox.shrink()),
        ],
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// Subtle press feedback (scale + dim) instead of a Material ripple.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: _down ? 0.6 : 1,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: _down ? 0.985 : 1,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A thin stacked bar of time in each HR zone.
class ZoneStrip extends StatelessWidget {
  const ZoneStrip(this.seconds, {super.key, this.height = 3});
  final List<int> seconds;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    final total = seconds.fold<int>(0, (a, b) => a + b);
    if (total == 0) return SizedBox(height: height);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var i = 0; i < seconds.length; i++)
              if (seconds[i] > 0)
                Expanded(flex: seconds[i], child: ColoredBox(color: t.zones[i])),
          ],
        ),
      ),
    );
  }
}

/// Standard horizontal page padding.
class Gutter extends StatelessWidget {
  const Gutter({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: Sp.gutter), child: child);
}

/// Cross-fades when [child]'s key changes. Unlike a bare AnimatedSwitcher it
/// survives a key coming back mid-fade (fast chart scrubbing, or fades frozen
/// while a tab sits offstage): only one copy per key is ever laid out.
class FadeSwap extends StatelessWidget {
  const FadeSwap({super.key, required this.child, this.duration = const Duration(milliseconds: 180)});
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: duration,
        layoutBuilder: (current, previous) {
          final seen = <Key?>{current?.key};
          return Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [
              for (final p in previous)
                if (seen.add(p.key)) p,
              ?current,
            ],
          );
        },
        child: child,
      );
}
