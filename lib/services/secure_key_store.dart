import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureKeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _apiKeyField = 'mimo_api_key';

  final FlutterSecureStorage _storage;

  Future<void> saveApiKey(String apiKey) {
    return _storage.write(key: _apiKeyField, value: apiKey.trim());
  }

  Future<String?> readApiKey() {
    return _storage.read(key: _apiKeyField);
  }

  Future<void> clearApiKey() {
    return _storage.delete(key: _apiKeyField);
  }

  String mask(String? apiKey) {
    final String value = apiKey?.trim() ?? '';
    if (value.isEmpty) {
      return '未填写';
    }
    if (value.length <= 4) {
      return '*' * value.length;
    }
    return '${'*' * (value.length - 4)}${value.substring(value.length - 4)}';
  }
}
