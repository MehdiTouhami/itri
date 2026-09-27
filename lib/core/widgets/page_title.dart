import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';
import '../theme/type.dart';
import 'primitives.dart';

/// Tab-page header: eyebrow line, optional tag, profile button, big title.
class PageTitle extends StatelessWidget {
  const PageTitle({super.key, required this.eyebrow, required this.title, this.tag, this.tagColor});

  final String eyebrow, title;
  final String? tag;
  final Color? tagColor;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Eyebrow(eyebrow)),
            if (tag != null) ...[
              Eyebrow(tag!, color: tagColor ?? t.textFaint),
              const SizedBox(width: Sp.md),
            ],
            Semantics(
              button: true,
              label: 'Profile and settings',
              child: Pressable(
                onTap: () => context.push('/profile'),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.line)),
                  child: Icon(Icons.person_outline_rounded, size: 16, color: t.textMuted),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.sm),
        Text(title, style: Tx.pageTitle(t)),
      ],
    );
  }
}

/// Back row for pushed pages.
class BackBar extends StatelessWidget {
  const BackBar({super.key, this.icon, this.fallback = '/today'});
  final IconData? icon;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Row(
      children: [
        Pressable(
          onTap: () => context.canPop() ? context.pop() : context.go(fallback),
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
        if (icon != null) Icon(icon, size: 18, color: t.textMuted),
      ],
    );
  }
}
