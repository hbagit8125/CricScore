import 'package:cric_score/app/app.dart';
import 'package:cric_score/core/theme/app_colors.dart';
import 'package:cric_score/core/theme/app_theme.dart';
import 'package:cric_score/data/local/app_database.dart';
import 'package:cric_score/data/match_repository.dart';
import 'package:cric_score/data/providers.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

late AppDatabase db;

Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const CricScoreApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Unmounts the app so live database queries are cancelled, then lets
/// drift's zero-length cleanup timer run before the test ends.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
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
    await tester.pumpAndSettle();
    expect(
      find.text('Match setup arrives with the new scoring screens.'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
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
    final repo = MatchRepository(db);
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
