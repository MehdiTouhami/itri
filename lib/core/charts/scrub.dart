import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Turns a horizontal drag / long-press / tap into a 0–1 position, and
/// null on release. Several charts listen to one of these to stay in sync.
class ScrubArea extends StatelessWidget {
  const ScrubArea({super.key, required this.position, required this.child, this.sticky = false});

  final ValueNotifier<double?> position;
  final Widget child;

  /// Keep the last position after release (useful on summary charts).
  final bool sticky;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      void set(Offset local) {
        final f = (local.dx / box.maxWidth).clamp(0.0, 1.0);
        if (position.value == null) HapticFeedback.selectionClick();
        position.value = f;
      }

      void clear() {
        if (!sticky) position.value = null;
      }

      return RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
            HorizontalDragGestureRecognizer.new,
            (r) => r
              ..onStart = ((d) => set(d.localPosition))
              ..onUpdate = ((d) => set(d.localPosition))
              ..onEnd = ((_) => clear())
              ..onCancel = clear,
          ),
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 180)),
            (r) => r
              ..onLongPressStart = ((d) => set(d.localPosition))
              ..onLongPressMoveUpdate = ((d) => set(d.localPosition))
              ..onLongPressEnd = ((_) => clear()),
          ),
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (r) => r..onTapUp = ((d) {
                  set(d.localPosition);
                  final v = position.value;
                  // Clear a tap's readout after a moment, unless a drag took over.
                  Future<void>.delayed(const Duration(milliseconds: 1600), () {
                    if (position.value == v) clear();
                  });
                }),
          ),
        },
        child: child,
      );
    });
  }
}

/// Maps a 0–1 scrub position onto an index into a list of [length] items.
int scrubIndex(double f, int length) => (f * (length - 1)).round().clamp(0, length - 1);
