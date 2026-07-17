import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../services/auth_email.dart';

/// Enter the 6-digit code emailed after sign-up (Supabase Auth → Email → confirm + OTP).
class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final String userName;

  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.userName,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _codeController = TextEditingController();
  bool _verifying = false;
  bool _resending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      _snack('Enter the 6-digit code from your email.', isError: true);
      return;
    }
    setState(() => _verifying = true);
    try {
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.signup,
        email: widget.email.trim(),
        token: code,
      );
      await Supabase.instance.client.auth.refreshSession();
      final user = Supabase.instance.client.auth.currentUser;
      if (user?.emailConfirmedAt != null && mounted) {
        _snack('Email verified — welcome!');
      } else if (mounted) {
        _snack('Code accepted. If the app does not open, tap Verify again.');
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      if (msg.contains('expired') || msg.contains('invalid')) {
        try {
          await Supabase.instance.client.auth.verifyOTP(
            type: OtpType.email,
            email: widget.email.trim(),
            token: code,
          );
          await Supabase.instance.client.auth.refreshSession();
          if (mounted) _snack('Email verified — welcome!', isError: false);
          return;
        } on AuthException catch (_) {}
      }
      _snack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() => _resending = true);
    try {
      await sendSignupVerificationEmail(widget.email);
      if (mounted) {
        _snack(
          'Verification email sent to ${widget.email}. Check spam. '
          'Supabase allows about 4 auth emails per hour.',
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        final msg = e.message.toLowerCase();
        if (msg.contains('already') || msg.contains('registered')) {
          _snack(
            'Email already registered. In Supabase dashboard: Authentication → Users → '
            'delete ${widget.email}, then register again in the app.',
            isError: true,
          );
        } else {
          _snack(e.message, isError: true);
        }
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppBranding.authBackground),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: scheme.onPrimary),
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pop(); // This takes the user back to the previous (login) screen
                    }
                  },
                  tooltip: 'Back to sign in',
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Material(
                    elevation: 12,
                    shadowColor: Colors.black26,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    color: scheme.surfaceContainerLowest,
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(Icons.mark_email_read_rounded, size: 64, color: scheme.primary),
                          const SizedBox(height: 20),
                          Text(
                            'Verify your email',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Hi ${widget.userName}, we sent a 6-digit code to:\n${widget.email}\n\n'
                            'Recommended: type the 6-digit code below.\n\n'
                            'The “Confirm email” button in the mail often shows a blank browser page — '
                            'that is normal. It tries to open this app via a special link. '
                            'It only works on the same phone/emulator where you registered, with the app installed. '
                            'If nothing happens, ignore the link and use the code instead.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.45,
                                ),
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: '000000',
                              filled: true,
                              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 8,
                            ),
                            onSubmitted: (_) => _verifyCode(),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _verifying ? null : _verifyCode,
                              child: _verifying
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Verify code'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No email? Wait 2 minutes, check spam, then tap Resend. ',
                            
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _resending ? null : _resendCode,
                            child: _resending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Resend code'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
