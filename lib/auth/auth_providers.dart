import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

/// Tests override this with a fake.
final authServiceProvider = Provider<AuthService>(
  (ref) => FirebaseAuthService(FirebaseAuth.instance),
);

/// The signed-in person, or null.
final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

/// The signed-in account's id, or null while signed out or loading.
final currentUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).value?.uid,
);
