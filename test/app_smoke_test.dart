import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itri_fitness/data/garmin/garmin_bundle.dart';
import 'package:itri_fitness/data/intervals/live_store.dart';
import 'package:itri_fitness/main.dart';
import 'package:itri_fitness/state/providers.dart';

void main() {
  testWidgets('boots into Today and switches tabs', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    // Pin to sample data so the test never depends on a private export.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        garminBundleProvider.overrideWith((ref) => const AsyncData<GarminBundle?>(null)),
        intervalsKeyStoreProvider.overrideWith((ref) => MemoryKeyStore()),
        liveFileProvider.overrideWith((ref) => MemoryLiveFile()),
        coachConsentStoreProvider.overrideWith((ref) => MemoryKeyStore()),
      ],
      child: const ItriFitnessApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('TODAY'), findsWidgets); // page title + tab label
    expect(find.text('Fitness & fatigue'.toUpperCase()), findsOneWidget);

    await tester.tap(find.text('LOG').last);
    await tester.pumpAndSettle();
    expect(find.text('ALL'), findsOneWidget);

    await tester.tap(find.text('SPORTS').last);
    await tester.pumpAndSettle();
    expect(find.text('Where your time goes'.toUpperCase()), findsOneWidget);

    // Coach: nothing can be sent until the notice is accepted.
    await tester.tap(find.text('COACH').last);
    await tester.pumpAndSettle();
    expect(find.text('I UNDERSTAND'), findsOneWidget);
    await tester.tap(find.text('I UNDERSTAND'));
    await tester.pumpAndSettle();
    expect(find.text('Try asking'.toUpperCase()), findsOneWidget);

    // Profile moved to the header button.
    await tester.tap(find.byIcon(Icons.person_outline_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('Max HR'), findsOneWidget);
    await tester.tap(find.text('BACK'));
    await tester.pumpAndSettle();

    // The switch swaps tabs and palette; from Today it lands on Recovery.
    await tester.tap(find.text('TODAY').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TRAINING'));
    await tester.pumpAndSettle();
    expect(find.text('READINESS'), findsOneWidget);
    expect(find.text('NIGHTS'), findsWidgets);

    await tester.tap(find.text('NIGHTS').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TRENDS').last);
    await tester.pumpAndSettle();
    expect(find.text('OVER TIME'), findsOneWidget);

    await tester.tap(find.text('RECOVERY').last);
    await tester.pumpAndSettle();
    expect(find.text('TODAY'), findsWidgets); // back to Training
  });
}
