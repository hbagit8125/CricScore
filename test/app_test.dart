import 'package:cric_score/app/app.dart';
import 'package:cric_score/auth/auth_providers.dart';
import 'package:cric_score/core/theme/app_colors.dart';
import 'package:cric_score/core/theme/app_theme.dart';
import 'package:cric_score/data/local/app_database.dart';
import 'package:cric_score/data/match_repository.dart';
import 'package:cric_score/data/providers.dart';
import 'package:cric_score/sync/sync_providers.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show Key, SizedBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth.dart';
import 'support/memory_cloud_store.dart';

late AppDatabase db;
late FakeAuthService auth;
late MemoryCloudStore cloud;

Future<void> pumpApp(WidgetTester tester) async {
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
  await settle(tester);
}

/// Lets database and sync work finish; they run on real async I/O.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 700));
  }
}

/// Scrolls [finder] into view and taps it, as a person would.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Unmounts the app so live database queries are cancelled, then lets
/// drift's zero-length cleanup timer run before the test ends.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    auth = FakeAuthService(signedIn: FakeAuthService.testUser);
    cloud = MemoryCloudStore();
  });
  tearDown(() => db.close());

  testWidgets('opens on the home screen', (tester) async {
    await pumpApp(tester);

    expect(find.text('CricScore'), findsOneWidget);
    expect(find.text('No matches yet'), findsOneWidget);
    expect(find.text('New match'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('New match opens match setup and Back returns home', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('New match'));
    await settle(tester);
    expect(find.text('FORMAT'), findsOneWidget);
    expect(find.text('T20'), findsOneWidget);

    await tester.pageBack();
    await settle(tester);
    expect(find.text('No matches yet'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('saved matches are listed, live ones first', (tester) async {
    TeamSheet team(String id, String name) => TeamSheet(
      id: id,
      name: name,
      players: [
        for (var i = 1; i <= 3; i++) PlayerRef(id: '$id$i', name: '$name $i'),
      ],
    );
    final repo = MatchRepository(db, ownerUid: 'u1');
    await tester.runAsync(() async {
      await repo.create(
        MatchSetup(
          rules: MatchRules.custom(overs: 5, playersPerSide: 3),
          teamA: team('L', 'Lions'),
          teamB: team('T', 'Tigers'),
          toss: const Toss(wonByTeamId: 'L', decision: TossDecision.bat),
        ),
      );
    });
    await pumpApp(tester);
    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(find.text('Lions v Tigers'), findsOneWidget);
    expect(find.text('Custom · Not started'), findsOneWidget);
    expect(find.text('No matches yet'), findsNothing);
    await unmountApp(tester);
  });

  group('sign-in', () {
    testWidgets('signed out: the sign-in screen comes first', (tester) async {
      auth = FakeAuthService();
      await pumpApp(tester);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('New match'), findsNothing);
      await unmountApp(tester);
    });

    testWidgets('Google sign-in goes straight to home', (tester) async {
      auth = FakeAuthService();
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('google')));
      await settle(tester);
      expect(find.text('New match'), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('create an account with email, then sign out', (tester) async {
      auth = FakeAuthService();
      await pumpApp(tester);
      await tapVisible(tester, find.text('Create an account'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('name')), 'Ali Raza');
      await tester.enterText(find.byKey(const Key('email')), 'ali@example.com');
      await tester.enterText(find.byKey(const Key('password')), 'secret1');
      await tapVisible(tester, find.byKey(const Key('submit')));
      await settle(tester);
      expect(find.text('New match'), findsOneWidget);

      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(find.text('Ali Raza'), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      expect(find.text('Continue with Google'), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('a wrong password is explained', (tester) async {
      auth = FakeAuthService();
      await pumpApp(tester);
      await tester.enterText(find.byKey(const Key('email')), 'no@example.com');
      await tester.enterText(find.byKey(const Key('password')), 'secret1');
      await tapVisible(tester, find.byKey(const Key('submit')));
      await settle(tester);
      expect(find.text('The email or password is not right.'), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('forgot password sends a reset link', (tester) async {
      auth = FakeAuthService();
      await pumpApp(tester);
      await tapVisible(tester, find.text('Forgot password?'));
      await tester.pump();
      expect(
        find.textContaining('Enter your email address first'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('email')), 'sam@example.com');
      await tapVisible(tester, find.text('Forgot password?'));
      await settle(tester);
      expect(auth.resetRequests, ['sam@example.com']);
      expect(
        find.text('Password reset link sent to sam@example.com.'),
        findsOneWidget,
      );
      await unmountApp(tester);
    });
  });

  testWidgets('a saved match is uploaded to the cloud automatically', (
    tester,
  ) async {
    final repo = MatchRepository(db, ownerUid: 'u1');
    late String id;
    await pumpApp(tester);
    await tester.runAsync(() async {
      id = await repo.create(
        MatchSetup(
          rules: MatchRules.custom(overs: 5, playersPerSide: 3),
          teamA: TeamSheet(
            id: 'L',
            name: 'Lions',
            players: [
              for (var i = 1; i <= 3; i++)
                PlayerRef(id: 'L$i', name: 'Lion $i'),
            ],
          ),
          teamB: TeamSheet(
            id: 'T',
            name: 'Tigers',
            players: [
              for (var i = 1; i <= 3; i++)
                PlayerRef(id: 'T$i', name: 'Tiger $i'),
            ],
          ),
          toss: const Toss(wonByTeamId: 'L', decision: TossDecision.bat),
        ),
      );
    });
    await settle(tester);
    expect(cloud.docs['matches/$id']?['ownerUid'], 'u1');
    expect(cloud.docs['matches/$id']?['title'], 'Lions v Tigers');
    await unmountApp(tester);
  });

  group('theme', () {
    for (final (name, theme, expected) in [
      ('light', AppTheme.light(), AppColors.light),
      ('dark', AppTheme.dark(), AppColors.dark),
    ]) {
      test('$name theme exposes its colour tokens', () {
        final colors = theme.extension<AppColors>();
        expect(colors, isNotNull);
        expect(colors!.background, expected.background);
        expect(theme.scaffoldBackgroundColor, expected.background);
        expect(theme.colorScheme.error, expected.wicket);
      });
    }

    test('uses the bundled fonts', () {
      final theme = AppTheme.dark();
      expect(theme.textTheme.bodyMedium?.fontFamily, AppFonts.body);
      expect(theme.textTheme.displayLarge?.fontFamily, AppFonts.display);
    });
  });
}
