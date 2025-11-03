import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/route_observer.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with RouteAware {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isEntering = true; // <-- new: show loading overlay while entering
  String? _error;

  void _resetState() {
    setState(() {
      _emailController.clear();
      _passwordController.clear();
      _error = null;
      _isLoading = false;
      _isGoogleLoading = false;
    });
  }

  /// Called when the route is pushed or when returning to this screen
  void _startEntering() {
    // show entering loader and reset state
    setState(() {
      _isEntering = true;
    });

    // reset fields immediately
    _resetState();

    // hide overlay after a short delay (adjust as needed)
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
  void didPush() {
    _startEntering();
  }

  @override
  void didPopNext() {
    _startEntering();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);

    // Run the entering loader when dependencies change (first build)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startEntering();
    });
  }

  @override
  void initState() {
    super.initState();
    // ensure we start in entering state briefly (in case route observer not yet active)
    _startEntering();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = await AuthService().loginCustomer(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (user != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You Successfully Logged In'),
              duration: Duration(seconds: 1),
              backgroundColor: Colors.green,
            ),
          );
          await Future.delayed(const Duration(seconds: 1));
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } on Exception catch (e) {
      String errorMsg = 'Login failed.';
      final errorStr = e.toString();
      if (errorStr.contains('user-not-found')) {
        errorMsg = 'No account found for this email.';
      } else if (errorStr.contains('wrong-password')) {
        errorMsg = 'Incorrect password. Please try again.';
      } else if (errorStr.contains('Access denied')) {
        errorMsg = errorStr.contains('gas station owner')
            ? 'This account is registered as a gas station owner. Please use the Owner Login instead.'
            : 'Access denied. Please check your account type.';
      } else if (errorStr.contains('Exception:')) {
        errorMsg = errorStr.split('Exception:')[1].trim();
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
      final result = await AuthService().signInWithGoogleAsCustomer();

      if (result != null) {
        final bool isNewUser = result['isNewUser'] as bool;

        if (isNewUser) {
          final userData = result['userData'] as Map<String, dynamic>?;
          final credential = result['credential'];

          if (mounted) {
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
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Welcome back!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 1),
              ),
            );

            await Future.delayed(const Duration(seconds: 1));
            Navigator.pushReplacementNamed(context, '/home');
          }
        }
      }
    } catch (e) {
      String errorMsg = 'Google sign-in failed.';
      final errorStr = e.toString();
      
      if (errorStr.contains('Access denied')) {
        errorMsg = errorStr.contains('gas station owner')
            ? 'This Google account is registered as a gas station owner. Please use the Owner Login instead.'
            : 'Access denied. Please check your account type.';
      } else if (errorStr.contains('network')) {
        errorMsg = 'Network error. Please check your internet connection and try again.';
      } else {
        errorMsg = errorStr.contains('Exception:')
            ? errorStr.split('Exception:')[1].trim()
            : 'Google sign-in failed. Please try again.';
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
    // if entering OR performing any auth action, absorb inputs
    final bool absorb = _isEntering || _isLoading || _isGoogleLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to Fuel-GO!'),
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
                      Padding(
                        padding: const EdgeInsets.only(bottom: 15.0),
                        child: Column(
                          children: [
                            Image.asset('assets/fuelgo1.png', height: 250, fit: BoxFit.contain),
                            const SizedBox(height: 2),
                            const Text(
                              'Fuel-Up Your Convenience',
                              style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.grey),
                            ),
                            const SizedBox(height: 2),
                            const Text('Fuel-GO!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
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
                        Text(_error!, style: const TextStyle(color: Colors.red)),
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
                          Navigator.pushReplacementNamed(context, '/signup');
                        },
                        child: const Text("Don't have an account? Sign Up"),
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
