import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../widgets/animated_button.dart';
import '../widgets/animated_card.dart';
import '../widgets/fade_in_widget.dart';
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

  @override
  void initState() {
    super.initState();
    _emailController.clear();
    _passwordController.clear();
    _error = null;
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
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = await AuthService().loginOwner(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (user != null) {
        if (mounted) {
          // Check verification status and route accordingly
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
            
            final approvalStatus = userDoc.data()?['approvalStatus'] as String? ?? '';
            final documentsSubmitted = userDoc.data()?['documentsSubmitted'] as bool? ?? false;
            final emailVerified = userDoc.data()?['emailVerified'] as bool? ?? false;
            final authProvider = userDoc.data()?['authProvider'] as String? ?? 'email';
            
            // Check if verification process is incomplete
            bool needsVerification = false;
            String? redirectRoute;
            Map<String, dynamic>? redirectArgs;
            
            // Check if email verification is needed (for email users only)
            if (authProvider == 'email' && !emailVerified) {
              needsVerification = true;
              redirectRoute = '/owner-verification';
              redirectArgs = {
                'email': user.email ?? '',
                'password': null,
                'name': userDoc.data()?['name'] ?? '',
                'isGoogleUser': false,
                'photoURL': null,
                'credential': null,
              };
            }
            // Check if documents need to be submitted
            else if (approvalStatus == null || approvalStatus.isEmpty) {
              needsVerification = true;
              redirectRoute = '/owner-document-upload';
              redirectArgs = {
                'userId': user.uid,
                'name': userDoc.data()?['name'] ?? '',
                'email': user.email ?? '',
              };
            } else if (!documentsSubmitted && approvalStatus != 'pending') {
              needsVerification = true;
              redirectRoute = '/owner-document-upload';
              redirectArgs = {
                'userId': user.uid,
                'name': userDoc.data()?['name'] ?? '',
                'email': user.email ?? '',
              };
            }
            
            // Show incomplete verification dialog if needed
            if (needsVerification && mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  title: const Text('Incomplete Verification'),
                  content: const Text(
                    'You haven\'t finished your verification as a gas station owner. Please click here to continue.',
                    textAlign: TextAlign.center,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (redirectRoute != null) {
                          Navigator.pushReplacementNamed(context, redirectRoute!, arguments: redirectArgs);
                        }
                      },
                      child: const Text('Continue Verification'),
                    ),
                  ],
                ),
              );
              return; // Don't proceed with normal login flow
            }
            
            // Normal routing for complete verification
            if (approvalStatus == 'rejected') {
              if (mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => AlertDialog(
                    title: const Text('Registration Rejected'),
                    content: Text(
                      userDoc.data()?['rejectionReason'] != null
                          ? 'Your registration has been rejected.\n\nReason: ${userDoc.data()?['rejectionReason']}\n\nPlease review your documents and try again by signing up.'
                          : 'Your registration has been rejected. Please review your documents and try again by signing up.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          AuthService().signOut();
                          Navigator.pushReplacementNamed(context, '/owner-signup');
                        },
                        child: const Text('Go to Sign Up'),
                      ),
                    ],
                  ),
                );
              }
            } else if (approvalStatus == 'request_submission' || !documentsSubmitted) {
              Navigator.pushReplacementNamed(context, '/owner-document-upload', arguments: {
                'userId': user.uid,
                'name': userDoc.data()?['name'] ?? '',
                'email': user.email ?? '',
              });
            } else if (approvalStatus == 'approved') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('You Successfully Logged In!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 1),
                ),
              );
              await Future.delayed(const Duration(seconds: 1));
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/owner-dashboard');
              }
            } else if (approvalStatus == 'pending') {
              Navigator.pushReplacementNamed(context, '/owner-waiting-approval');
            } else {
              Navigator.pushReplacementNamed(context, '/owner-waiting-approval');
            }
          } catch (e) {
            Navigator.pushReplacementNamed(context, '/owner-waiting-approval');
          }
        }
      }
    } on Exception catch (e) {
      String errorMsg = 'Login failed.';
      final errorStr = e.toString();
      if (errorStr.contains('user-not-found')) {
        errorMsg = 'Cannot Access: No account found for this email. Please sign up first.';
      } else if (errorStr.contains('wrong-password')) {
        errorMsg = 'Incorrect password. Please try again.';
      } else if (errorStr.contains('Access denied')) {
        errorMsg = 'Access denied. This account is not registered as a gas station owner.';
      } else if (errorStr.contains('Cannot Access')) {
        errorMsg = errorStr;
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

    try {
      final result = await AuthService().signInWithGoogleAsOwner();

      if (result != null) {
        final bool isNewUser = result['isNewUser'] as bool;
        final userData = result['userData'] as Map<String, dynamic>?;
        final credential = result['credential'];

        if (isNewUser) {
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
          }
        } else {
          // Existing owner - check approval status and document status
          final user = result['user'] as User?;
          if (user != null && mounted) {
            try {
              // Get user document to check both approval status and document status
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get();
              
              final approvalStatus = userDoc.data()?['approvalStatus'] as String? ?? '';
              final documentsSubmitted = userDoc.data()?['documentsSubmitted'] as bool? ?? false;
              final emailVerified = userDoc.data()?['emailVerified'] as bool? ?? false;
              final authProvider = userDoc.data()?['authProvider'] as String? ?? 'google';
              
              // Check if verification process is incomplete
              bool needsVerification = false;
              String? redirectRoute;
              Map<String, dynamic>? redirectArgs;
              
              // Check if email verification is needed (for email users only)
              if (authProvider == 'email' && !emailVerified) {
                needsVerification = true;
                redirectRoute = '/owner-verification';
                redirectArgs = {
                  'email': user.email ?? '',
                  'password': null,
                  'name': userDoc.data()?['name'] ?? '',
                  'isGoogleUser': false,
                  'photoURL': null,
                  'credential': null,
                };
              }
              // Check if documents need to be submitted
              else if (approvalStatus == null || approvalStatus.isEmpty) {
                needsVerification = true;
                redirectRoute = '/owner-document-upload';
                redirectArgs = {
                  'userId': user.uid,
                  'name': userDoc.data()?['name'] ?? '',
                  'email': user.email ?? '',
                };
              } else if (!documentsSubmitted && approvalStatus != 'pending') {
                needsVerification = true;
                redirectRoute = '/owner-document-upload';
                redirectArgs = {
                  'userId': user.uid,
                  'name': userDoc.data()?['name'] ?? '',
                  'email': user.email ?? '',
                };
              }
              
              // Show incomplete verification dialog if needed
              if (needsVerification && mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => AlertDialog(
                    title: const Text('Incomplete Verification'),
                    content: const Text(
                      'You haven\'t finished your verification as a gas station owner. Please click here to continue.',
                      textAlign: TextAlign.center,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          if (redirectRoute != null) {
                            Navigator.pushReplacementNamed(context, redirectRoute!, arguments: redirectArgs);
                          }
                        },
                        child: const Text('Continue Verification'),
                      ),
                    ],
                  ),
                );
                return; // Don't proceed with normal login flow
              }
              
              // Handle different approval statuses
              if (approvalStatus == 'rejected') {
                if (mounted) {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => AlertDialog(
                      title: const Text('Registration Rejected'),
                      content: Text(
                        userDoc.data()?['rejectionReason'] != null
                            ? 'Your registration has been rejected.\n\nReason: ${userDoc.data()?['rejectionReason']}\n\nPlease review your documents and try again by signing up.'
                            : 'Your registration has been rejected. Please review your documents and try again by signing up.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            AuthService().signOut();
                            Navigator.pushReplacementNamed(context, '/owner-signup');
                          },
                          child: const Text('Go to Sign Up'),
                        ),
                      ],
                    ),
                  );
                }
              } else if (approvalStatus == 'request_submission' || !documentsSubmitted) {
                Navigator.pushReplacementNamed(context, '/owner-document-upload', arguments: {
                  'userId': user.uid,
                  'name': userDoc.data()?['name'] ?? '',
                  'email': user.email ?? '',
                });
              } else if (approvalStatus == 'approved') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('You Successfully Logged In!'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 1),
                  ),
                );
                await Future.delayed(const Duration(seconds: 1));
                Navigator.pushReplacementNamed(context, '/owner-dashboard');
              } else if (approvalStatus == 'pending') {
                Navigator.pushReplacementNamed(context, '/owner-waiting-approval');
              } else {
                Navigator.pushReplacementNamed(context, '/owner-waiting-approval');
              }
            } catch (e) {
              Navigator.pushReplacementNamed(context, '/owner-dashboard');
            }
          }
        }
      }
    } catch (e) {
      String errorMsg = 'Google sign-in failed.';
      final errorStr = e.toString();

      if (errorStr.contains('Access denied')) {
        errorMsg = 'Access denied. This Google account is not registered as a gas station owner.';
      } else if (errorStr.contains('pending admin approval')) {
        errorMsg = 'Your owner account is pending admin approval. Please wait for approval before signing in.';
      } else if (errorStr.contains('not been approved')) {
        errorMsg = 'Your owner account has not been approved. Please contact admin for assistance.';
      } else if (errorStr.contains('account-exists-with-different-credential')) {
        errorMsg = 'An account already exists with this email using a different sign-in method.';
      } else if (errorStr.contains('network')) {
        errorMsg = 'Network error. Please check your internet connection and try again.';
      } else if (errorStr.contains('sign_in_canceled') || errorStr.contains('cancelled')) {
        errorMsg = 'Google sign-in was cancelled.';
      } else {
        errorMsg = 'Google sign-in failed: ${e.toString()}';
      }

      setState(() {
        _error = errorMsg;
      });
    } finally {
      setState(() {
        _isGoogleLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradientTheme = theme.extension<GradientTheme>()!;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: gradientTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: FadeInWidget(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            Navigator.pushReplacementNamed(context, '/role-selection');
                          },
                          icon: const Icon(Icons.arrow_back_ios_new),
                          color: theme.primaryColor,
                        ),
                        const Spacer(),
                      ],
                    ),
                    Hero(
                      tag: 'app_logo',
                      child: Image.asset('assets/fuelgo1.png', height: 180, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 24),
                    AnimatedCard(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            Text(
                              'Owner Portal',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Manage your station',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 32),
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'Enter your email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (value) => value == null || value.isEmpty ? 'Enter your email' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                hintText: 'Enter your password',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              obscureText: true,
                              validator: (value) => value == null || value.isEmpty ? 'Enter your password' : null,
                            ),
                            const SizedBox(height: 24),
                            if (_error != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            AnimatedButton(
                              onPressed: _login,
                              isLoading: _isLoading,
                              width: double.infinity,
                              child: const Text('Login as Owner'),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Text('OR', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 16),
                            AnimatedButton(
                              onPressed: _signInWithGoogle,
                              isLoading: _isGoogleLoading,
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black87,
                              width: double.infinity,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    'assets/google_logo.png',
                                    height: 24,
                                    width: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  const Text('Continue with Google'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () {
                                Navigator.pushNamed(context, '/forgot-password');
                              },
                              child: const Text('Forgot Password?'),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text("New Owner?"),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pushReplacementNamed(context, '/owner-signup');
                                  },
                                  child: const Text('Register Station'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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
