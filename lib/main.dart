import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/owner_verification_screen.dart';
import 'home_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/login_screen.dart';
import 'screens/owner_dashboard_screen.dart';
import 'screens/owner_document_upload_screen.dart' show OwnerDocumentUploadScreen;
import 'screens/owner_login_screen.dart';
import 'screens/owner_signup_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/verification_screen.dart';
import 'services/email_processor_service.dart';
import 'services/notification_service.dart';

// Custom theme extension for gradients
class GradientTheme extends ThemeExtension<GradientTheme> {
  final LinearGradient primaryGradient;
  final LinearGradient secondaryGradient;
  final LinearGradient backgroundGradient;

  const GradientTheme({
    required this.primaryGradient,
    required this.secondaryGradient,
    required this.backgroundGradient,
  });

  @override
  ThemeExtension<GradientTheme> copyWith({
    LinearGradient? primaryGradient,
    LinearGradient? secondaryGradient,
    LinearGradient? backgroundGradient,
  }) {
    return GradientTheme(
      primaryGradient: primaryGradient ?? this.primaryGradient,
      secondaryGradient: secondaryGradient ?? this.secondaryGradient,
      backgroundGradient: backgroundGradient ?? this.backgroundGradient,
    );
  }

  @override
  ThemeExtension<GradientTheme> lerp(
    covariant ThemeExtension<GradientTheme>? other,
    double t,
  ) {
    if (other is! GradientTheme) {
      return this;
    }
    return GradientTheme(
      primaryGradient: LinearGradient.lerp(primaryGradient, other.primaryGradient, t)!,
      secondaryGradient: LinearGradient.lerp(secondaryGradient, other.secondaryGradient, t)!,
      backgroundGradient: LinearGradient.lerp(backgroundGradient, other.backgroundGradient, t)!,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('==== Fuel-GO! Application Starting ====');

  try {
    await Firebase.initializeApp();
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
    // Continue anyway - app should still work without Firebase initially
  }

  // Initialize notification service in background
  if (!kIsWeb) {
    _initializeServicesInBackground();
  }

  runApp(const MyApp());
}

// Move heavy initialization to background to prevent blocking main thread
void _initializeServicesInBackground() async {
  // Use microtasks to prevent blocking the main thread
  scheduleMicrotask(() async {
    try {
      await NotificationService().initialize();
      debugPrint('NotificationService initialized');
    } catch (e) {
      debugPrint('NotificationService initialization error: $e');
    }
  });

  // Start email monitoring with delay to not block startup
  scheduleMicrotask(() {
    _startEmailMonitoring();
  });
}

// Fixed email monitoring to run in background
void _startEmailMonitoring() {
  debugPrint('Starting email monitoring service for admin replies...');

  // Add initial delay to prevent startup blocking
  Timer(const Duration(seconds: 30), () async {
    try {
      // Run initial check in background
      await _processEmailsInBackground();
      debugPrint('Initial email check completed');
    } catch (e) {
      debugPrint('Error running initial email check: $e');
    }
  });

  // Schedule periodic checks
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    try {
      await _processEmailsInBackground();
      debugPrint('Scheduled email check completed at ${DateTime.now()}');
    } catch (e) {
      debugPrint('Error during scheduled email check: $e');
    }
  });
}

