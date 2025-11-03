// lib/screens/admin_approval_screen.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../services/email_service.dart';

class AdminApprovalScreen extends StatefulWidget {
  const AdminApprovalScreen({Key? key}) : super(key: key);

  @override
  State<AdminApprovalScreen> createState() => _AdminApprovalScreenState();
}

class _AdminApprovalScreenState extends State<AdminApprovalScreen> {
  final _usersRef = FirebaseFirestore.instance.collection('users');

Future<void> _updateApprovalStatusAndNotify({
  required String userId,
  required String ownerEmail,
  required String ownerName,
  required String stationName,
  required String status,
  String? reason,
}) async {
  try {
    // 2) Send EmailJS email to owner notifying them FIRST (before deletion if rejected)
      final subject = status == 'approved'
          ? 'FuelGo Registration APPROVED - Welcome to FuelGo!'
          : status == 'rejected'
              ? 'FuelGo Registration REJECTED'
              : 'FuelGo Registration - Document Review Required';

      final message = status == 'approved'
          ? '''
<p>Dear ${ownerName},</p>
<p>Congratulations! Your gas station registration has been <strong>APPROVED</strong>.</p>
<br>
<p><strong>Your Registration Details:</strong></p>
<ul>
<li>Name: ${ownerName}</li>
<li>Station: ${stationName}</li>
<li>Status: APPROVED</li>
</ul>
<br>
<p><strong>Next Steps:</strong></p>
<p>You can now log into your owner account and start managing your gas station. Upload fuel prices, manage inventory, and serve customers through the FuelGo platform.</p>
<br>
<p>If you have any questions or need assistance, don't hesitate to reply to this email.</p>
<br>
<p>Best regards,<br/>
The FuelGo Team<br/>
FuelGo System Admin</p>
'''
          : status == 'rejected'
              ? '''
<p>Dear ${ownerName},</p>
<p>Unfortunately, your gas station registration has been <strong>REJECTED</strong>.</p>
<br>
<p><strong>Your Registration Details:</strong></p>
<ul>
<li>Name: ${ownerName}</li>
<li>Station: ${stationName}</li>
<li>Status: REJECTED</li>
</ul>
<br>
${reason != null ? '<p><strong>Reason:</strong> $reason</p><br>' : ''}
<p>You will need to sign up again with updated documents. Please review the requirements and ensure all documents are clear and valid before resubmitting.</p>
<br>
<p>If you have any questions, please contact our support team.</p>
<br>
<p>Best regards,<br/>
The FuelGo Team</p>
'''
          : '''
<p>Dear ${ownerName},</p>
<p>Your registration requires document review.</p>
<br>
<p><strong>Details:</strong></p>
<ul>
<li>Name: ${ownerName}</li>
<li>Station: ${stationName}</li>
<li>Status: NEEDS RESUBMISSION</li>
</ul>
<br>
<p>${reason != null ? '<strong>Reason:</strong> $reason<br/><br/>' : ''}Please resubmit with clearer documents (check for blurry images, expired IDs, or missing info).</p>
<br>
<p>Reply if you have questions.</p>
<br>
<p>Best regards,<br/>
The FuelGo Team</p>
''';

      final ok = await EmailService.sendEmail(
        toEmail: ownerEmail,
        subject: subject,
        message: message,
      );

      // If rejected, delete all related data AFTER sending email
      if (status == 'rejected') {
        try {
          await _deleteRejectedUserData(userId);
        } catch (deleteError) {
          // If deletion fails, still show success for email notification
          // but add warning about deletion failure
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Email sent but data deletion failed: $deleteError'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ));
          }
          // Re-throw to be handled by outer catch
          throw deleteError;
        }
      } else {
        // 1) Update Firestore with the new status AND email notification flag
        await _usersRef.doc(userId).update({
          'approvalStatus': status,
          'emailNotificationSent': true, // KEY: This allows future login attempts
          if (status == 'approved') ...{
            'approvedAt': FieldValue.serverTimestamp(),
            'documentsSubmitted': true, // Ensure documents are marked as submitted for approved
          },
          if (status == 'request_submission') ...{
            'requestSubmissionAt': FieldValue.serverTimestamp(),
            'documentsSubmitted': false, // Reset to allow resubmission
          },
          if (reason != null) 'rejectionReason': reason,
        });
      }

      if (mounted) {
        final statusText = status == 'approved' 
            ? 'approved' 
            : status == 'rejected' 
                ? 'rejected' 
                : 'marked for resubmission';
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(status == 'rejected' 
                ? (ApiConfig.authDeleteApiUrl.isEmpty
                    ? 'User rejected, Firestore/Storage data deleted, and owner notified via email.\nNote: Auth user may still exist - delete manually via Firebase Console.'
                    : 'User rejected, all data (including Auth) deleted, and owner notified via email.')
                : 'User $statusText and owner notified via email.'),
            backgroundColor: status == 'rejected' ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 6),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(status == 'rejected'
                ? 'User rejected and data deleted, but email notification failed.'
                : 'Status updated to $statusText but email notification failed.'),
            backgroundColor: Colors.orange,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to process rejection: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _showApproveConfirmDialog(String userId, String email, String name, String stationName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve Registration'),
        content: Text('Are you sure you want to approve the registration for $name\'s station: $stationName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Cancel')
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(context);
              _updateApprovalStatusAndNotify(
                userId: userId,
                ownerEmail: email,
                ownerName: name,
                stationName: stationName,
                status: 'approved',
              );
            },
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRequestSubmissionDialog(String userId, String email, String name, String stationName) {
    final TextEditingController reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Request Document Resubmission'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Request $name to resubmit documents for: $stationName'),
            const SizedBox(height: 12),
            const Text('Provide a reason (optional):'),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl, 
              maxLines: 3, 
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g., Blurry images, expired documents, missing information...'
              )
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Cancel')
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              final reason = reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim();
              Navigator.pop(context);
              _updateApprovalStatusAndNotify(
                userId: userId,
                ownerEmail: email,
                ownerName: name,
                stationName: stationName,
                status: 'request_submission',
                reason: reason,
              );
            },
            child: const Text('Request Resubmission', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentImageCard(String title, String imageUrl) {
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppBar(
                    title: Text(title),
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Expanded(
                    child: InteractiveViewer(
                      child: Image.network(imageUrl, fit: BoxFit.contain),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: Card(
        elevation: 2,
        child: Container(
          width: 120,
          height: 120,
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                  ),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteRejectedUserData(String userId) async {
    try {
      // Get user data first to find related documents
      final userDoc = await _usersRef.doc(userId).get();
      if (!userDoc.exists) return;

      final userData = userDoc.data() as Map<String, dynamic>?;
      final stationId = userData?['stationId'] as String?;
      final documentUrls = userData?['documentUrls'] as Map<String, dynamic>?;

      // 1. Delete uploaded documents from Firebase Storage
      if (documentUrls != null) {
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('owner_documents')
              .child(userId);

          // Delete all files in the user's document folder
          final listResult = await storageRef.listAll();
          for (var item in listResult.items) {
            try {
              await item.delete();
            } catch (e) {
              print('Error deleting storage file ${item.name}: $e');
              // Continue deleting other files even if one fails
            }
          }

          // Also try to delete the folder itself
          try {
            await storageRef.delete();
          } catch (e) {
            // Folder might not exist or already deleted, that's okay
            print('Note: Could not delete storage folder: $e');
          }
        } catch (e) {
          print('Error deleting storage documents: $e');
          // Continue with other deletions even if storage deletion fails
        }
      }

      // 2. Delete gas station document if it exists
      if (stationId != null) {
        try {
          await FirebaseFirestore.instance
              .collection('gas_stations')
              .doc(stationId)
              .delete();
        } catch (e) {
          print('Error deleting gas station: $e');
          // Continue with user deletion even if gas station deletion fails
        }
      }

      // 3. Delete user document from Firestore
      try {
        await _usersRef.doc(userId).delete();
      } catch (e) {
        print('Error deleting user document: $e');
        throw e; // Re-throw if user deletion fails
      }

      // 4. Delete Firebase Authentication user account via API (if configured)
      if (ApiConfig.authDeleteApiUrl.isNotEmpty) {
        try {
          print('Attempting to delete Firebase Auth user via API: $userId');
          
          // Get current admin user's token for authentication
          final currentUser = FirebaseAuth.instance.currentUser;
          final adminToken = currentUser != null 
              ? await currentUser.getIdToken() 
              : null;
          
          final response = await http.post(
            Uri.parse(ApiConfig.authDeleteApiUrl),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'userId': userId,
              'adminToken': adminToken,
            }),
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('API request timeout');
            },
          );
          
          if (response.statusCode == 200) {
            final result = jsonDecode(response.body);
            if (result['success'] == true) {
              print('✅ Successfully deleted Firebase Auth user: $userId');
            } else {
              throw Exception(result['message'] ?? 'API returned unsuccessful result');
            }
          } else {
            final errorData = jsonDecode(response.body);
            throw Exception(errorData['message'] ?? 'API request failed with status ${response.statusCode}');
          }
        } catch (e) {
          print('❌ Error deleting Firebase Auth user via API: $e');
          // Don't throw - continue even if Auth deletion fails
          // The Firestore and Storage data are already deleted
          print('⚠️ Note: Firebase Auth user ($userId) may still exist. Firestore and Storage data have been deleted.');
        }
      } else {
        // API URL not configured - skip Auth deletion
        print('⚠️ Auth deletion API URL not configured. Firebase Auth user ($userId) still exists.');
        print('⚠️ To enable Auth deletion, set ApiConfig.authDeleteApiUrl or delete manually via Firebase Console.');
      }

      print('Successfully deleted all data for rejected user: $userId');
    } catch (e) {
      print('Error in _deleteRejectedUserData: $e');
      rethrow; // Re-throw to be handled by caller
    }
  }

  void _showRejectDialog(String userId, String email, String name, String stationName) {
    final TextEditingController reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Registration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reject registration for $name\'s station: $stationName'),
            const SizedBox(height: 12),
            const Text('Provide a reason (optional):'),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl, 
              maxLines: 3, 
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g., Invalid documents, incomplete information...'
              )
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Text(
                '⚠️ This will reject the registration, delete all submitted data, and the owner will need to sign up again.',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Cancel')
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final reason = reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim();
              Navigator.pop(context);
              _updateApprovalStatusAndNotify(
                userId: userId,
                ownerEmail: email,
                ownerName: name,
                stationName: stationName,
                status: 'rejected',
                reason: reason,
              );
            },
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Pending Registrations'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await AuthService().signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/admin-login');
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _usersRef.where('approvalStatus', isEqualTo: 'pending').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No pending registrations.', style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final userId = doc.id;
              final data = doc.data() as Map<String, dynamic>;
              final name = data['name'] ?? 'No name';
              final email = data['email'] ?? '';
              final stationName = data['stationName'] ?? 'Unknown Station';
              final submittedAt = data['submittedAt'] as Timestamp?;
              final submittedDate = submittedAt?.toDate().toString().split(' ')[0] ?? 'Unknown';
              
              // Get document URLs
              final documentUrls = data['documentUrls'] as Map<String, dynamic>?;
              final gasStationIdUrl = documentUrls?['gasStationId'] as String?;
              final governmentIdUrl = documentUrls?['governmentId'] as String?;
              final businessPermitUrl = documentUrls?['businessPermit'] as String?;
              final userIdForAuth = doc.id; // Store userId for Auth deletion reference

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('Station: $stationName', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                                Text('Email: $email', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                                Text('Submitted: $submittedDate', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('PENDING', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Document Images Section
                      if (gasStationIdUrl != null || governmentIdUrl != null || businessPermitUrl != null) ...[
                        const Text(
                          'Submitted Documents:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (gasStationIdUrl != null)
                              _buildDocumentImageCard('Gas Station ID', gasStationIdUrl),
                            if (governmentIdUrl != null)
                              _buildDocumentImageCard('Government ID', governmentIdUrl),
                            if (businessPermitUrl != null)
                              _buildDocumentImageCard('Business Permit', businessPermitUrl),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Approval Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.check_circle, size: 18),
                            label: const Text('Approve'),
                            onPressed: () => _showApproveConfirmDialog(userId, email, name, stationName),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.assignment_return, size: 18),
                            label: const Text('Request Resubmission'),
                            onPressed: () => _showRequestSubmissionDialog(userId, email, name, stationName),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.cancel, size: 18),
                            label: const Text('Reject'),
                            onPressed: () => _showRejectDialog(userId, email, name, stationName),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}