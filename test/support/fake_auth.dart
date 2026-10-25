import 'dart:async';

import 'package:cric_score/auth/auth_service.dart';

/// Sign-in without Firebase. Accounts live in memory.
class FakeAuthService implements AuthService {
  FakeAuthService({AppUser? signedIn}) : _user = signedIn;

  static const testUser = AppUser(
    uid: 'u1',
    email: 'sam@example.com',
    displayName: 'Sam',
  );

  final _changes = StreamController<AppUser?>.broadcast();
  final Map<String, ({String password, AppUser user})> _accounts = {};
  AppUser? _user;
  final List<String> resetRequests = [];

  /// What the next Google sign-in returns; null means the window was
  /// closed.
  AppUser? googleUser = testUser;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  AppUser? get currentUser => _user;

  void _set(AppUser? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  Future<bool> signInWithGoogle() async {
    final g = googleUser;
    if (g == null) return false;
    _set(g);
    return true;
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    final account = _accounts[email.trim()];
    if (account == null || account.password != password) {
      throw const AuthException('The email or password is not right.');
    }
    _set(account.user);
  }

  @override
  Future<void> createAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    if (_accounts.containsKey(email.trim())) {
      throw const AuthException(
        'An account already uses this email. Sign in instead.',
      );
    }
    final user = AppUser(
      uid: 'uid-${_accounts.length + 2}',
      email: email.trim(),
      displayName: name.trim(),
    );
    _accounts[email.trim()] = (password: password, user: user);
    _set(user);
  }

  @override
  Future<void> sendPasswordReset(String email) async =>
      resetRequests.add(email.trim());

  @override
  Future<void> signOut() async => _set(null);
}
