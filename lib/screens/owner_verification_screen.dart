// lib/screens/owner_verification_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class OwnerVerificationScreen extends StatefulWidget {
  final String email;
  final String? password; // null for Google users
  final String name;
  final String? photoURL;
  final bool isGoogleUser;
  final AuthCredential? credential; // for Google users

  const OwnerVerificationScreen({
    Key? key,
    required this.email,
    this.password,
    required this.name,
    this.photoURL,
    required this.isGoogleUser,
    this.credential,
  }) : super(key: key);

  @override
  State<OwnerVerificationScreen> createState() => _OwnerVerificationScreenState();
}

class _OwnerVerificationScreenState extends State<OwnerVerificationScreen> {
  bool _isLoading = false;
  bool _isResending = false;
  String? _error;

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
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && !currentUser.emailVerified) {
        try {
          await AuthService().sendEmailVerification();
          print('Verification email sent to existing user: ${currentUser.email}');
        } catch (e) {
          print('Error sending verification to existing user: $e');
        }
      }
    }
  }

  /*Future<void> _createGoogleAccountWithVerification() async {
    try {
      // Create account using the regular signUpOwner method with a temporary password
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

      if (e.toString().contains('email-already-in-use')) {
        setState(() {
          _error = 'This email is already registered. Please try signing in instead.';
        });
      } else {
        setState(() {
          _error = 'Failed to create account. Please try again. Error: ${e.toString()}';
        });
      }
    }
  }*/

  Future<void> _createGoogleAccountWithVerification() async {
  setState(() => _isLoading = true);
  try {
    // Step 0: ensure we have an incoming credential + email
    final credential = widget.credential;
    final email = widget.email;
    if (credential == null || email.isEmpty) {
      setState(() {
        _error = 'Missing Google credential or email.';
      });
      return;
    }

    // Step 1: use Auth to check existing providers (works without Firestore reads)
    final methods = await FirebaseAuth.instance.fetchSignInMethodsForEmail(email);

    // If user already has email/password, instruct to sign in with email and link Google later.
    if (methods.contains('password') && !methods.contains('google.com')) {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      setState(() {
        _error = 'This email already exists with email/password. We sent a password reset to $email — sign in with your email then link Google from Account Settings.';
      });
      return;
    }

    // If Google is already a provider, try signing in, then inspect the user's own document by UID
    if (methods.contains('google.com')) {
      try {
        final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
        final firebaseUser = userCredential.user;
        if (firebaseUser != null) {
          // Safely read only the current user's document (allowed by rules)
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(firebaseUser.uid).get();
          final data = userDoc.data() as Map<String, dynamic>?;

          final documentsSubmitted = data?['documentsSubmitted'] as bool? ?? false;
          final approvalStatus = data?['approvalStatus'] as String? ?? '';

          if (approvalStatus == 'approved' && documentsSubmitted) {
            Navigator.pushReplacementNamed(context, '/owner-dashboard');
          } else {
            Navigator.pushReplacementNamed(context, '/owner-document-upload', arguments: {
              'userId': firebaseUser.uid,
              'name': widget.name,
              'email': widget.email,
            });
          }
          return;
        }
      } on FirebaseAuthException catch (fae) {
        setState(() {
          _error = 'Google sign-in failed: ${fae.message ?? fae.code}';
        });
        return;
      } catch (e) {
        setState(() {
          _error = 'Failed to sign in with Google: ${e.toString()}';
        });
        return;
      }
    }

    // Step 2: No existing Firestore user -> create account directly with Google
    try {
      final user = await AuthService().completeGoogleOwnerAfterVerification(
        name: widget.name,
        email: widget.email,
        photoURL: widget.photoURL,
        credential: credential,
      );

      if (user != null) {
        // Navigate to document upload
        Navigator.pushReplacementNamed(context, '/owner-document-upload', arguments: {
          'userId': user.uid,
          'name': widget.name,
          'email': widget.email,
        });
      } else {
        throw Exception('Failed to create user account');
      }
    } on FirebaseAuthException catch (fae) {
      if (fae.code == 'account-exists-with-different-credential') {
        // Send password reset
        await FirebaseAuth.instance.sendPasswordResetEmail(email: widget.email);
        setState(() {
          _error = 'An account with this email exists (email/password). We sent a password reset to ${widget.email} — sign in with your email and then link Google from Account Settings.';
        });
        return;
      } else {
        setState(() {
          _error = 'Google sign-in failed: ${fae.message ?? fae.code}';
        });
        return;
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to create account. Please try again. Error: ${e.toString()}';
      });
    }
  } catch (e) {
    print('Error creating Google owner account for verification: $e');
    if (e.toString().contains('email-already-in-use')) {
      // rather than a generic message, we handle it above — but keep fallback
      setState(() {
        _error = 'This email is already registered. Please try signing in instead.';
      });
    } else {
      setState(() {
        _error = 'Failed to create account. Please try again. Error: ${e.toString()}';
      });
    }
  } finally {
    setState(() => _isLoading = false);
  }
}


  Future<void> _checkEmailVerified() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
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
              'tempPasswordUsed': FieldValue.delete(),
            });
          } catch (e) {
            print('Error linking Google credential: $e');
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
                      'Email verified successfully! Please upload your required documents.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // Navigate to document upload screen
                      Navigator.pushReplacementNamed(
                        context, 
                        '/owner-document-upload',
                        arguments: {
                          'userId': refreshedUser.uid,
                          'name': widget.name,
                          'email': widget.email,
                        },
                      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Your Email - Owner'),
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
                      ? 'Completing your Google owner account setup. Please wait...'
                      : 'Please check your email and click the verification link to verify your owner account.',
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
                const SizedBox(height: 8),
                const Text(
                  'After verification, you will need to upload your required documents for admin approval.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
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