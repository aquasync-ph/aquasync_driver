import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConfig {
  static String get url {
    final raw = dotenv.env['SUPABASE_URL'] ?? '';
    final match = RegExp(r'https?://[^\s\)\]"]+').firstMatch(raw);
    if (match != null) {
      return match.group(0)!;
    }
    return 'https://qxruxonusvoxshuwxrah.supabase.co';
  }

  static String get anonKey {
    final raw = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    final cleaned = raw.replaceAll(RegExp(r'[\s\"\'\]\[\)]'), '');
    if (cleaned.isNotEmpty) {
      return cleaned;
    }
    return 'sb_publishable_MbMRR6syNwtezcWMke6yXw_Y1cozFRo';
  }
}
