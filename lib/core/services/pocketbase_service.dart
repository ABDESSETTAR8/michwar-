import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base URL for the self-hosted PocketBase server.
///
/// - Android emulator: `10.0.2.2` reaches the host machine's `localhost`.
/// - iOS simulator / web / desktop: `127.0.0.1` works directly.
/// - Real device (e.g. a downloaded APK) on the same Wi-Fi: replace with
///   your computer's LAN IP, e.g. `http://192.168.1.50:8090`.
/// - Production: point at your deployed PocketBase URL, e.g.
///   `https://api.michwar.example.com`.
///
/// Override at build/run time with:
///   `flutter run --dart-define=POCKETBASE_URL=http://192.168.1.50:8090`
String pocketbaseBaseUrl() {
  const override = String.fromEnvironment('POCKETBASE_URL');
  if (override.isNotEmpty) return override;

  if (kIsWeb) return 'http://127.0.0.1:8090';
  if (Platform.isAndroid) return 'http://10.0.2.2:8090';
  return 'http://127.0.0.1:8090';
}

/// Wraps the app-wide [PocketBase] client. The auth session (token + user
/// record) is persisted across restarts via [AsyncAuthStore] backed by
/// `shared_preferences`, replacing Firebase Auth's automatic session
/// persistence.
class PocketBaseService {
  PocketBaseService._(this.pb);

  final PocketBase pb;

  static PocketBaseService? _instance;

  /// Must be awaited once during app startup (see `main.dart`) before the
  /// `pocketbaseProvider` override is installed.
  static Future<PocketBaseService> getInstance() async {
    if (_instance != null) return _instance!;

    final prefs = await SharedPreferences.getInstance();

    final store = AsyncAuthStore(
      save: (String data) async => prefs.setString('pb_auth', data),
      initial: prefs.getString('pb_auth'),
      clear: () async => prefs.remove('pb_auth'),
    );

    final pb = PocketBase(pocketbaseBaseUrl(), authStore: store);
    _instance = PocketBaseService._(pb);
    return _instance!;
  }
}
