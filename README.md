# CricScore

Cricket scoring for every format, built on the Laws of Cricket. Android and iOS first, with a web build for previews.

The app is being rebuilt in phases (see `docs/` for the plan). The rebuild lives on the `rebuild` branch; `main` keeps the previous app until the new scoring screens land.

## Project layout

```
lib/                      Flutter app
  app/                    App root and routes (go_router)
  core/theme/             Colour tokens, fonts, light and dark themes
  auth/                   Sign-in (Google, email) behind a small interface
  data/                   On-device storage: drift (SQLite) database, match and team repositories
  sync/                   Cloud sync with Firestore
firestore.rules           Who can read and change what in the cloud
firebase/rules-tests/     Tests for those rules, run in the Firestore emulator
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

## Firebase

The app uses the Firebase project `cricscore-a5897` (Firestore in `asia-south1`). `lib/firebase_options.dart` and `android/app/google-services.json` identify the project; they are not secrets.

Deploy security rules after changing `firestore.rules`:

```
firebase deploy --only firestore:rules
```

Test the rules locally (needs Java 21 and Node):

```
npm ci --prefix firebase/rules-tests
firebase emulators:exec --only firestore --project cricscore-rules-test "npm test --prefix firebase/rules-tests"
```

## Android signing

Google sign-in only works in builds signed with the app key, whose SHA-1 and SHA-256 fingerprints are registered in Firebase. The key is never committed.

- Locally, put its details in `android/key.properties` (ignored by git) or point `CRICSCORE_KEY_PROPERTIES` at a file containing `storeFile`, `storePassword`, `keyAlias` and `keyPassword`.
- In GitHub Actions, the secrets `ANDROID_KEYSTORE_BASE64` (the key file, base64-encoded) and `ANDROID_KEYSTORE_PASSWORD` are used. Without them the build falls back to a throwaway key.

Keep a backup of the key: losing it means re-registering fingerprints, and once the app is in the Play Store, it is the upload key.

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
