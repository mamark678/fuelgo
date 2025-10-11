// lib/services/email_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';

class EmailService {
  static const String serviceId = "service_yzmk22f";
  static const String templateId = "template_z7zcqww";
  static const String userId = "kZ2vMIaMKYU2murtt"; // EmailJS public key

  /// Generic send. `message` may contain simple HTML if your EmailJS template uses it.
  static Future<bool> sendEmail({
    required String toEmail,
    required String subject,
    required String message,
  }) async {
    final url = Uri.parse("https://api.emailjs.com/api/v1.0/email/send");

    final payload = {
      "service_id": serviceId,
      "template_id": templateId,
      "user_id": userId,
      "template_params": {
        "to_email": toEmail,
        "subject": subject,
        "message": message,
      }
    };

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print("❌ EmailJS returned ${response.statusCode}: ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ EmailJS error: $e");
      return false;
    }
  }

  /// Convenience: send to multiple admins (one request per admin).
  static Future<void> sendEmailToAdmins({
    required List<String> adminEmails,
    required String subject,
    required String message,
  }) async {
    for (final email in adminEmails) {
      // Best-effort fire-and-forget per admin; you may want to handle failures differently.
      final ok = await sendEmail(toEmail: email, subject: subject, message: message);
      if (!ok) {
        print('Failed to send admin notification to $email');
      }
    }
  }

  /// Send email with base64 encoded images (for document attachments)
  static Future<bool> sendEmailWithImages({
    required String toEmail,
    required String subject,
    required String htmlMessage,
    Map<String, String>? base64Images, // filename -> base64 content
  }) async {
    final url = Uri.parse("https://api.emailjs.com/api/v1.0/email/send");

    // Prepare template parameters
    final templateParams = {
      "to_email": toEmail,
      "subject": subject,
      "message": htmlMessage,
    };

    // Add base64 images to template params if provided
    if (base64Images != null) {
      base64Images.forEach((filename, base64Content) {
        templateParams[filename] = base64Content;
      });
    }

    final payload = {
      "service_id": serviceId,
      "template_id": templateId,
      "user_id": userId,
      "template_params": templateParams,
    };

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print("❌ EmailJS returned ${response.statusCode}: ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ EmailJS error: $e");
      return false;
    }
  }
}
