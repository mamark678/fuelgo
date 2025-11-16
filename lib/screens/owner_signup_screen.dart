import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../widgets/route_observer.dart';
import 'owner_station_map_select_screen.dart';

class OwnerSignupScreen extends StatefulWidget {
  final String? prefillName;
  final String? prefillEmail;
  final String? prefillPhotoURL;

  const OwnerSignupScreen({Key? key, this.prefillName, this.prefillEmail, this.prefillPhotoURL}) : super(key: key);

  @override
  State<OwnerSignupScreen> createState() => _OwnerSignupScreenState();
}

class _OwnerSignupScreenState extends State<OwnerSignupScreen> with RouteAware {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _createPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _error;
  LatLng? _selectedLatLng;
  String? _selectedStationName;

  void _debugLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    print('🔧 [$timestamp] OWNER SIGNUP: $message');
  }

  @override
  void initState() {
    super.initState();
    _fullNameController.text = widget.prefillName ?? '';
    _emailController.text = widget.prefillEmail ?? '';

    _debugLog('Owner signup screen initialized');
    _debugLog('Prefilled name: ${widget.prefillName ?? 'none'}');
    _debugLog('Prefilled email: ${widget.prefillEmail ?? 'none'}');
    _debugLog('Prefilled photo: ${widget.prefillPhotoURL != null ? 'present' : 'none'}');

    if (widget.prefillName == null) _fullNameController.clear();
    if (widget.prefillEmail == null) _emailController.clear();
    _createPasswordController.clear();
    _confirmPasswordController.clear();
    _error = null;
    _selectedLatLng = null;
    _selectedStationName = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _createPasswordController.dispose();
    _confirmPasswordController.dispose();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _resetForm();
  }

  void _resetForm() {
    if (widget.prefillName == null) _fullNameController.clear();
    if (widget.prefillEmail == null) _emailController.clear();
    _createPasswordController.clear();
    _confirmPasswordController.clear();
    setState(() {
      _error = null;
      _isLoading = false;
      _isGoogleLoading = false;
      _selectedLatLng = null;
      _selectedStationName = null;
    });
    _debugLog('Form reset');
  }

  void _selectStationLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const OwnerStationMapSelectScreen(),
      ),
    );
    if (result != null && result is Map) {
      setState(() {
        _selectedStationName = result['stationName'] as String?;
        _selectedLatLng = LatLng(result['lat'], result['lng']);
      });
      _debugLog('Station selected: $_selectedStationName at ${_selectedLatLng?.latitude}, ${_selectedLatLng?.longitude}');
    }
  }

  Future<void> _createGasStation(String userId, String displayName) async {
    _debugLog('Creating gas station for user: $userId');
    final stationId = 'FG${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    _debugLog('Generated station ID: $stationId');

    try {
      // Use station name as address if no specific address is provided
      final address = _selectedStationName ?? 'Location: ${_selectedLatLng!.latitude.toStringAsFixed(6)}, ${_selectedLatLng!.longitude.toStringAsFixed(6)}';
      
      await FirestoreService.createOrUpdateGasStation(
        stationId: stationId,
        name: _selectedStationName!,
        brand: 'Shell',
        position: _selectedLatLng!,
        address: address, // Use station name or coordinates
        prices: const <String, double>{},
        ownerId: userId,
        stationName: _selectedStationName,
      );
      _debugLog('Gas station created successfully');

      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'stationName': _selectedStationName,
        'stationId': stationId,
        'stationLat': _selectedLatLng!.latitude,
        'stationLng': _selectedLatLng!.longitude,
      });
      _debugLog('User document updated with station info');
    } catch (e) {
      _debugLog('❌ Error creating gas station: $e');
      rethrow;
    }
  }

  Future<void> _signup() async {
    _debugLog('=== STARTING EMAIL SIGNUP ===');

    if (!_formKey.currentState!.validate()) {
      _debugLog('❌ Form validation failed');
      return;
    }

    if (_createPasswordController.text != _confirmPasswordController.text) {
      _debugLog('❌ Password mismatch detected');
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    final email = _emailController.text.trim();
    final password = _createPasswordController.text.trim();
    final name = _fullNameController.text.trim();

    _debugLog('📝 Signup data - Email: $email, Name: $name, Password length: ${password.length}');

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // First, check if email already exists in Auth (for rejected users)
      try {
        final signInMethods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);
        if (signInMethods.isNotEmpty) {
          // Email exists in Auth - check if it's a rejected user (no Firestore doc)
          _debugLog('⚠️ Email exists in Auth, checking if rejected user...');
          
          // Try to sign in with the provided password to get the user ID
          try {
            final signInResult = await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
            
            if (signInResult.user != null) {
              final user = signInResult.user!;
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get();
              
              // If no Firestore document exists, this is a rejected user trying to re-register
              if (!userDoc.exists) {
                _debugLog('✅ Rejected user detected - skipping verification, going to document upload');
                
                // Create a minimal Firestore document to mark as pending
                // This replaces any existing document (if any) for rejected users
                await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                  'email': email,
                  'name': name,
                  'role': 'owner',
                  'authProvider': 'email',
                  'emailVerified': true, // Skip verification for rejected users re-registering
                  'approvalStatus': 'pending',
                  'pendingDocuments': true,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                
                if (mounted) {
                  Navigator.pushReplacementNamed(
                    context,
                    '/owner-document-upload',
                    arguments: {
                      'userId': user.uid,
                      'name': name,
                      'email': email,
                      'isGoogleUser': false,
                      'googleCredential': null,
                      'needsPasswordSetup': false,
                    },
                  );
                }
                return;
              } else {
                // Firestore doc exists - regular existing account
                await FirebaseAuth.instance.signOut();
                setState(() {
                  _error = 'This email is already registered. Please login or use "Forgot Password".';
                  _isLoading = false;
                });
                return;
              }
            }
          } on FirebaseAuthException catch (signInError) {
            // Wrong password or other sign-in error
            if (signInError.code == 'wrong-password' || signInError.code == 'invalid-credential') {
              // For rejected users, we need to handle wrong password differently
              // Check if there's no Firestore doc - if so, allow password reset or show helpful message
              try {
                // Try to get user by email (this is a workaround - we'll check Firestore)
                // Since we can't get UID without password, we'll show a helpful error
                setState(() {
                  _error = 'This email is already registered but the password is incorrect.\n\nIf you were previously rejected, please use "Forgot Password" to reset it, or contact support.';
                  _isLoading = false;
                });
              } catch (e) {
                setState(() {
                  _error = 'This email is already registered. Please use the correct password or use "Forgot Password" to reset it.';
                  _isLoading = false;
                });
              }
              return;
            }
            // For other errors, continue with signup attempt
            _debugLog('⚠️ Sign-in failed but continuing: ${signInError.code}');
          }
        }
      } catch (e) {
        // If fetchSignInMethodsForEmail fails, continue with normal signup
        _debugLog('⚠️ Could not check email existence: $e');
      }

      _debugLog('🚀 Calling AuthService().signUpOwner()');

      User? user = await AuthService().signUpOwner(
        email: email,
        password: password,
        name: name,
        extraData: {
          'approvalStatus': 'pending',
          'pendingDocuments': true,
        },
      );

      _debugLog('✅ SignUpOwner result: ${user != null ? 'SUCCESS' : 'FAILED - user is null'}');

      if (user == null) {
        _debugLog('❌ User creation failed - null user returned');
        setState(() {
          _error = 'Failed to create owner account.';
        });
        return;
      }

      _debugLog('👤 User created successfully - UID: ${user.uid}');
      _debugLog('📧 User email: ${user.email}');
      _debugLog('✉️ User emailVerified: ${user.emailVerified}');

      if (!mounted) return;

      _debugLog('🎯 Navigating to owner verification screen');
      Navigator.pushReplacementNamed(
        context,
        '/owner-verification',
        arguments: {
          'email': email,
          'password': null,
          'name': name,
          'isGoogleUser': false,
          'photoURL': null,
          'credential': null,
        },
      );
      _debugLog('➡️ Navigation pushed: /owner-verification');
    } on FirebaseAuthException catch (e) {
      _debugLog('❌ FirebaseAuthException caught:');
      _debugLog('🔴 Code: ${e.code}');
      _debugLog('🔴 Message: ${e.message}');

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
              '/owner-verification',
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
        // This should not happen now since we check before signup,
        // but keep as fallback - try to sign in and check if it's a rejected user
        _debugLog('⚠️ email-already-in-use caught - attempting to sign in to check if rejected user...');
        try {
          final signInResult = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          
          if (signInResult.user != null) {
            final user = signInResult.user!;
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
            
            // If no Firestore document exists, this is a rejected user trying to re-register
            if (!userDoc.exists) {
              _debugLog('✅ Rejected user detected via error handler - skipping verification, going to document upload');
              
              // Create a minimal Firestore document to mark as pending
              await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                'email': email,
                'name': name,
                'role': 'owner',
                'authProvider': 'email',
                'emailVerified': true, // Skip verification for rejected users re-registering
                'approvalStatus': 'pending',
                'pendingDocuments': true,
                'createdAt': FieldValue.serverTimestamp(),
              });
              
              if (mounted) {
                Navigator.pushReplacementNamed(
                  context,
                  '/owner-document-upload',
                  arguments: {
                    'userId': user.uid,
                    'name': name,
                    'email': email,
                    'isGoogleUser': false,
                    'googleCredential': null,
                    'needsPasswordSetup': false,
                  },
                );
              }
              return;
            } else {
              // Firestore doc exists - regular existing account
              await FirebaseAuth.instance.signOut();
              msg = 'This email is already registered. Please login or use "Forgot Password".';
            }
          }
        } on FirebaseAuthException catch (signInError) {
          // Wrong password
          if (signInError.code == 'wrong-password' || signInError.code == 'invalid-credential') {
            msg = 'This email is already registered but the password is incorrect.\n\nIf you were previously rejected, please use "Forgot Password" to reset it.';
          } else {
            msg = 'This email is already registered. Please login or use "Forgot Password".';
          }
        } catch (e) {
          // Other errors - show generic message
          msg = 'This email is already registered. Please login or use "Forgot Password".';
        }
      } else if (e.code == 'weak-password') {
        msg = 'The password provided is too weak.';
      } else if (e.code == 'operation-not-allowed') {
        msg = 'Email/password accounts are not enabled in Firebase.';
      }
      setState(() {
        _error = msg;
      });
    } catch (e, stackTrace) {
      _debugLog('💥 General exception caught: ${e.toString()}');
      _debugLog('🔍 Exception type: ${e.runtimeType}');
      _debugLog('📚 Stack trace: ${stackTrace.toString()}');
      setState(() {
        _error = 'Failed to create account: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _debugLog('=== EMAIL SIGNUP COMPLETED ===');
    }
  }

  Future<void> _signUpWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });

    _debugLog('=== 🚀 STARTING GOOGLE SIGNUP (OWNER) ===');
    _debugLog('👤 Current Firebase user: ${FirebaseAuth.instance.currentUser?.email ?? 'none'}');

    try {
      _debugLog('📞 Calling AuthService().signInWithGoogleAsOwner()');

      final result = await AuthService().signInWithGoogleAsOwner();

      _debugLog('📦 Google sign-up result: ${result != null ? 'NOT NULL' : 'NULL'}');

      if (result != null) {
        _debugLog('🔑 Result keys: ${result.keys.toList()}');

        final isNewUser = result['isNewUser'] == true;
        final userData = result['userData'];
        final credential = result['credential'];

        _debugLog('👶 isNewUser: $isNewUser');
        _debugLog('📝 userData: ${userData != null ? 'present' : 'null'}');
        if (userData != null) {
          _debugLog('📧 userData email: ${userData['email']}');
          _debugLog('👤 userData name: ${userData['name']}');
          _debugLog('🖼️ userData photoURL: ${userData['photoURL'] != null ? 'present' : 'null'}');
        }
        _debugLog('🎫 credential: ${credential != null ? credential.runtimeType.toString() : 'null'}');

        if (isNewUser && userData != null) {
          _debugLog('✨ New owner detected - navigating to owner verification');
          if (mounted) {
            Navigator.pushReplacementNamed(
              context,
              '/owner-verification',
              arguments: {
                'email': userData['email'],
                'password': null,
                'name': userData['name'],
                'photoURL': userData['photoURL'],
                'isGoogleUser': true,
                'credential': credential,
              },
            );
            _debugLog('➡️ Navigation pushed: /owner-verification with Google user data');
          }
        } else if (!isNewUser) {
          _debugLog('⚠️ Existing owner detected - should not happen in signup flow');
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Account Already Exists'),
                content: const Text('An owner account with this Google account already exists. Please sign in instead.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.pushReplacementNamed(context, '/owner-login');
                      _debugLog('➡️ Navigation pushed: /owner-login (from dialog)');
                    },
                    child: const Text('Go to Login'),
                  ),
                ],
              ),
            );
          }
        } else {
          _debugLog('❌ Unexpected state - userData is null for new user');
          setState(() {
            _error = 'Failed to retrieve Google user data. Please try again.';
          });
        }
      } else {
        _debugLog('🚫 Google sign-up returned null - user likely cancelled');
      }
    } catch (e, stackTrace) {
      _debugLog('💥 GOOGLE SIGN-UP ERROR:');
      _debugLog('❌ Error: ${e.toString()}');
      _debugLog('🔍 Error type: ${e.runtimeType}');
      _debugLog('📚 Stack trace: ${stackTrace.toString()}');

      if (e is FirebaseAuthException) {
        _debugLog('🔥 FirebaseAuthException code: ${e.code}');
        _debugLog('🔥 FirebaseAuthException message: ${e.message}');
      }

      String errorMsg = 'Google sign-up failed.';
      final errorStr = e.toString();

      _debugLog('🔍 Checking error string: $errorStr');

      if (errorStr.contains('Access denied')) {
        errorMsg = 'Access denied. This Google account is not registered as a gas station owner.';
        _debugLog('🎯 Matched: Access denied error');
      } else if (errorStr.contains('account-exists-with-different-credential')) {
        errorMsg = 'An account already exists with this email using a different sign-in method.';
        _debugLog('🎯 Matched: Different credential error');
      } else if (errorStr.contains('network')) {
        errorMsg = 'Network error. Please check your internet connection and try again.';
        _debugLog('🎯 Matched: Network error');
      } else if (errorStr.contains('sign_in_canceled') || errorStr.contains('cancelled')) {
        errorMsg = 'Google sign-up was cancelled.';
        _debugLog('🎯 Matched: Sign-up cancelled');
      } else if (errorStr.contains('popup-closed-by-user')) {
        errorMsg = 'Sign-up popup was closed. Please try again.';
        _debugLog('🎯 Matched: Popup closed error');
      } else if (errorStr.contains('operation-not-allowed')) {
        errorMsg = 'Google sign-in is not enabled. Check Firebase console configuration.';
        _debugLog('🎯 Matched: Operation not allowed error');
      } else if (errorStr.contains('invalid-api-key')) {
        errorMsg = 'Invalid API key configuration. Please contact support.';
        _debugLog('🎯 Matched: Invalid API key error');
      } else {
        _debugLog('❓ No specific error match found - using detailed message');
        errorMsg = 'Google sign-up failed: ${e.toString()}';
      }

      setState(() {
        _error = errorMsg;
      });
    } finally {
      setState(() {
        _isGoogleLoading = false;
      });
      _debugLog('=== ✅ GOOGLE SIGN-UP COMPLETED ===');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Sign Up'),
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
                Image.asset('assets/fuelgo1.png', height: 120, fit: BoxFit.contain),
                const SizedBox(height: 16),

                // Show Google info if coming from Google signup
                if (widget.prefillName != null && widget.prefillEmail != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      border: Border.all(color: Colors.blue.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Complete your owner registration with Google account: ${widget.prefillEmail}',
                            style: TextStyle(color: Colors.blue.shade600, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Google Sign-up button (only show if not from Google prefill)
                if (widget.prefillEmail == null) ...[
                  _isGoogleLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton.icon(
                          onPressed: _signUpWithGoogle,
                          icon: Image.asset(
                            'assets/google_logo.png',
                            height: 24,
                            width: 24,
                          ),
                          label: const Text('Sign up as Owner with Google'),
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
                ],

                // Email signup form
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
                    labelText: 'E-Mail',
                    hintText: 'Enter your email',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  enabled: widget.prefillEmail == null,
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
                        child: Text(
                          widget.prefillEmail != null
                              ? 'Complete Google Sign Up as Owner'
                              : 'Sign Up as Owner with Email',
                        ),
                      ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/owner-login');
                  },
                  child: const Text('Already have an account? Login as Owner'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/role-selection');
                  },
                  child: const Text('Back to Role Selection'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
