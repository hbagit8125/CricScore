import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The signed-in person.
@immutable
final class AppUser {
  const AppUser({required this.uid, this.email, this.displayName});

  final String uid;
  final String? email;
  final String? displayName;

  /// What to call them on screen.
  String get label =>
      displayName?.isNotEmpty == true ? displayName! : (email ?? 'Signed in');

  @override
  bool operator ==(Object other) => other is AppUser && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;
}

/// A sign-in problem explained in words the user can act on.
final class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sign-in, kept behind an interface so screens and tests do not depend on
/// Firebase directly.
abstract interface class AuthService {
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  /// Returns false when the person closed the Google window.
  Future<bool> signInWithGoogle();

  Future<void> signInWithEmail(String email, String password);

  Future<void> createAccount({
    required String name,
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}

/// The OAuth "web" client of the Firebase project. Android needs it to get
/// an ID token Firebase accepts. It identifies the app; it is not a secret.
const _googleServerClientId =
    '533039039056-47k51emg7lihtsqrg7dqibq04j6ipajv.apps.googleusercontent.com';

class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;
  Future<void>? _googleReady;

  static AppUser? _toUser(User? u) => u == null
      ? null
      : AppUser(uid: u.uid, email: u.email, displayName: u.displayName);

  @override
  Stream<AppUser?> authStateChanges() => _auth.authStateChanges().map(_toUser);

  @override
  AppUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Future<bool> signInWithGoogle() => _guard(() async {
    if (kIsWeb) {
      await _auth.signInWithPopup(GoogleAuthProvider());
      return true;
    }
    final google = GoogleSignIn.instance;
    _googleReady ??= google.initialize(serverClientId: _googleServerClientId);
    await _googleReady;
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw const AuthException(
        'Google sign-in did not finish. Check your connection and try again.',
      );
    }
    final idToken = account.authentication.idToken;
    await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
    return true;
  });

  @override
  Future<void> signInWithEmail(String email, String password) => _guard(
    () => _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<void> createAccount({
    required String name,
    required String email,
    required String password,
  }) => _guard(() async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user?.updateDisplayName(name.trim());
    await cred.user?.reload();
  });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb && _googleReady != null) {
      await GoogleSignIn.instance.signOut();
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw AuthException(messageFor(e.code));
    }
  }

  /// Plain-language messages for Firebase Auth error codes.
  @visibleForTesting
  static String messageFor(String code) => switch (code) {
    'invalid-email' => 'That email address does not look right.',
    'user-disabled' => 'This account has been switched off.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'The email or password is not right.',
    'email-already-in-use' =>
      'An account already uses this email. Sign in instead.',
    'weak-password' => 'Use a password of at least 6 characters.',
    'too-many-requests' =>
      'Too many attempts. Wait a few minutes and try again.',
    'network-request-failed' =>
      'No internet connection. Connect and try again.',
    'popup-closed-by-user' || 'cancelled-popup-request' =>
      'The Google window was closed before signing in.',
    'account-exists-with-different-credential' =>
      'This email is already used with another sign-in method.',
    _ => 'Sign-in did not work. Please try again.',
  };
}
