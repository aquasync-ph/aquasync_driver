import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConfig {
  static String get url {
    final v = dotenv.env['SUPABASE_URL'];
    return (v != null && v.trim().isNotEmpty)
        ? v.trim()
        : 'https://qxruxonusvoxshuwxrah.supabase.co';
  }

  static String get anonKey {
    final v = dotenv.env['SUPABASE_ANON_KEY'];
    return (v != null && v.trim().isNotEmpty)
        ? v.trim()
        : 'sb_publishable_MbMRR6syNwtezcWMke6yXw_Y1cozFRo';
  }
}
