import 'package:flutter/foundation.dart';

class AppConfig {
  static const _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  // Android emulator reaches host machine via 10.0.2.2.
  static const androidBaseUrl = 'http://10.0.2.2:3000';
  static const iosBaseUrl = 'http://localhost:3000';

  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    if (defaultTargetPlatform == TargetPlatform.android) return androidBaseUrl;
    return iosBaseUrl;
  }
}
