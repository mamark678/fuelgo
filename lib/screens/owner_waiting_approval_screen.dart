// lib/screens/owner_waiting_approval_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class OwnerWaitingApprovalScreen extends StatefulWidget {
  const OwnerWaitingApprovalScreen({Key? key}) : super(key: key);

  @override
  State<OwnerWaitingApprovalScreen> createState() => _OwnerWaitingApprovalScreenState();
}

class _OwnerWaitingApprovalScreenState extends State<OwnerWaitingApprovalScreen> {
  String? _approvalStatus;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkApprovalStatus();
    _watchApprovalStatus();
  }

  Future<void> _checkApprovalStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _error = 'No user session found. Please log in again.';
        _isLoading = false;
      });
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final status = userDoc.data()?['approvalStatus'] as String? ?? 'pending';
        setState(() {
          _approvalStatus = status;
          _isLoading = false;
        });

        // Automatically navigate based on status
        if (status == 'approved') {
          _navigateToDashboard();
        } else if (status == 'request_submission') {
          _navigateToDocumentUpload(user);
        } else if (status == 'rejected') {
          _handleRejection();
        }
      } else {
        setState(() {
          _error = 'User document not found.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error checking approval status: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _watchApprovalStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    AuthService().watchApprovalStatus(user.uid).listen((status) {
      if (status != null && mounted) {
        setState(() {
          _approvalStatus = status;
        });

        // Automatically navigate when status changes
        if (status == 'approved') {
          _navigateToDashboard();
        } else if (status == 'request_submission') {
          _navigateToDocumentUpload(user);
        } else if (status == 'rejected') {
          _handleRejection();
        }
      }
    });
  }

  void _navigateToDashboard() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your registration has been approved! Welcome!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/owner-dashboard');
        }
      });
    }
  }

  void _navigateToDocumentUpload(User user) {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/owner-document-upload', arguments: {
        'userId': user.uid,
        'name': user.displayName ?? '',
        'email': user.email ?? '',
      });
    }
  }

  void _handleRejection() {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Registration Rejected'),
          content: const Text(
            'Your registration has been rejected. Please review your documents and try again. You will be redirected to the sign-up page.',
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
  }

  void _signOut() async {
    await AuthService().signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/owner-login');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Checking Status'),
          automaticallyImplyLeading: false,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Error'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/owner-login');
                },
                child: const Text('Go to Login'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Waiting for Approval'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Icon(
                Icons.pending_actions,
                size: 80,
                color: Colors.orange.shade300,
              ),
              const SizedBox(height: 24),
              const Text(
                'Waiting for Admin Approval',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Your registration documents have been submitted and are currently being reviewed by our admin team.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 32),
                    const SizedBox(height: 12),
                    const Text(
                      'What happens next?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Our admin team will review your documents\n'
                      '2. You will receive an email notification once reviewed\n'
                      '3. If approved, you can access your dashboard\n'
                      '4. If additional documents are needed, you will be notified',
                      style: TextStyle(fontSize: 14),
                      textAlign: TextAlign.left,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _checkApprovalStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Status'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  padding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _signOut,
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

