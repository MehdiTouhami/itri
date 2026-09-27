import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/type.dart';
import '../../core/widgets/primitives.dart';

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: context.tk.gold),
            ),
            const SizedBox(height: Sp.md),
            const Eyebrow('Reading sessions'),
          ],
        ),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState(this.error, {super.key});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final t = context.tk;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sessions could not be loaded', style: Tx.heading(t)),
            const SizedBox(height: Sp.sm),
            Text('$error', style: Tx.small(t), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