// Run email processing in background to prevent UI blocking
Future<void> _processEmailsInBackground() async {
  try {
    // Use compute to run in separate isolate if it's CPU intensive
    // If EmailProcessorService.processAdminReplies() is already async and lightweight,
    // just await it directly
    await EmailProcessorService.processAdminReplies();
  } catch (e) {
    debugPrint('Background email processing error: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fuel-GO!',
      theme: ThemeData(
        primaryColor: Colors.orange.shade800,
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: Colors.orange.shade600,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.orange.shade700,
          foregroundColor: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.orange.shade50,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            foregroundColor: Colors.white,
          ),
        ),
        extensions: [
          GradientTheme(
            primaryGradient: LinearGradient(
              colors: [Colors.orange.shade800, Colors.orange.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            secondaryGradient: LinearGradient(
              colors: [Colors.orange.shade600, Colors.orange.shade300],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            backgroundGradient: LinearGradient(
              colors: [Colors.orange.shade50, Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ],
      ),
      home: kIsWeb
          ? Scaffold(
              appBar: AppBar(title: const Text('Fuel-GO! (Web Preview)')),
              body: const Center(
                child: Text(
                  'Map preview only works on iOS/Android.\n'
                  'Please run on an emulator/device.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : const AuthWrapper(),
      routes: {
        '/role-selection': (context) => const StatefulRoleSelectionScreen(),
        '/login': (context) => const StatefulLoginScreen(),
        '/signup': (context) => const StatefulSignupScreen(),
        '/verification': (context) => const StatefulVerificationScreen(),
        '/forgot-password': (context) => const StatefulForgotPasswordScreen(),
        '/home': (context) => const StatefulHomeScreen(),
        '/owner-login': (context) => const StatefulOwnerLoginScreen(),
        '/owner-signup': (context) => const StatefulOwnerSignupScreen(),
        '/owner-dashboard': (context) => const StatefulOwnerDashboardScreen(),
        '/analytics': (context) => const AnalyticsScreen(),
        '/owner-verification': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return StatefulScreenWrapper(
            routeName: '/owner-verification',
            child: OwnerVerificationScreen(
              email: args?['email'] as String? ?? '',
              password: args?['password'] as String?,
              name: args?['name'] as String? ?? '',
              photoURL: args?['photoURL'] as String?,
              isGoogleUser: args?['isGoogleUser'] as bool? ?? false,
              credential: args?['credential'] as AuthCredential?,
            ),
          );
        },
        '/owner-document-upload': (context) {
          return const StatefulOwnerDocumentUploadScreen();
        },
      },
    );
  }
}

class StatefulOwnerDocumentUploadScreen extends StatelessWidget {
  const StatefulOwnerDocumentUploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;

    final userId = args?['userId'] as String? ?? '';
    final name = args?['name'] as String? ?? '';
    final email = args?['email'] as String? ?? '';

    return StatefulScreenWrapper(
      routeName: '/owner-document-upload',
      child: OwnerDocumentUploadScreen(
        userId: userId,
        name: name,
        email: email,
      ),
    );
  }
}

// Completely rewritten AuthWrapper for better performance
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool _isLoading = true;
  Widget? _initialScreen;
  Timer? _timeoutTimer;
  bool _hasInitialized = false;
  
  // Add this to prevent multiple simultaneous auth checks
  bool _isCheckingAuth = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[AuthWrapper] initState called');
    
    // Use post frame callback to ensure widget tree is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasInitialized && !_isCheckingAuth) {
        _hasInitialized = true;
        _performAuthCheck();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeoutTimer?.cancel();
    super.dispose();
  }

  // Optimized auth check with better error handling
  Future<void> _performAuthCheck() async {
    if (_isCheckingAuth || !mounted) return;
    
    _isCheckingAuth = true;
    
    // Set a reasonable timeout
    _timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isLoading) {
        debugPrint('Auth check timeout - defaulting to role selection');
        _setInitialScreen(const StatefulRoleSelectionScreen());
      }
    });

    try {
      debugPrint('Starting optimized auth check...');
      
      // Step 1: Quick Firebase Auth check (usually cached)
      User? firebaseUser;
      try {
        firebaseUser = FirebaseAuth.instance.currentUser;
        debugPrint('Firebase user: ${firebaseUser?.uid ?? 'null'}');
      } catch (e) {
        debugPrint('Firebase Auth error: $e');
        _setInitialScreen(const StatefulRoleSelectionScreen());
        return;
      }

      Widget targetScreen;

      if (firebaseUser != null) {
        // User is authenticated - determine appropriate screen
        targetScreen = await _getAuthenticatedUserScreen(firebaseUser);
      } else {
        // User is not authenticated
        targetScreen = await _getUnauthenticatedUserScreen();
      }

      debugPrint('Auth check completed successfully');
      _setInitialScreen(targetScreen);

    } catch (e, stackTrace) {
      debugPrint('Auth check error: $e');
      debugPrint('Stack trace: $stackTrace');
      _setInitialScreen(const StatefulRoleSelectionScreen());
    } finally {
      _isCheckingAuth = false;
    }
  }

  // Separate method for authenticated user flow
  Future<Widget> _getAuthenticatedUserScreen(User user) async {
    try {
      // First try to get saved route quickly
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      final savedRoute = prefs.getString('last_route');
      
      if (savedRoute != null && _isValidAuthenticatedRoute(savedRoute)) {
        debugPrint('Using saved authenticated route: $savedRoute');
        return _getScreenFromRoute(savedRoute);
      }

      // If no valid saved route, get user role from Firestore
      debugPrint('Getting user role from Firestore...');
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 5));

      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final userRole = userData['role'] ?? 'customer';
        debugPrint('User role: $userRole');
        
        return userRole == 'owner' 
            ? const StatefulOwnerDashboardScreen()
            : const StatefulHomeScreen();
      } else {
        debugPrint('User doc not found - defaulting to home');
        return const StatefulHomeScreen();
      }
    } catch (e) {
      debugPrint('Error getting authenticated user screen: $e');
      // Default to home for authenticated users if there's an error
      return const StatefulHomeScreen();
    }
  }

  // Separate method for unauthenticated user flow
  Future<Widget> _getUnauthenticatedUserScreen() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      final savedRoute = prefs.getString('last_route');
      
      if (savedRoute != null && _isValidUnauthenticatedRoute(savedRoute)) {
        debugPrint('Using saved unauthenticated route: $savedRoute');
        return _getScreenFromRoute(savedRoute);
      }
    } catch (e) {
      debugPrint('Error getting saved route for unauthenticated user: $e');
    }
    
    debugPrint('Defaulting to role selection');
    return const StatefulRoleSelectionScreen();
  }

  void _setInitialScreen(Widget screen) {
    if (!mounted) return;

    _timeoutTimer?.cancel();
    
    // Use microtask to ensure this doesn't block the current execution
    scheduleMicrotask(() {
      if (mounted && _isLoading) {
        setState(() {
          _initialScreen = screen;
          _isLoading = false;
        });
        debugPrint('[AuthWrapper] Initial screen set successfully');
      }
    });
  }

  bool _isValidAuthenticatedRoute(String route) {
    const authenticatedRoutes = [
      '/home',
      '/owner-dashboard',
      '/price-management',
    ];
    return authenticatedRoutes.contains(route);
  }

  bool _isValidUnauthenticatedRoute(String route) {
    const unauthenticatedRoutes = [
      '/role-selection',
      '/login',
      '/signup',
      '/forgot-password',
      '/owner-login',
      '/owner-signup',
    ];
    return unauthenticatedRoutes.contains(route);
  }

  Widget _getScreenFromRoute(String route) {
    switch (route) {
      case '/role-selection':
        return const StatefulRoleSelectionScreen();
      case '/login':
        return const StatefulLoginScreen();
      case '/signup':
        return const StatefulSignupScreen();
      case '/forgot-password':
        return const StatefulForgotPasswordScreen();
      case '/home':
        return const StatefulHomeScreen();
      case '/owner-login':
        return const StatefulOwnerLoginScreen();
      case '/owner-signup':
        return const StatefulOwnerSignupScreen();
      case '/owner-dashboard':
        return const StatefulOwnerDashboardScreen();
      default:
        return const StatefulRoleSelectionScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Loading Fuel-GO!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please wait...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _initialScreen ?? const StatefulRoleSelectionScreen();
  }
}

