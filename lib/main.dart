import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'dart:async';
import 'app_theme.dart';
import 'screens/email_verification_screen.dart';
import 'screens/tracking_screen.dart';
import 'screens/messages_list_screen.dart';
import 'screens/requests_screen.dart';
import 'screens/map_help_home_screen.dart';
import 'widgets/pitch_bottom_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/auth_config.dart';
import 'services/auth_email.dart';
import 'utils/app_user.dart';
import 'utils/geo_utils.dart';
import 'utils/request_expiry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web: do not sync routes to the browser history stack (avoids Chrome
  // "session history item marked skippable" on load). No-op on mobile/desktop.
  setUrlStrategy(null);

  // Session is stored on device until the user taps Log out (secure storage on Android).
  await Supabase.initialize(
    url: 'https://bturoqldvwpdmxxmxgdu.supabase.co',
    anonKey: 'sb_publishable_9BrVAcL7q6OQSrEGwvhySA_wlJd4Dfi',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      detectSessionInUri: true,
    ),
  );

  runApp(const RapidAidApp());
}

final supabase = Supabase.instance.client;
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class RapidAidApp extends StatefulWidget {
  const RapidAidApp({super.key});

  @override
  State<RapidAidApp> createState() => _RapidAidAppState();
}

class _RapidAidAppState extends State<RapidAidApp> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user?.emailConfirmedAt == null) return;
      if (data.event != AuthChangeEvent.signedIn &&
          data.event != AuthChangeEvent.tokenRefreshed &&
          data.event != AuthChangeEvent.userUpdated) {
        return;
      }
      if (!mounted) return;
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Email confirmed — you are signed in.'),
          backgroundColor: Colors.green,
        ),
      );
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _rootNavigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'RapidAid',
      debugShowCheckedModeBanner: false,
      theme: buildRapidAidTheme(),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session =
              snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
          if (snapshot.connectionState == ConnectionState.waiting && session == null) {
            return const SplashScreen();
          }
          if (session == null) {
            return const LoginScreen();
          }
          final user = session.user;
          if (user.emailConfirmedAt == null) {
            return EmailVerificationScreen(
              email: user.email ?? '',
              userName: (user.userMetadata?['full_name'] as String?)?.trim().isNotEmpty == true
                  ? user.userMetadata!['full_name'] as String
                  : 'Member',
            );
          }
          return const DashboardScreen();
        },
      ),
    );
  }
}

