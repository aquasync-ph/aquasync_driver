import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'env_config.dart';

class BrevoService {
  static const String _apiUrl = 'https://api.brevo.com/v3/smtp/email';

  /// Sends a transactional email using Brevo API v3 with the BREVO_API_KEY loaded from environment variables.
  static Future<bool> sendEmail({
    required String toEmail,
    required String subject,
    required String htmlContent,
    String? toName,
    String senderEmail = 'noreply@aquasync.com',
    String senderName = 'AquaSync Driver',
  }) async {
    final apiKey = EnvConfig.brevoApiKey;
    if (apiKey.isEmpty) {
      debugPrint('BrevoService: BREVO_API_KEY is not configured in environment.');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'accept': 'application/json',
          'api-key': apiKey,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'sender': {
            'name': senderName,
            'email': senderEmail,
          },
          'to': [
            {
              'email': toEmail,
              if (toName != null && toName.isNotEmpty) 'name': toName,
            }
          ],
          'subject': subject,
          'htmlContent': htmlContent,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        debugPrint('BrevoService: Email successfully sent to $toEmail');
        return true;
      } else {
        debugPrint(
          'BrevoService: Failed to send email (Status: ${response.statusCode}): ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('BrevoService error: $e');
      return false;
    }
  }
}
