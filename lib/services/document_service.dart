// lib/services/document_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class DocumentService {
  /// Store document submission status in user document
  /// Since documents are sent via email, we only track submission status
  static Future<void> storeDocumentSubmissionStatus({
    required String userId,
    required bool documentsSubmitted,
    String? approvalStatus,
  }) async {
    try {
      final updateData = {
        'documentsSubmitted': documentsSubmitted,
        'submittedAt': FieldValue.serverTimestamp(),
      };

      if (approvalStatus != null) {
        updateData['approvalStatus'] = approvalStatus;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update(updateData);
    } catch (e) {
      print('Error storing document submission status: $e');
      throw e;
    }
  }

  /// Get document submission status for a user
  static Future<Map<String, dynamic>> getDocumentSubmissionStatus(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        return {
          'documentsSubmitted': false,
          'approvalStatus': null,
        };
      }

      final data = userDoc.data() as Map<String, dynamic>;
      return {
        'documentsSubmitted': data['documentsSubmitted'] ?? false,
        'approvalStatus': data['approvalStatus'],
        'submittedAt': data['submittedAt'],
      };
    } catch (e) {
      print('Error getting document submission status: $e');
      return {
        'documentsSubmitted': false,
        'approvalStatus': null,
      };
    }
  }

  /// Update approval status for user documents
  static Future<void> updateApprovalStatus({
    required String userId,
    required String approvalStatus,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
            'approvalStatus': approvalStatus,
            'approvedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error updating approval status: $e');
      throw e;
    }
  }
}
