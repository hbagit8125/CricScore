# CricScore

Cricket scoring for every format, built on the Laws of Cricket. Android and iOS first, with a web build for previews.

The app is being rebuilt in phases (see `docs/` for the plan). The rebuild lives on the `rebuild` branch; `main` keeps the previous app until the new scoring screens land.

## Project layout

```
lib/                      Flutter app
  app/                    App root and routes (go_router)
  core/theme/             Colour tokens, fonts, light and dark themes
  data/                   On-device storage: drift (SQLite) database, match and team repositories
  features/<feature>/     One folder per screen area
packages/cricket_engine/  Pure Dart scoring engine (no Flutter), tested on its own
assets/fonts/             Barlow and Barlow Condensed (SIL Open Font License)
android/ ios/ web/        Platform projects
.github/workflows/ci.yml  Format, analyze, test, then Android, iOS and web builds
```

The app and engine share one pub workspace, so `flutter pub get` at the root resolves both.

## Running

Requires Flutter 3.47 (stable).

```
flutter pub get
flutter run                 # on a connected device or emulator
flutter run -d chrome       # in a browser
```

## Code generation

The database code in `lib/data/local/app_database.g.dart` is generated. After changing the tables, regenerate it and commit the result:

```
dart run build_runner build --delete-conflicting-outputs --force-jit
```

`--force-jit` avoids a compile step that Windows Application Control blocks on some machines.

The web build stores data in the browser through `web/sqlite3.wasm` and `web/drift_worker.js`, taken from the drift release matching the `drift` version in `pubspec.lock`. Update both files whenever `drift` is upgraded.

## Checks

These are the same checks CI runs on every pull request.

```
dart format --output=none --set-exit-if-changed lib test packages/cricket_engine
flutter analyze
flutter test
cd packages/cricket_engine && dart test
```

## App identifiers

Android `applicationId` and iOS bundle identifier are both `com.cricscore.app`.
