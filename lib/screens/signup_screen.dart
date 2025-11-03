// lib/screens/signup_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/route_observer.dart';

class SignupScreen extends StatefulWidget {
  final String? prefillName;
  final String? prefillEmail;
  final String? prefillPhotoURL;

  const SignupScreen({Key? key, this.prefillName, this.prefillEmail, this.prefillPhotoURL}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> with RouteAware {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _emailController;
  final TextEditingController _createPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isEntering = true; // <-- new
  String? _error;

  void _resetState() {
    setState(() {
      _fullNameController.text = widget.prefillName ?? '';
      _emailController.text = widget.prefillEmail ?? '';
      _createPasswordController.clear();
      _confirmPasswordController.clear();
      _error = null;
      _isLoading = false;
      _isGoogleLoading = false;
    });
  }

  void _startEntering() {
    setState(() {
      _isEntering = true;
    });

    // Reset fields immediately
    _resetState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _isEntering = false;
          });
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);

    // Reset state every time this screen is entered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startEntering();
    });
  }

  @override
  void didPush() {
    _startEntering();
  }

  @override
  void didPopNext() {
    _startEntering();
  }

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.prefillName ?? '');
    _emailController = TextEditingController(text: widget.prefillEmail ?? '');
    _createPasswordController.clear();
    _confirmPasswordController.clear();
    _error = null;
    _isLoading = false;
    _isGoogleLoading = false;

    // start entering briefly
    _startEntering();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _fullNameController.dispose();
    _emailController.dispose();
    _createPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_createPasswordController.text != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    final email = _emailController.text.trim();
    final password = _createPasswordController.text.trim();
    final name = _fullNameController.text.trim();

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Pre-check if email exists (non-blocking - if it fails due to rate limits, proceed anyway)
      try {
        final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
        if (methods.isNotEmpty) {
          String suggestion = 'This email is already registered.';
          if (methods.contains('google.com')) {
            suggestion = 'This email is already registered with Google. Please sign in with Google or reset your password.';
          } else if (methods.contains('password')) {
            suggestion = 'This email is already registered. Please login or use "Forgot Password".';
          } else {
            suggestion = 'This email is already registered with another sign-in method: ${methods.join(', ')}';
          }
          setState(() {
            _error = suggestion;
          });
          return;
        }
      } on FirebaseAuthException catch (e) {
        // If fetchSignInMethodsForEmail fails due to rate limits, skip the check and proceed
        // The actual signup will handle duplicate email errors properly
        if (e.code == 'too-many-requests') {
          print('Warning: fetchSignInMethodsForEmail rate limited, proceeding with signup anyway');
          // Continue to signup - it will handle duplicate email if account exists
        } else {
          // Re-throw other FirebaseAuthExceptions from fetchSignInMethodsForEmail
          rethrow;
        }
      }

      User? user = await AuthService().signUp(
        email: email,
        password: password,
        name: name,
      );

      if (user == null) {
        setState(() {
          _error = 'Failed to create user account.';
        });
        return;
      }

      // Note: Email verification is already sent in AuthService().signUp()
      // No need to call sendEmailVerification() again here

      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/verification',
        arguments: {
          'email': email,
          'password': null,
          'name': name,
          'isGoogleUser': false,
          'photoURL': null,
          'credential': null,
        },
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'Failed to create account.';
      if (e.code == 'invalid-email') {
        msg = 'Invalid email address.';
      } else if (e.code == 'too-many-requests') {
        // If we get too-many-requests during account creation, the account might have been created
        // Check if we can sign in to verify account exists
        try {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          // If sign-in succeeds, account was created - navigate to verification
          await FirebaseAuth.instance.signOut(); // Sign out immediately
          if (mounted) {
            Navigator.pushReplacementNamed(
              context,
              '/verification',
              arguments: {
                'email': email,
                'password': null,
                'name': name,
                'isGoogleUser': false,
                'photoURL': null,
                'credential': null,
              },
            );
            return;
          }
        } catch (_) {
          // Sign-in failed, account probably wasn't created
          msg = 'Too many attempts. Please wait a moment and try again.';
        }
      } else if (e.code == 'email-already-in-use') {
        msg = 'This email is already registered. Please login or use "Forgot Password".';
      }
      setState(() {
        _error = msg;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to create account.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signUpWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });

    try {
      final result = await AuthService().signInWithGoogleAsCustomer();

      if (result == null) return;

      final bool isNewUser = result['isNewUser'] as bool;

      if (mounted) {
        if (isNewUser) {
          final userData = result['userData'] as Map<String, dynamic>?;
          final credential = result['credential'];

          Navigator.pushReplacementNamed(
            context,
            '/verification',
            arguments: {
              'email': userData?['email'] ?? '',
              'password': null,
              'name': userData?['name'] ?? '',
              'photoURL': userData?['photoURL'],
              'isGoogleUser': true,
              'credential': credential,
            },
          );
        } else {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Account Already Exists'),
              content: const Text('An account with this Google account already exists. Please sign in instead.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                  child: const Text('Go to Login'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Google sign-up failed. Please try again.';
      });
    } finally {
      setState(() {
        _isGoogleLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool absorb = _isEntering || _isLoading || _isGoogleLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign-Up for Fuel-GO'),
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
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AbsorbPointer(
                absorbing: absorb,
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/fuelgo1.png', height: 120, fit: BoxFit.contain),
                      const SizedBox(height: 16),
                      _isGoogleLoading
                          ? const CircularProgressIndicator()
                          : ElevatedButton.icon(
                              onPressed: _signUpWithGoogle,
                              icon: Image.asset(
                                'assets/google_logo.png',
                                height: 24,
                                width: 24,
                              ),
                              label: const Text('Sign up with Google'),
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
                      const Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('OR', style: TextStyle(color: Colors.grey)),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _fullNameController,
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          hintText: 'Enter your full name',
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        validator: (value) => value == null || value.isEmpty ? 'Enter your full name' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'Enter your email',
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter your email';
                          }
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _createPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Create Password',
                          hintText: 'Enter your password',
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter your password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          hintText: 'Confirm your password',
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (value != _createPasswordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
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
                        const SizedBox(height: 16),
                      ],
                      _isLoading
                          ? const CircularProgressIndicator()
                          : ElevatedButton(
                              onPressed: _signup,
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                              ),
                              child: const Text('Sign Up with Email'),
                            ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          Navigator.pushReplacementNamed(context, '/login');
                        },
                        child: const Text('Already have an account? Login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Full-screen non-interactive loading overlay while entering
          if (_isEntering)
            const Positioned.fill(
              child: ColoredBox(
                color: Color.fromARGB(120, 0, 0, 0),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
