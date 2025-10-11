// lib/services/email_processor_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class EmailProcessorService {
  static const String gmailUsername = 'fuelgosystem@gmail.com';
  static const String gmailPassword = 'yneb dhkm iqax nnkt'; // Your Gmail app password
  
  /// Main method to check for admin replies and process them
  static Future<void> processAdminReplies() async {
    try {
      print('🔍 Checking Gmail for admin replies...');
      
      // Connect to Gmail IMAP
      final client = ImapClient(isLogEnabled: false);
      await client.connectToServer('imap.gmail.com', 993, isSecure: true);
      await client.login(gmailUsername, gmailPassword);
      await client.selectInbox();
      
      // Search for unread emails with APPROVE or REJECT in subject
      final searchResult = await client.searchMessages(
        searchCriteria: 'UNSEEN SUBJECT "APPROVE" OR SUBJECT "REJECT"',
      );
      
      print('📧 Found ${searchResult.matchingSequence?.length ?? 0} unread admin replies');
      
      // Process each reply
      if (searchResult.matchingSequence != null && searchResult.matchingSequence!.isNotEmpty) {
        final messages = await client.fetchMessages(
          searchResult.matchingSequence!,
          'BODY.PEEK[]'
        );
        
        for (final message in messages.messages) {
          await _handleAdminReply(message);
          
          // Mark as read after processing
          await client.markSeen(MessageSequence.fromMessage(message));
        }
      }
      
      await client.logout();
      print('✅ Admin reply processing completed');
      
    } catch (e) {
      print('❌ Error processing admin replies: $e');
    }
  }
  
  /// Process individual admin reply email
  static Future<void> _handleAdminReply(MimeMessage message) async {
    try {
      final subject = message.decodeSubject() ?? '';
      final body = message.decodeTextPlainPart() ?? '';
      
      print('📨 Processing reply: $subject');
      
      String? decision;
      String? userId;
      String? reason;
      
      // Parse decision and user ID from subject
      if (subject.startsWith('APPROVE ')) {
        decision = 'approved';
        userId = subject.substring(8).trim();
      } else if (subject.startsWith('REJECT ')) {
        decision = 'rejected';
        userId = subject.substring(7).trim();
      }
      
      if (decision == null || userId == null || userId.isEmpty) {
        print('❌ Invalid subject format: $subject');
        return;
      }
      
      // Extract reason from email body
      final bodyLines = body.split('\n');
      for (final line in bodyLines) {
        final trimmedLine = line.trim();
        if (trimmedLine.toLowerCase().contains('reason:')) {
          reason = trimmedLine.substring(trimmedLine.indexOf(':') + 1).trim();
          break;
        } else if (trimmedLine.toLowerCase().contains('optional reason:')) {
          reason = trimmedLine.substring(trimmedLine.indexOf(':') + 1).trim();
          break;
        }
      }
      
      // Remove empty reasons
      if (reason != null && reason.isEmpty) {
        reason = null;
      }
      
      print('📋 Decision: $decision for user: $userId');
      if (reason != null) print('📝 Reason: $reason');
      
      // Update user status in Firestore
      await _updateUserStatus(userId, decision, reason);
      
      // Send notification email to the user
      await _sendUserNotification(userId, decision, reason);
      
      print('✅ Successfully processed reply for user: $userId');
      
    } catch (e) {
      print('❌ Error handling admin reply: $e');
    }
  }
  
  /// Update user approval status in Firestore
  static Future<void> _updateUserStatus(String userId, String decision, String? reason) async {
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
      final userDoc = await userRef.get();
      
      if (!userDoc.exists) {
        print('❌ User not found: $userId');
        return;
      }
      
      final updateData = {
        'approvalStatus': decision,
        'processedAt': FieldValue.serverTimestamp(),
      };
      
      if (reason != null) {
        updateData['approvalReason'] = reason;
      }
      
      await userRef.update(updateData);
      print('✅ Updated user status: $userId -> $decision');
      
    } catch (e) {
      print('❌ Error updating user status: $e');
      rethrow;
    }
  }
  
  /// Send notification email to the gas station owner
  static Future<void> _sendUserNotification(String userId, String decision, String? reason) async {
    try {
      // Get user details from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      if (!userDoc.exists) {
        print('❌ User not found for notification: $userId');
        return;
      }
      
      final userData = userDoc.data()!;
      final userName = userData['name'] as String;
      final userEmail = userData['email'] as String;
      final stationName = userData['stationName'] as String?;
      
      final isApproved = decision == 'approved';
      final statusText = isApproved ? 'APPROVED' : 'REJECTED';
      final statusIcon = isApproved ? '✅' : '❌';
      final statusColor = isApproved ? 'green' : 'red';
      
      // Create email content
      String emailText = '''
Dear $userName,

Your gas station owner registration has been $statusText.

Registration Details:
- Name: $userName
- Station Name: ${stationName ?? 'Not specified'}
- Status: $statusText
- Processed: ${DateTime.now().toLocal().toString()}
''';

      if (reason != null && reason.isNotEmpty) {
        emailText += '\n${isApproved ? 'Note' : 'Reason'}: $reason\n';
      }

      if (isApproved) {
        emailText += '''

🎉 Congratulations! You can now log in to your FuelGo owner account and start managing your gas station.

Next Steps:
1. Log in to your FuelGo owner account
2. Update your station information and fuel prices
3. Start serving customers through the FuelGo platform

Thank you for choosing FuelGo!
''';
      } else {
        emailText += '''

If you believe this decision was made in error or would like to resubmit your application, please contact our support team.

Thank you for your interest in FuelGo.
''';
      }

      emailText += '''

---
This is an automated message from FuelGo System.
Please do not reply to this email.
''';

      // Create HTML version
      String emailHtml = '''
<html>
<body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
  <div style="background-color: $statusColor; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0;">
    <h1>$statusIcon Registration $statusText</h1>
  </div>
  
  <div style="padding: 20px; border: 1px solid #ddd; border-top: none; border-radius: 0 0 8px 8px;">
    <p>Dear <strong>$userName</strong>,</p>
    
    <p>Your gas station owner registration has been <strong style="color: $statusColor;">$statusText</strong>.</p>
    
    <div style="background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin: 20px 0;">
      <h3>Registration Details:</h3>
      <ul style="list-style: none; padding: 0;">
        <li><strong>Name:</strong> $userName</li>
        <li><strong>Station:</strong> ${stationName ?? 'Not specified'}</li>
        <li><strong>Status:</strong> <span style="color: $statusColor; font-weight: bold;">$statusText</span></li>
        <li><strong>Processed:</strong> ${DateTime.now().toLocal().toString().split('.')[0]}</li>
      </ul>
      ${reason != null && reason.isNotEmpty ? '<p><strong>${isApproved ? 'Note' : 'Reason'}:</strong> $reason</p>' : ''}
    </div>
''';

      if (isApproved) {
        emailHtml += '''
    <div style="background-color: #d4edda; padding: 15px; border-radius: 5px; margin: 20px 0; border-left: 4px solid #28a745;">
      <h3 style="color: #155724;">🎉 Congratulations!</h3>
      <p style="color: #155724;">You can now log in to your FuelGo owner account and start managing your gas station.</p>
      
      <h4 style="color: #155724;">Next Steps:</h4>
      <ol style="color: #155724;">
        <li>Log in to your FuelGo owner account</li>
        <li>Update your station information and fuel prices</li>
        <li>Start serving customers through the FuelGo platform</li>
      </ol>
    </div>
''';
      } else {
        emailHtml += '''
    <div style="background-color: #f8d7da; padding: 15px; border-radius: 5px; margin: 20px 0; border-left: 4px solid #dc3545;">
      <p style="color: #721c24;">If you believe this decision was made in error or would like to resubmit your application, please contact our support team.</p>
    </div>
''';
      }

      emailHtml += '''
    <p>Thank you for ${isApproved ? 'choosing' : 'your interest in'} FuelGo!</p>
    
    <hr style="margin: 30px 0; border: 1px solid #eee;">
    <p style="font-size: 12px; color: #6c757d; text-align: center;">
      This is an automated message from FuelGo System.<br>
      Please do not reply to this email.
    </p>
  </div>
</body>
</html>
''';

      // Send the email
      final smtpServer = gmail(gmailUsername, gmailPassword);
      
      final message = Message()
        ..from = Address(gmailUsername, 'FuelGo System')
        ..recipients.add(userEmail)
        ..subject = 'FuelGo Registration $statusText - $userName'
        ..text = emailText
        ..html = emailHtml;
      
      await send(message, smtpServer);
      
      print('✅ Notification email sent to: $userEmail');
      
    } catch (e) {
      print('❌ Error sending notification email: $e');
      rethrow;
    }
  }
}