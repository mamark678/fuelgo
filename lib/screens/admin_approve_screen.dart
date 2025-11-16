// lib/screens/admin_approval_screen.dart
// Updated to support BOTH Firebase Storage URLs AND Base64 images

import 'dart:convert';
import 'dart:typed_data';

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
  print('🔄 Starting approval status update...');
  print('   User ID: $userId');
  print('   Status: $status');
  print('   Email: $ownerEmail');
  
  try {
    // Prepare email content
    final subject = status == 'approved'
        ? 'FuelGo Registration APPROVED - Welcome to FuelGo!'
        : status == 'rejected'
            ? 'FuelGo Registration REJECTED'
            : 'FuelGo Registration - Document Review Required';

    final message = status == 'approved'
        ? '''
<p>Dear $ownerName,</p>
<p>Congratulations! Your gas station registration has been <strong>APPROVED</strong>.</p>
<br>
<p><strong>Your Registration Details:</strong></p>
<ul>
<li>Name: $ownerName</li>
<li>Station: $stationName</li>
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
<p>Dear $ownerName,</p>
<p>Unfortunately, your gas station registration has been <strong>REJECTED</strong>.</p>
<br>
<p><strong>Your Registration Details:</strong></p>
<ul>
<li>Name: $ownerName</li>
<li>Station: $stationName</li>
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
<p>Dear $ownerName,</p>
<p>Your registration requires document review.</p>
<br>
<p><strong>Details:</strong></p>
<ul>
<li>Name: $ownerName</li>
<li>Station: $stationName</li>
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

    print('📧 Sending email notification...');
    
    // Send email notification
    bool emailSent = false;
    try {
      emailSent = await EmailService.sendEmail(
        toEmail: ownerEmail,
        subject: subject,
        message: message,
      );
      print(emailSent ? '✅ Email sent successfully' : '⚠️ Email sending returned false');
    } catch (emailError) {
      print('❌ Email sending failed: $emailError');
      // Continue even if email fails
    }

    // Handle rejection - DELETE USER DATA
    if (status == 'rejected') {
      print('🗑️ Starting rejection process - deleting user data...');
      
      try {
        await _deleteRejectedUserData(userId);
        print('✅ Successfully deleted rejected user data');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(emailSent 
                ? '✅ User rejected and deleted successfully!\n📧 Email notification sent to owner.'
                : '✅ User rejected and deleted successfully!\n⚠️ Email notification failed.'),
            backgroundColor: emailSent ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 5),
          ));
        }
      } catch (deleteError) {
        print('❌ Error deleting user data: $deleteError');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ Error deleting user data: $deleteError\n\nPlease try again or delete manually.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ));
        }
        
        // Re-throw to stop execution
        rethrow;
      }
    } 
    // Handle approval or request resubmission - UPDATE FIRESTORE
    else {
      print('💾 Updating Firestore with new status...');
      
      try {
        // Update user document
        await _usersRef.doc(userId).update({
          'approvalStatus': status,
          'emailNotificationSent': emailSent,
          if (status == 'approved') ...{
            'approvedAt': FieldValue.serverTimestamp(),
            'documentsSubmitted': true,
          },
          if (status == 'request_submission') ...{
            'requestSubmissionAt': FieldValue.serverTimestamp(),
            'documentsSubmitted': false,
          },
          if (reason != null) 'rejectionReason': reason,
        });
        
        // Also update all gas stations owned by this user to sync ownerApprovalStatus
        try {
          final stationsSnapshot = await FirebaseFirestore.instance
              .collection('gas_stations')
              .where('ownerId', isEqualTo: userId)
              .get();
          
          final batch = FirebaseFirestore.instance.batch();
          for (final stationDoc in stationsSnapshot.docs) {
            batch.update(stationDoc.reference, {
              'ownerApprovalStatus': status,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
          print('✅ Updated ${stationsSnapshot.docs.length} gas station(s) with new approval status');
        } catch (stationUpdateError) {
          print('⚠️ Warning: Could not update gas stations: $stationUpdateError');
          // Don't fail the whole operation if station update fails
        }
        
        print('✅ Firestore updated successfully');
        
        if (mounted) {
          final statusText = status == 'approved' ? 'approved' : 'marked for resubmission';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(emailSent
                ? '✅ User $statusText successfully!\n📧 Email notification sent.'
                : '✅ User $statusText successfully!\n⚠️ Email notification failed.'),
            backgroundColor: emailSent ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 4),
          ));
        }
      } catch (firestoreError) {
        print('❌ Firestore update failed: $firestoreError');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ Failed to update status: $firestoreError'),
            backgroundColor: Colors.red,
          ));
        }
        
        rethrow;
      }
    }
    
    print('✅ Approval status update completed successfully');
  } catch (e, stackTrace) {
    print('❌ Error in _updateApprovalStatusAndNotify: $e');
    print('Stack trace: $stackTrace');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ Operation failed: $e\n\nCheck console for details.'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 6),
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

  // Universal document image card - handles BOTH URLs and base64
  Widget _buildDocumentImageCard(String title, dynamic imageData) {
    // Check if it's a base64 string or URL
    final isBase64 = imageData is String && !imageData.startsWith('http');
    
    if (isBase64) {
      // Handle base64 image
      return _buildBase64ImageCard(title, imageData);
    } else {
      // Handle URL image
      return _buildUrlImageCard(title, imageData);
    }
  }

  // For base64 images stored in Firestore
  Widget _buildBase64ImageCard(String title, String base64String) {
    try {
      final Uint8List bytes = base64Decode(base64String);
      
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
                        child: Image.memory(
                          bytes, 
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline, color: Colors.red, size: 48),
                                  SizedBox(height: 8),
                                  Text('Failed to load image'),
                                ],
                              ),
                            );
                          },
                        ),
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
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                    ),
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
    } catch (e) {
      return Card(
        elevation: 2,
        child: Container(
          width: 120,
          height: 120,
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broken_image, color: Colors.grey, size: 32),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              const Text(
                'Invalid image',
                style: TextStyle(fontSize: 10, color: Colors.red),
              ),
            ],
          ),
        ),
      );
    }
  }

  // For URL images stored in Firebase Storage
  Widget _buildUrlImageCard(String title, String imageUrl) {
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
  print('🗑️ === STARTING DELETION PROCESS ===');
  print('   User ID: $userId');
  
  try {
    // Step 1: Get user document
    print('📋 Step 1: Fetching user document...');
    final userDoc = await _usersRef.doc(userId).get();
    
    if (!userDoc.exists) {
      print('⚠️ User document does not exist: $userId');
      print('   This might mean it was already deleted.');
      return;
    }
    
    print('✅ User document found');
    
    final userData = userDoc.data() as Map<String, dynamic>?;
    final stationId = userData?['stationId'] as String?;
    final documentUrls = userData?['documentUrls'] as Map<String, dynamic>?;
    final documentImages = userData?['documentImages'] as Map<String, dynamic>?;
    
    print('📊 User data summary:');
    print('   - Station ID: $stationId');
    print('   - Has documentUrls: ${documentUrls != null}');
    print('   - Has documentImages (base64): ${documentImages != null}');

    // Step 2: Skip Firebase Storage deletion (using base64 in Firestore instead)
    print('⏭️ Step 2: Skipped - Documents stored as base64 in Firestore, not in Storage');
    print('   - documentImages (base64): ${documentImages != null ? "Will be deleted with user doc" : "N/A"}');
    print('   - documentUrls (legacy): ${documentUrls != null ? "Ignored (empty/null)" : "N/A"}');

    // Step 3: Delete gas station document
    if (stationId != null && stationId.isNotEmpty) {
      print('🏪 Step 3: Deleting gas station document...');
      
      try {
        await FirebaseFirestore.instance
            .collection('gas_stations')
            .doc(stationId)
            .delete();
        print('   ✅ Gas station deleted: $stationId');
      } catch (e) {
        print('   ⚠️ Could not delete gas station: $e');
        // Continue anyway
      }
    } else {
      print('⏭️ Step 3: Skipped - No station ID found');
    }

    // Step 4: Delete user document from Firestore
    print('📄 Step 4: Deleting user document from Firestore...');
    
    try {
      await _usersRef.doc(userId).delete();
      print('   ✅ User document deleted successfully');
    } catch (e) {
      print('   ❌ CRITICAL: Failed to delete user document: $e');
      throw Exception('Failed to delete user document: $e');
    }

    print('✅ === DELETION PROCESS COMPLETED ===');
    print('   - User document (Firestore): DELETED ✅');
    print('   - Gas station document: ${stationId != null ? "DELETED ✅" : "N/A"}');
    print('   - Base64 images: ${documentImages != null ? "DELETED ✅ (stored in user doc)" : "N/A"}');
    print('   - Firebase Storage: SKIPPED (not used)');
    print('   - Firebase Auth account: PRESERVED (owner can re-register)');
    
  } catch (e, stackTrace) {
    print('❌ === DELETION PROCESS FAILED ===');
    print('   Error: $e');
    print('   Stack trace: $stackTrace');
    rethrow;
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
              
              // Try to get base64 images first (NEW FORMAT)
              final documentImages = data['documentImages'] as Map<String, dynamic>?;
              dynamic gasStationIdData;
              dynamic governmentIdData;
              dynamic businessPermitData;

              if (documentImages != null) {
                // New format: base64 images in documentImages field
                gasStationIdData = documentImages['gasStationId'] as String?;
                governmentIdData = documentImages['governmentId'] as String?;
                businessPermitData = documentImages['businessPermit'] as String?;
              } else {
                // Old format: URLs in documentUrls field (fallback)
                final documentUrls = data['documentUrls'] as Map<String, dynamic>?;
                if (documentUrls != null) {
                  gasStationIdData = (documentUrls['gasStationId'] ??
                      documentUrls['gas_station_id'] ??
                      documentUrls['gasStation'] ??
                      documentUrls['stationId']) as String?;

                  governmentIdData = (documentUrls['governmentId'] ??
                      documentUrls['government_id'] ??
                      documentUrls['govId']) as String?;

                  businessPermitData = (documentUrls['businessPermit'] ??
                      documentUrls['business_permit'] ??
                      documentUrls['permit']) as String?;
                }

                // Also check legacy/top-level fields as a fallback
                gasStationIdData = gasStationIdData ?? data['gasStationIdUrl'] as String?;
                governmentIdData = governmentIdData ?? data['governmentIdUrl'] as String?;
                businessPermitData = businessPermitData ?? data['businessPermitUrl'] as String?;
              }

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
                      
                      // Document Images Section (supports both URLs and base64)
                      if (gasStationIdData != null || governmentIdData != null || businessPermitData != null) ...[
                        const Text(
                          'Submitted Documents:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (gasStationIdData != null)
                              _buildDocumentImageCard('Gas Station ID', gasStationIdData),
                            if (governmentIdData != null)
                              _buildDocumentImageCard('Government ID', governmentIdData),
                            if (businessPermitData != null)
                              _buildDocumentImageCard('Business Permit', businessPermitData),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'No documents found for this submission.',
                                  style: TextStyle(color: Colors.orange),
                                ),
                              ),
                            ],
                          ),
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