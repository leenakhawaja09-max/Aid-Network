import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/auth_config.dart';

/// True when sign-up returned a user but no new account was created (email already in auth).
bool isDuplicateSignupUser(User? user) {
  if (user == null) return false;
  final identities = user.identities;
  return identities == null || identities.isEmpty;
}

/// Sends (or re-sends) the signup confirmation email with OTP / link.
Future<void> sendSignupVerificationEmail(String email) async {
  await Supabase.instance.client.auth.resend(
    type: OtpType.signup,
    email: email.trim(),
    emailRedirectTo: kAuthRedirectUrl,
  );
}