// --- 1. SPLASH SCREEN (Keep your existing code) ---
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppBranding.authBackground),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                ),
                child: Column(
                  children: [
                    Text(
                      'CAN',
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                        height: 1,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Community Aid Network',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- 2. LOGIN SCREEN (Keep your existing code) ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  Future<void> _tryLogin() async {
    if (_formKey.currentState!.validate()) {
      final email = _emailController.text.trim();
      try {
        await supabase.auth.signInWithPassword(
          email: email,
          password: _passController.text.trim(),
        );
      } on AuthException catch (e) {
        if (!mounted) return;
        final msg = e.message.toLowerCase();
        if (msg.contains('email not confirmed') || msg.contains('not verified')) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EmailVerificationScreen(
                email: email,
                userName: 'Member',
              ),
            ),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppBranding.authBackground),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Material(
              elevation: 16,
              shadowColor: Colors.black.withValues(alpha: 0.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              color: scheme.surfaceContainerLowest,
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Text(
                          'CAN',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: scheme.primary,
                                letterSpacing: 1,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Community Aid Network',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 28),
                  _buildValidatedField(
                    context,
                    'Email',
                    'Enter your email',
                    _emailController,
                    fieldKey: 'login_email',
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: 15),
                  _buildValidatedField(
                    context,
                    'Password',
                    'Enter your password',
                    _passController,
                    isPass: true,
                    fieldKey: 'login_password',
                    autofillHints: const [AutofillHints.password],
                  ),
                  const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _tryLogin,
                            child: const Text('Sign in'),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Don't have an account?",
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const RegisterScreen()),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Text(
                                  'Create one',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
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
        ),
      ),
    );
  }
}

// --- 3. REGISTRATION SCREEN (REPLACED WITH ROBUST LOGIC) ---
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _regFormKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleSignUp() async {
    if (_regFormKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final email = _emailController.text.trim();
        final pass = _passController.text.trim();
        final name = _nameController.text.trim();

        final res = await supabase.auth.signUp(
          email: email,
          password: pass,
          data: {'full_name': name},
          emailRedirectTo: kAuthRedirectUrl,
        );

        if (isDuplicateSignupUser(res.user)) {
          try {
            await sendSignupVerificationEmail(email);
          } on AuthException catch (resendErr) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'This email is already registered. ${resendErr.message}\n\n'
                  ,
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 8),
              ),
            );
            return;
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Account already exists — we sent another verification email. '
                  'Check spam.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 8),
              ),
            );
          }
        }

        final uid = res.user?.id;
        if (uid != null) {
          try {
            await supabase.from('profiles').upsert({
              'id': uid,
              'full_name': name,
              'helps_count': 0,
              'karma_points': 0,
              'rating': 5.0,
              'skills': [],
            });
          } catch (supabaseError) {
            debugPrint("Supabase profile upsert: $supabaseError");
          }
        }

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => EmailVerificationScreen(
                email: email,
                userName: name,
              ),
            ),
            (route) => false,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Check your email for a 6-digit verification code.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } on AuthException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(e.message),
                backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppBranding.authBackground),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Material(
                  elevation: 16,
                  shadowColor: Colors.black.withValues(alpha: 0.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  color: scheme.surfaceContainerLowest,
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                      child: Form(
                        key: _regFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Create account',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Join neighbors helping neighbors.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            const SizedBox(height: 22),
                          _buildValidatedField(
                            context,
                            'Full name',
                            'Your name',
                            _nameController,
                            fieldKey: 'signup_name',
                            autofillHints: const [AutofillHints.name],
                          ),
                          const SizedBox(height: 14),
                          _buildValidatedField(
                            context,
                            'Email',
                            'you@example.com',
                            _emailController,
                            fieldKey: 'signup_email',
                            autofillHints: const [AutofillHints.email],
                          ),
                          const SizedBox(height: 14),
                          _buildValidatedField(
                            context,
                            'Password',
                            'Create a strong password',
                            _passController,
                            isPass: true,
                            fieldKey: 'signup_password',
                            autofillHints: const [AutofillHints.newPassword],
                          ),
                            const SizedBox(height: 26),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                onPressed: _isLoading ? null : _handleSignUp,
                                child: _isLoading
                                    ? SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          color: scheme.onPrimary,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Continue'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 4. DASHBOARD SCREEN ---
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  String activeMissionType = "none";
  String? _activeRequestId;
  String _partnerName = "Helper";
  String? _lastHelperAcceptedPitchId;
  String? _lastAwaitingAckPitchId;
  final Set<String> _skippedStaleAcceptedPitch = {};
  StreamSubscription<List<Map<String, dynamic>>>? _helperPitchSub;

  @override
  void initState() {
    super.initState();
    _subscribeHelperAcceptedPitches();
    _purgeExpiredRequests();
  }

  Future<void> _purgeExpiredRequests() async {
    try {
      await supabase.rpc('purge_expired_requests');
    } catch (e) {
      debugPrint('purge_expired_requests: $e');
    }
  }

  @override
  void dispose() {
    _helperPitchSub?.cancel();
    super.dispose();
  }

  void _subscribeHelperAcceptedPitches() {
    final uid = currentUserId();
    if (uid == null) return;
    _helperPitchSub = supabase.from('pitches').stream(primaryKey: ['id']).eq('helper_id', uid).listen(
      (rows) {
      if (!mounted) return;
      for (final r in rows) {
        final st = r['status']?.toString() ?? '';
        final pid = r['id']?.toString();
        if (pid == null) continue;
        if (st == 'awaiting_helper_ack' && pid != _lastAwaitingAckPitchId) {
          _lastAwaitingAckPitchId = pid;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
              'A requester chose you — open Requests → I\'m Helping and tap “Confirm I will assist” to share locations.',
            ),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ));
        }
      }
      for (final r in rows) {
        if (r['status']?.toString() != 'accepted') continue;
        final pid = r['id']?.toString();
        final rid = r['request_id']?.toString();
        if (pid == null || rid == null || pid == _lastHelperAcceptedPitchId) continue;
        if (_skippedStaleAcceptedPitch.contains(pid)) continue;
        _onHelperMissionAccepted(rid, pid);
      }
    },
      onError: (Object e) => debugPrint('pitches realtime: $e'),
    );
  }

  Future<void> _onHelperMissionAccepted(String requestId, String pitchId) async {
    if (pitchId == _lastHelperAcceptedPitchId || _skippedStaleAcceptedPitch.contains(pitchId)) return;
    try {
      final req = await supabase.from('requests').select('status').eq('id', requestId).maybeSingle();
      final s = req?['status']?.toString().toLowerCase() ?? '';
      if (s != 'in-progress' &&
          s != 'in_progress' &&
          s != 'accepted' &&
          s != 'helper_selected' &&
          s != 'arriving') {
        _skippedStaleAcceptedPitch.add(pitchId);
        return;
      }
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (pitchId == _lastHelperAcceptedPitchId) return;
    _lastHelperAcceptedPitchId = pitchId;
    setState(() {
      activeMissionType = 'assisting';
      _activeRequestId = requestId;
      _partnerName = 'Requester';
      _currentIndex = 2;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Mission is live — tracking and location updates are enabled.'),
      backgroundColor: Theme.of(context).colorScheme.primary,
    ));
  }

  Stream<List<Map<String, dynamic>>> getRequests() {
    // Return a realtime stream of all requests (no status filter)
    // ordered by `created_at` descending so newest appear first.
    return supabase
        .from('requests')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) {
          final rid = _activeRequestId;
          return List<Map<String, dynamic>>.from(data)
              .where((r) => isRequestVisibleForDiscovery(r, exceptRequestId: rid))
              .toList();
        })
        .handleError((Object e) => debugPrint('requests realtime: $e'));
  }

  void clearMission() => setState(() {
        activeMissionType = "none";
        _activeRequestId = null;
        _partnerName = "Helper";
        _lastHelperAcceptedPitchId = null;
        _lastAwaitingAckPitchId = null;
        _skippedStaleAcceptedPitch.clear();
        _currentIndex = 0;
      });

  void handleMissionAccepted(String type, String second, [String third = ""]) {
    setState(() {
      activeMissionType = type;
      if (type == "receiving") {
        _partnerName = second.isNotEmpty ? second : "Helper";
        _activeRequestId = third.isNotEmpty ? third : null;
        _currentIndex = 2;
      } else if (type == "assisting") {
        _partnerName = second.isNotEmpty ? second : "Requester";
        _activeRequestId = third.isNotEmpty ? third : null;
        _currentIndex = 2;
      } else if (type == "none") {
        _partnerName = "Helper";
        _activeRequestId = null;
      }
    });
    if (!mounted) return;
    if (type == "receiving") {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Help is on the way from $_partnerName!"),
          backgroundColor: Theme.of(context).colorScheme.primary));
    } else if (type == "assisting") {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Assisting $_partnerName!"),
          backgroundColor: Theme.of(context).colorScheme.primary));
    }
  }

  Future<void> addNewRequest(
      String category, String description, String distance) async {
    try {
      final uid = currentUserId();
      if (uid == null) return;
      Map<String, dynamic>? prof;
      try {
        prof = await supabase.from('profiles').select('full_name,latitude,longitude').eq('id', uid).maybeSingle();
      } catch (_) {}
      final lat = readCoord(prof?['latitude']);
      final lng = readCoord(prof?['longitude']);
      final insert = <String, dynamic>{
        'title': description.isNotEmpty ? description : "New $category Request",
        'description': description,
        'category': category,
        'distance': distance,
        'status': 'open',
        'user_id': uid,
        'userName': prof?['full_name']?.toString() ?? 'User',
        'current_radius': double.tryParse(distance.split(' ').first) ?? 5.0,
      };
      if (lat != null && lng != null) {
        insert['latitude'] = lat;
        insert['longitude'] = lng;
      }
      await supabase.from('requests').insert(insert);
      if (mounted) {
        setState(() => _currentIndex = 1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Error adding request: $e"),
            backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: getRequests(),
      builder: (context, snapshot) {
        final requests = snapshot.data ?? [];
        final uid = currentUserId();
        final myRequests = uid == null
            ? <Map<String, dynamic>>[]
            : requests
                .where((r) => r['user_id']?.toString() == uid)
                .toList();

        final List<Widget> screens = [
          MapHelpHomeScreen(
            globalRequests: requests,
            activeMissionType: activeMissionType,
            activeRequestId: _activeRequestId,
            onOfferHelp: (req) {
              PitchBottomSheet.show(
                context,
                requestId: req['id'].toString(),
                requestOwnerId: req['user_id']?.toString() ?? '',
              );
            },
            // CreateRequestSheet already inserts into Supabase; only switch tab here.
            onAfterRequestPosted: () {
              if (mounted) setState(() => _currentIndex = 1);
            },
            onViewTracking: () => setState(() => _currentIndex = 2),
          ),
          RequestsScreen(
              onActionAccepted: (type, arg2, arg3) {
                if (type == "receiving" || type == "assisting") {
                  handleMissionAccepted(type, arg2, arg3);
                } else if (type == "none") {
                  clearMission();
                } else {
                  addNewRequest(type, arg2, arg3);
                }
              },
              userRequests: myRequests),
          TrackingScreen(
              missionType: activeMissionType,
              requestId: _activeRequestId,
              partnerName: _partnerName,
              onMissionComplete: clearMission),
          const MessagesListScreen(),
        ];

        return Scaffold(
          extendBody: true,
          body: IndexedStack(index: _currentIndex, children: screens),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) => setState(() => _currentIndex = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map_rounded),
                label: 'Map',
              ),
              NavigationDestination(
                icon: Icon(Icons.assignment_outlined),
                selectedIcon: Icon(Icons.assignment_rounded),
                label: 'Requests',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore_rounded),
                label: 'Tracking',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_rounded),
                label: 'Chat',
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- SHARED UI HELPERS ---
Widget _buildValidatedField(
  BuildContext context,
  String label,
  String hint,
  TextEditingController controller, {
  bool isPass = false,
  String? fieldKey,
  Iterable<String>? autofillHints,
}) {
  final theme = Theme.of(context);
  final id = fieldKey ?? label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ) ??
            const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Semantics(
        identifier: id,
        label: label,
        textField: true,
        child: TextFormField(
          key: ValueKey(id),
          controller: controller,
          obscureText: isPass,
          autofillHints: autofillHints,
          validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
          decoration: InputDecoration(hintText: hint).applyDefaults(theme.inputDecorationTheme),
        ),
      ),
    ],
  );
}
