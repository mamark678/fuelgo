import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/route_observer.dart';

class OwnerLoginScreen extends StatefulWidget {
  const OwnerLoginScreen({Key? key}) : super(key: key);

  @override
  State<OwnerLoginScreen> createState() => _OwnerLoginScreenState();
}

class _OwnerLoginScreenState extends State<OwnerLoginScreen> with RouteAware {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _error;

  void _debugLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    print('🔧 [$timestamp] OWNER LOGIN: $message');
  }

  @override

  void initState() {
    super.initState();
    _emailController.clear();
    _passwordController.clear();
    _error = null;
    _debugLog('Owner login screen initialized');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _resetForm();
  }

  void _resetForm() {
    _emailController.clear();
    _passwordController.clear();
    setState(() {
      _error = null;
      _isLoading = false;
      _isGoogleLoading = false;
    });
    _debugLog('Form reset');
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _debugLog('🚀 Starting email login for: ${_emailController.text.trim()}');

    try {
      final user = await AuthService().loginOwner(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      _debugLog('✅ Email login result: ${user != null ? 'SUCCESS' : 'FAILED - user is null'}');

      if (user != null) {
        _debugLog('👤 User UID: ${user.uid}');
        _debugLog('📧 User email: ${user.email}');
        _debugLog('🎭 User displayName: ${user.displayName}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You Successfully Logged In'),
              duration: Duration(seconds: 1),
            ),
          );
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            _debugLog('🎯 Navigating to owner dashboard');
            Navigator.pushReplacementNamed(context, '/owner-dashboard');
            _debugLog('➡️ Navigation pushed: /owner-dashboard');
          }
        }
      }
    } on Exception catch (e) {
      _debugLog('❌ Email login exception: ${e.toString()}');
      _debugLog('🔍 Exception type: ${e.runtimeType}');

      String errorMsg = 'Login failed.';
      final errorStr = e.toString();
      if (errorStr.contains('user-not-found')) {
        errorMsg = 'No account found for this email.';
      } else if (errorStr.contains('wrong-password')) {
        errorMsg = 'Incorrect password. Please try again.';
      } else if (errorStr.contains('Access denied')) {
        errorMsg = 'Access denied. This account is not registered as a gas station owner.';
      }
      setState(() {
        _error = errorMsg;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });

    _debugLog('=== 🚀 STARTING GOOGLE SIGN-IN (OWNER) ===');
    _debugLog('👤 Current Firebase user: ${FirebaseAuth.instance.currentUser?.email ?? 'none'}');

    try {
      _debugLog('📞 Calling AuthService().signInWithGoogleAsOwner()');

      final result = await AuthService().signInWithGoogleAsOwner();

      _debugLog('📦 Google sign-in result: ${result != null ? 'NOT NULL' : 'NULL'}');

      if (result != null) {
        _debugLog('🔑 Result keys: ${result.keys.toList()}');

        final bool isNewUser = result['isNewUser'] as bool;
        final userData = result['userData'] as Map<String, dynamic>?;
        final credential = result['credential'];

        // 🎯 ADD THESE DEBUG LOGS HERE:
        _debugLog('🔍 isNewUser value: $isNewUser');
        _debugLog('📊 Full result object: $result');
        
        _debugLog('👶 isNewUser: $isNewUser');
        _debugLog('📝 userData: ${userData != null ? 'present' : 'null'}');
        if (userData != null) {
          _debugLog('📧 userData email: ${userData['email']}');
          _debugLog('👤 userData name: ${userData['name']}');
        }
        _debugLog('🎫 credential: ${credential != null ? credential.runtimeType.toString() : 'null'}');

        if (isNewUser) {
          _debugLog('✨ New owner detected - navigating to owner verification');
          if (mounted) {
            Navigator.pushReplacementNamed(
              context,
              '/owner-verification',
              arguments: {
                'email': userData?['email'] ?? '',
                'password': null,
                'name': userData?['name'] ?? '',
                'photoURL': userData?['photoURL'],
                'isGoogleUser': true,
                'credential': credential,
              },
            );
            _debugLog('➡️ Navigation pushed: /owner-verification');
          }
        } else {
  _debugLog('🎉 Existing owner - checking document status');
  final user = result['user'] as User?;
  if (user != null && mounted) {
    try {
      // Check if documents are submitted
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      final documentsSubmitted = userDoc.data()?['documentsSubmitted'] as bool? ?? false;
      
      if (!documentsSubmitted) {
        _debugLog('📄 Documents not submitted - redirecting to document upload');
        // Existing user but documents not submitted
        Navigator.pushReplacementNamed(context, '/owner-document-upload', arguments: {
          'userId': user.uid,
          'name': userDoc.data()?['name'] ?? '',
          'email': user.email ?? '',
        });
        _debugLog('➡️ Navigation pushed: /owner-document-upload');
      } else {
        _debugLog('✅ Documents submitted - going to dashboard');
        // Normal dashboard flow
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Welcome back!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
        Navigator.pushReplacementNamed(context, '/owner-dashboard');
        _debugLog('➡️ Navigation pushed: /owner-dashboard');
      }
    } catch (e) {
      _debugLog('❌ Error checking document status: $e');
      // Fallback to dashboard
      Navigator.pushReplacementNamed(context, '/owner-dashboard');
    }
  }
}
      } else {
        _debugLog('🚫 Google sign-in returned null - user likely cancelled');
      }
    } catch (e, stackTrace) {
      _debugLog('💥 GOOGLE SIGN-IN ERROR:');
      _debugLog('❌ Error: ${e.toString()}');
      _debugLog('🔍 Error type: ${e.runtimeType}');
      _debugLog('📚 Stack trace: ${stackTrace.toString()}');

      if (e is FirebaseAuthException) {
        _debugLog('🔥 FirebaseAuthException code: ${e.code}');
        _debugLog('🔥 FirebaseAuthException message: ${e.message}');
      }

      String errorMsg = 'Google sign-in failed.';
      final errorStr = e.toString();

      _debugLog('🔍 Checking error string: $errorStr');

      if (errorStr.contains('Access denied')) {
        errorMsg = 'Access denied. This Google account is not registered as a gas station owner.';
        _debugLog('🎯 Matched: Access denied error');
      } else if (errorStr.contains('pending admin approval')) {
        errorMsg = 'Your owner account is pending admin approval. Please wait for approval before signing in.';
        _debugLog('🎯 Matched: Pending approval error');
      } else if (errorStr.contains('not been approved')) {
        errorMsg = 'Your owner account has not been approved. Please contact admin for assistance.';
        _debugLog('🎯 Matched: Not approved error');
      } else if (errorStr.contains('account-exists-with-different-credential')) {
        errorMsg = 'An account already exists with this email using a different sign-in method.';
        _debugLog('🎯 Matched: Different credential error');
      } else if (errorStr.contains('network')) {
        errorMsg = 'Network error. Please check your internet connection and try again.';
        _debugLog('🎯 Matched: Network error');
      } else if (errorStr.contains('sign_in_canceled') || errorStr.contains('cancelled')) {
        errorMsg = 'Google sign-in was cancelled.';
        _debugLog('🎯 Matched: Sign-in cancelled');
      } else {
        _debugLog('❓ No specific error match found - using generic message');
        errorMsg = 'Google sign-in failed: ${e.toString()}';
      }

      setState(() {
        _error = errorMsg;
      });
    } finally {
      setState(() {
        _isGoogleLoading = false;
      });
      _debugLog('=== ✅ GOOGLE SIGN-IN COMPLETED ===');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Login'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/role-selection');
              },
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              label: const Text('Role'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/fuelgo1.png', height: 250, fit: BoxFit.contain),
                const SizedBox(height: 2),
                const Text(
                  'We Bring Customers to You',
                  style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.grey),
                ),
                const SizedBox(height: 2),
                const Text('Fuel-GO!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'E-Mail',
                    hintText: 'Enter your email',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  validator: (value) => value == null || value.isEmpty ? 'Enter your email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter your password',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  obscureText: true,
                  validator: (value) => value == null || value.isEmpty ? 'Enter your password' : null,
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red.shade600, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        child: const Text('Login with Email'),
                      ),
                const SizedBox(height: 16),
                const Text(
                  'OR',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                _isGoogleLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        onPressed: _signInWithGoogle,
                        icon: Image.asset(
                          'assets/google_logo.png',
                          height: 24,
                          width: 24,
                        ),
                        label: const Text('Continue with Google'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          side: const BorderSide(color: Colors.grey),
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/forgot-password');
                  },
                  child: const Text('Forgot Password?'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/owner-signup');
                  },
                  child: const Text("Don't have an account? Sign Up as Owner"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
