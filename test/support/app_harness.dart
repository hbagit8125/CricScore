import 'package:cric_score/app/app.dart';
import 'package:cric_score/auth/auth_providers.dart';
import 'package:cric_score/data/local/app_database.dart';
import 'package:cric_score/data/providers.dart';
import 'package:cric_score/sync/sync_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth.dart';
import 'memory_cloud_store.dart';

/// The whole app on an in-memory database, signed in as [FakeAuthService.testUser].
class AppHarness {
  AppHarness(this.tester) {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }

  final WidgetTester tester;
  final db = AppDatabase(NativeDatabase.memory());
  final auth = FakeAuthService(signedIn: FakeAuthService.testUser);
  final cloud = MemoryCloudStore();

  /// Taps made through [tap], for checking the tap budget.
  int taps = 0;

  Future<void> start({Size size = const Size(420, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          authServiceProvider.overrideWithValue(auth),
          cloudStoreProvider.overrideWithValue(cloud),
        ],
        child: const CricScoreApp(),
      ),
    );
    await settle();
  }

  /// Lets database writes (real async I/O) and animations finish.
  Future<void> settle({int rounds = 3}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// A scorer's tap: scrolls into view, taps, waits for the result.
  Future<void> tap(Finder finder) async {
    expect(finder, findsOneWidget, reason: '$finder');
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    taps++;
    await settle();
  }

  Future<void> tapKey(String key) => tap(find.byKey(Key(key)));

  /// Unmounts and closes the database so no timers are left running.
  Future<void> stop() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  }
}
