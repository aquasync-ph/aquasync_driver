import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'supabase_config.dart';

class EnvConfig {
  static bool _initialized = false;

  /// Initializes flutter_dotenv to load environment configuration from .env asset
  static Future<void> init() async {
    if (_initialized) return;
    try {
      await dotenv.load(fileName: ".env");
      _initialized = true;
    } catch (e) {
      debugPrint('Warning: Could not load .env file: $e');
    }
  }

  /// Supabase Project URL
  static String get supabaseUrl => SupabaseConfig.url;

  /// Supabase Publishable / Anon Key
  static String get supabaseAnonKey => SupabaseConfig.anonKey;

  /// Brevo API Key for sending emails
  static String get brevoApiKey => dotenv.env['BREVO_API_KEY'] ?? '';
}