// Simplified wrapper for all screens
class StatefulScreenWrapper extends StatelessWidget {
  final Widget child;
  final String routeName;

  const StatefulScreenWrapper({
    Key? key,
    required this.child,
    required this.routeName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

// Wrapper classes for each screen
class StatefulRoleSelectionScreen extends StatelessWidget {
  const StatefulRoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatefulScreenWrapper(
      routeName: '/role-selection',
      child: RoleSelectionScreen(),
    );
  }
}

class StatefulLoginScreen extends StatelessWidget {
  const StatefulLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatefulScreenWrapper(
      routeName: '/login',
      child: LoginScreen(),
    );
  }
}

class StatefulSignupScreen extends StatelessWidget {
  const StatefulSignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return StatefulScreenWrapper(
      routeName: '/signup',
      child: SignupScreen(
        prefillName: args?['name'] as String?,
        prefillEmail: args?['email'] as String?,
        prefillPhotoURL: args?['photoURL'] as String?,
      ),
    );
  }
}

class StatefulForgotPasswordScreen extends StatelessWidget {
  const StatefulForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatefulScreenWrapper(
      routeName: '/forgot-password',
      child: ForgotPasswordScreen(),
    );
  }
}

class StatefulHomeScreen extends StatelessWidget {
  const StatefulHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatefulScreenWrapper(
      routeName: '/home',
      child: HomeScreen(),
    );
  }
}

class StatefulOwnerLoginScreen extends StatelessWidget {
  const StatefulOwnerLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatefulScreenWrapper(
      routeName: '/owner-login',
      child: OwnerLoginScreen(),
    );
  }
}

class StatefulOwnerSignupScreen extends StatelessWidget {
  const StatefulOwnerSignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    return StatefulScreenWrapper(
      routeName: '/owner-signup',
      child: OwnerSignupScreen(
        prefillName: args?['name'],
        prefillEmail: args?['email'],
        prefillPhotoURL: args?['photoURL'],
      ),
    );
  }
}

class StatefulOwnerDashboardScreen extends StatelessWidget {
  const StatefulOwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StatefulScreenWrapper(
      routeName: '/owner-dashboard',
      child: OwnerDashboardScreen(),
    );
  }
}

class StatefulVerificationScreen extends StatelessWidget {
  const StatefulVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    return StatefulScreenWrapper(
      routeName: '/verification',
      child: VerificationScreen(
        email: args?['email'] as String? ?? '',
        password: args?['password'] as String?,
        name: args?['name'] as String? ?? '',
        photoURL: args?['photoURL'] as String?,
        isGoogleUser: args?['isGoogleUser'] as bool? ?? false,
        credential: args?['credential'] as AuthCredential?,
      ),
    );
  }
}