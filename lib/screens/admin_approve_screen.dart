// lib/screens/admin_approval_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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

      // 2) Send EmailJS email to owner notifying them
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
<p>We regret to inform you that your gas station registration has been <strong>REJECTED</strong>.</p>
<br>
<p><strong>Registration Details:</strong></p>
<ul>
<li>Name: ${ownerName}</li>
<li>Station: ${stationName}</li>
<li>Status: REJECTED</li>
</ul>
<br>
<p><strong>Reason for Rejection:</strong></p>
<p>${reason ?? 'No specific reason provided.'}</p>
<br>
<p>If you believe this decision was made in error or if you have additional information to provide, please reply to this email with your concerns.</p>
<br>
<p>Best regards,<br/>
The FuelGo Team<br/>
FuelGo System Admin</p>
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

      if (mounted) {
        final statusText = status == 'approved' 
            ? 'approved' 
            : status == 'rejected' 
                ? 'rejected' 
                : 'marked for resubmission';
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('User $statusText and owner notified via email.'),
            backgroundColor: status == 'rejected' ? Colors.red : Colors.green,
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Status updated to $statusText but email notification failed.'),
            backgroundColor: Colors.orange,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to update status: $e'),
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

  void _showRejectDialog(String userId, String email, String name, String stationName) {
    final TextEditingController reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Registration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reject the registration for $name\'s station: $stationName'),
            const SizedBox(height: 12),
            const Text('Provide a reason (required):'),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl, 
              maxLines: 3, 
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g., Invalid documents, fraudulent information, does not meet requirements...'
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a reason for rejection'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
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
                            label: const Text('Resubmit'),
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