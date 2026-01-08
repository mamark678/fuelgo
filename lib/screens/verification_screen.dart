// lib/screens/verification_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class VerificationScreen extends StatefulWidget {
  final String email;
  final String? password; // null for Google users or when password not created yet
  final String name;
  final String? photoURL;
  final bool isGoogleUser;
  final AuthCredential? credential; // for Google users

  const VerificationScreen({
    Key? key,
    required this.email,
    this.password,
    required this.name,
    this.photoURL,
    required this.isGoogleUser,
    this.credential,
  }) : super(key: key);

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool _isLoading = false;
  bool _isResending = false;
  String? _error;
  bool _hasCreatedAccount = false;
  Timer? _pollTimer;
  int _pollAttempts = 0;

  @override
  void initState() {
    super.initState();
    _initializeAccount();
  }

  Future<void> _initializeAccount() async {
    if (widget.isGoogleUser && widget.credential != null) {
      // For Google users, create the account with email verification
      await _createGoogleAccountWithVerification();
    } else if (!widget.isGoogleUser) {
      // For email users, verification email was already sent in signup
      // Just check if there's a current user to send verification to
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && !currentUser.emailVerified) {
        try {
          await AuthService().sendEmailVerification();
          print('Verification email sent to existing user: ${currentUser.email}');
        } catch (e) {
          print('Error sending verification to existing user: $e');
        }
      }
        // Start a short polling loop so that if user verifies in browser and returns
        // to the app we detect the emailVerified flag without requiring full manual checks.
        _startVerificationPolling();
    }
  }

  Future<void> _createGoogleAccountWithVerification() async {
  try {
    // 🔹 Step 1: Check if the email already exists in Firestore
    final existing = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: widget.email)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      // Already registered, stop here
      setState(() {
        _error = 'This email is already registered. Please try signing in instead.';
      });
      return;
    }

    // 🔹 Step 2: Only create if not existing
    final tempPassword = 'TempPass123!${DateTime.now().millisecondsSinceEpoch}';

    final user = await AuthService().signUpOwner(
      email: widget.email,
      password: tempPassword,
      name: widget.name,
      extraData: {
        'authProvider': 'google',
        'photoURL': widget.photoURL,
        'googleCredential': true,
        'tempPasswordUsed': true,
        'pendingDocuments': true, // Flag to indicate documents are needed
      },
    );

    if (user != null) {
      print('Google owner account created with temporary password for: ${widget.email}');
      print('Verification email should have been sent automatically by signUpOwner method');
    } else {
      throw Exception('Failed to create user account');
    }
  } catch (e) {
    print('Error creating Google owner account for verification: $e');
    setState(() {
      _error = 'Failed to create account. Please try again. Error: ${e.toString()}';
    });
  }
}


  Future<void> _checkEmailVerified() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // First reload the current user to get fresh verification status
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          _error = 'No user session found. Please try signing up again.';
        });
        return;
      }

      await currentUser.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (refreshedUser != null && refreshedUser.emailVerified) {
        // Mark user as verified in Firestore
        await AuthService().markEmailUserAsVerified(refreshedUser.uid);

        // If this was a Google user, link the Google credential
        if (widget.isGoogleUser && widget.credential != null) {
          try {
            await refreshedUser.linkWithCredential(widget.credential!);
            print('Google credential linked successfully');

            // Update Firestore to reflect Google auth and remove temp password flag
            await FirebaseFirestore.instance
                .collection('users')
                .doc(refreshedUser.uid)
                .update({
              'authProvider': 'google',
              'photoURL': widget.photoURL,
              'linkedProviders': ['password', 'google.com'],
              'tempPasswordUsed': FieldValue.delete(), // Remove temp flag
            });
          } catch (e) {
            print('Error linking Google credential: $e');
            // Continue anyway - account is still valid
          }
        }

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                content: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 48),
                    SizedBox(height: 16),
                    Text(
                      'Account verified successfully! Welcome to Fuel-GO!',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      // Close the dialog first
                      Navigator.of(context).pop();

                      // Sign out the current user so they are taken to the login screen
                      try {
                        await FirebaseAuth.instance.signOut();
                      } catch (e) {
                        print('Error signing out after verification: $e');
                      }

                      // Navigate to login (instead of home)
                      if (mounted) {
                        Navigator.pushReplacementNamed(context, '/login');
                      }
                    },
                    child: const Text('Continue'),
                  ),
                ],
              );
            },
          );
        }
      } else {
        setState(() {
          _error = 'Email not verified yet. Please check your email and click the verification link.';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Verification check failed: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _resendVerificationEmail() async {
    setState(() {
      _error = null;
      _isResending = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await currentUser.sendEmailVerification();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification email sent! Please check your inbox.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _error = 'No user session found. Please try signing up again.';
        });
      }
    } catch (e) {
      print('Resend verification error: $e');
      setState(() {
        _error = 'Failed to resend verification email. Please try again later.';
      });
    } finally {
      setState(() {
        _isResending = false;
      });
    }
  }

  void _startVerificationPolling() {
    _pollTimer?.cancel();
    _pollAttempts = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      _pollAttempts++;
      if (_pollAttempts > 20) {
        // Stop after ~60 seconds
        timer.cancel();
        return;
      }
      try {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) return;
        await currentUser.reload();
        final refreshed = FirebaseAuth.instance.currentUser;
        if (refreshed != null && refreshed.emailVerified) {
          timer.cancel();
          // mark in Firestore and show success flow
          await AuthService().markEmailUserAsVerified(refreshed.uid);
          if (widget.isGoogleUser && widget.credential != null) {
            try {
              await refreshed.linkWithCredential(widget.credential!);
            } catch (_) {}
          }
          if (mounted) {
            // Sign out and go to login (same as normal flow)
            try {
              await FirebaseAuth.instance.signOut();
            } catch (_) {}
            if (mounted) Navigator.pushReplacementNamed(context, '/login');
          }
        }
      } catch (_) {
        // ignore transient errors and keep polling
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Your Email'),
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
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.email, size: 64, color: Colors.blue),
                const SizedBox(height: 16),
                Text(
                  widget.isGoogleUser
                      ? 'Please check your email and click the verification link to complete your Google account setup.'
                      : 'Please check your email and click the verification link to verify your account.',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.email,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (widget.isGoogleUser) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'After verification, you\'ll be able to sign in with both your email and Google account.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
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
                            style: TextStyle(
                              color: Colors.red.shade600,
                              fontSize: 14,
                            ),
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
                        onPressed: _checkEmailVerified,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        child: const Text('I have verified'),
                      ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isResending ? null : _resendVerificationEmail,
                  child: _isResending ? const Text('Sending...') : const Text('Resend Verification Email'),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
