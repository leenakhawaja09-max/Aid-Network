import 'dart:io';

/// Rewrites host for Android emulator: `localhost` / `127.0.0.1` → `10.0.2.2`.
///
/// Use for any **local** HTTP API during development (not Supabase cloud URLs).
String emulatorSafeHost(String host) {
  if (!Platform.isAndroid) return host;
  if (host == 'localhost' || host == '127.0.0.1') return '10.0.2.2';
  return host;
}

Uri emulatorSafeUri(Uri uri) {
  final h = uri.host;
  if (h != 'localhost' && h != '127.0.0.1') return uri;
  return uri.replace(host: emulatorSafeHost(h));
}
