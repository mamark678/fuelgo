import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../widgets/animated_button.dart';
import '../widgets/animated_card.dart';
import '../widgets/fade_in_widget.dart';
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
  bool _isEntering = true;
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

  void _startEntering() {
    setState(() {
      _isEntering = true;
    });

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startEntering();
    });
  }

  @override
  void initState() {
    super.initState();
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
    final theme = Theme.of(context);
    final gradientTheme = theme.extension<GradientTheme>()!;
    final bool absorb = _isEntering || _isLoading || _isGoogleLoading;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: gradientTheme.backgroundGradient,
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: AbsorbPointer(
                    absorbing: absorb,
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
                                    'Welcome Back',
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.primaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Sign in to continue',
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
                                    child: const Text('Login'),
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
                                      const Text("Don't have an account?"),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pushReplacementNamed(context, '/signup');
                                        },
                                        child: const Text('Sign Up'),
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
          ),
          if (_isEntering)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
