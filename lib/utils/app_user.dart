import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase Auth user id (UUID string), or null if signed out.
String? currentUserId() => Supabase.instance.client.auth.currentUser?.id;
