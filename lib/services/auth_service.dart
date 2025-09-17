// lib/services/auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AuthService
/// - Djoser + JWT login
/// - Stores access/refresh in secure storage
/// - Tries multiple base URLs (Android emulator & iOS simulator/desktop)
/// - Exposes helpers for other services to fetch tokens/base URL
class AuthService {
  AuthService._();
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;

  final _storage = const FlutterSecureStorage();

  /// Try these in order. Adjust for your LAN if needed.
  final List<String> _baseUrls = const [
    'http://10.0.2.2:8000',   // Android emulator
    'http://127.0.0.1:8000',  // iOS simulator / macOS / desktop
    'http://192.168.1.101:8000',
    'http://192.168.1.103:8000',
  ];

  String? _lastWorkingBaseUrl;

  Future<http.Response?> _attemptRequest(
    Future<http.Response> Function(String) builder,
  ) async {
    final candidates = <String>[
      if (_lastWorkingBaseUrl != null) _lastWorkingBaseUrl!,
      ..._baseUrls.where((b) => b != _lastWorkingBaseUrl),
    ];

    for (final base in candidates) {
      try {
        final res = await builder(base);
        if (res.statusCode >= 200 && res.statusCode < 500) {
          _lastWorkingBaseUrl = base;
          return res;
        }
      } catch (_) {}
    }
    return null;
  }

  // ---------------- AUTH FLOWS ----------------

  Future<bool> login(String email, String password) async {
    final res = await _attemptRequest(
      (base) => http.post(
        Uri.parse('$base/api/auth/jwt/create/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.toLowerCase(), 'password': password}),
      ),
    );

    if (res != null && res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await _storage.write(key: 'access', value: data['access'] as String?);
      await _storage.write(key: 'refresh', value: data['refresh'] as String?);
      return true;
    }
    return false;
  }

  Future<bool> signup(String email, String username, String password) async {
    final res = await _attemptRequest(
      (base) => http.post(
        Uri.parse('$base/api/auth/users/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.toLowerCase(),
          'username': username,
          'password': password,
          're_password': password,
        }),
      ),
    );

    if (res != null && res.statusCode == 201) return true;
    return false;
  }

  Future<Map<String, dynamic>?> getUser() async {
    final access = await readAccess();
    if (access == null) return null;

    final res = await _attemptRequest(
      (base) => http.get(
        Uri.parse('$base/api/auth/users/me/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $access',
        },
      ),
    );

    if (res != null && res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> logout() async {
    final refresh = await _storage.read(key: 'refresh');
    if (refresh != null) {
      await _attemptRequest(
        (base) => http.post(
          Uri.parse('$base/api/auth/jwt/blacklist/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh': refresh}),
        ),
      );
    }
    await _storage.deleteAll();
  }

  // ---------------- TOKEN HELPERS ----------------

  Future<String?> readAccess() => _storage.read(key: 'access');
  Future<String?> readRefresh() => _storage.read(key: 'refresh');
  Future<void> saveAccess(String token) => _storage.write(key: 'access', value: token);

  Future<String?> refreshAccessToken() async {
    final refresh = await readRefresh();
    if (refresh == null) return null;

    final res = await _attemptRequest(
      (base) => http.post(
        Uri.parse('$base/api/auth/jwt/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refresh}),
      ),
    );

    if (res != null && res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final newAccess = data['access'] as String?;
      if (newAccess != null) {
        await saveAccess(newAccess);
        return newAccess;
      }
    }
    return null;
  }

  String get baseUrl => _lastWorkingBaseUrl ?? _baseUrls.first;
  String? getBaseUrl() => _lastWorkingBaseUrl ?? _baseUrls.first;
}
