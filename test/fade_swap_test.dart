import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itri_fitness/core/widgets/primitives.dart';

// Regression: a bare AnimatedSwitcher throws "Duplicate keys found" when a
// value returns before its old copy has faded out (seen on the mode switch).
void main() {
  Widget at(String s, {bool ticking = true}) => MaterialApp(
        home: TickerMode(enabled: ticking, child: FadeSwap(child: Text(s, key: ValueKey(s)))),
      );

  Future<void> flip(WidgetTester tester, {required bool ticking}) async {
    for (final s in ['A', 'B', 'A', 'B', 'A']) {
      await tester.pumpWidget(at(s, ticking: ticking));
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets('a value returning mid-fade does not duplicate keys', (tester) async {
    await flip(tester, ticking: true);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);
  });

  testWidgets('still safe while fades are frozen offstage', (tester) async {
    await flip(tester, ticking: false);
    expect(tester.takeException(), isNull);
    expect(find.text('A'), findsOneWidget);
  });
}
