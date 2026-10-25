import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../auth/auth_service.dart';
import '../../core/theme/app_colors.dart';

enum _Mode { signIn, createAccount }

/// The first screen until someone signs in. Google is one tap; email works
/// for anyone.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _mode = _Mode.signIn;
  var _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  AuthService get _auth => ref.read(authServiceProvider);

  Future<void> _attempt(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() => _attempt(() async {
    await _auth.signInWithGoogle();
  });

  Future<void> _submitEmail() async {
    if (!_form.currentState!.validate()) return;
    await _attempt(
      () => _mode == _Mode.signIn
          ? _auth.signInWithEmail(_email.text, _password.text)
          : _auth.createAccount(
              name: _name.text,
              email: _email.text,
              password: _password.text,
            ),
    );
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = 'Enter your email address first, then tap Forgot password.';
        _notice = null;
      });
      return;
    }
    await _attempt(() async {
      await _auth.sendPasswordReset(email);
      if (mounted) {
        setState(() => _notice = 'Password reset link sent to $email.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final creating = _mode == _Mode.createAccount;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.sports_cricket, size: 48, color: colors.runs),
                    const SizedBox(height: 12),
                    Text('CricScore', style: text.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in to keep your matches safe and share live scores.',
                      style: text.bodyMedium?.copyWith(color: colors.muted),
                    ),
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      key: const Key('google'),
                      onPressed: _busy ? null : _google,
                      icon: const Icon(Icons.login),
                      label: const Text('Continue with Google'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        foregroundColor: colors.foreground,
                        side: BorderSide(color: colors.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: Divider(color: colors.line)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or with email',
                            style: text.bodySmall?.copyWith(
                              color: colors.muted,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: colors.line)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (creating) ...[
                      TextFormField(
                        key: const Key('name'),
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Enter your name.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      key: const Key('email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) => (v ?? '').trim().contains('@')
                          ? null
                          : 'Enter your email address.',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('password'),
                      controller: _password,
                      obscureText: true,
                      autofillHints: [
                        if (creating)
                          AutofillHints.newPassword
                        else
                          AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: creating ? 'At least 6 characters' : null,
                      ),
                      validator: (v) => (v ?? '').length < 6
                          ? 'Use at least 6 characters.'
                          : null,
                      onFieldSubmitted: (_) => _submitEmail(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        key: const Key('error'),
                        style: text.bodyMedium?.copyWith(color: colors.wicket),
                      ),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _notice!,
                        style: text.bodyMedium?.copyWith(color: colors.runs),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('submit'),
                      onPressed: _busy ? null : _submitEmail,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(creating ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 8),
                    // Wraps onto two lines on narrow screens or large text.
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _mode = creating
                                      ? _Mode.signIn
                                      : _Mode.createAccount;
                                  _error = null;
                                }),
                          child: Text(
                            creating
                                ? 'I have an account'
                                : 'Create an account',
                          ),
                        ),
                        if (!creating)
                          TextButton(
                            onPressed: _busy ? null : _resetPassword,
                            child: const Text('Forgot password?'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
