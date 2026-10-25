import 'package:cric_score/app/app.dart';
import 'package:cric_score/core/theme/app_colors.dart';
import 'package:cric_score/core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: CricScoreApp()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on the home screen', (tester) async {
    await pumpApp(tester);

    expect(find.text('CricScore'), findsOneWidget);
    expect(find.text('No matches yet'), findsOneWidget);
    expect(find.text('New match'), findsOneWidget);
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
