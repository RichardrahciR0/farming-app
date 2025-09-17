import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class JwtHelper {
  static const _base = "http://10.0.2.2:8000";
  static final _storage = const FlutterSecureStorage();

  static Future<String?> getAccess() => _storage.read(key: "access");
  static Future<String?> getRefresh() => _storage.read(key: "refresh");
  static Future<void> setAccess(String v) => _storage.write(key: "access", value: v);

  static Future<String?> ensureAccessToken() async {
    var access = await getAccess();
    if (access == null) return null;

    final probe = await http.get(
      Uri.parse("$_base/api/profile/"),
      headers: {"Authorization": "Bearer $access"},
    );

    if (probe.statusCode != 401) return access;

    final refresh = await getRefresh();
    if (refresh == null) return null;

    final resp = await http.post(
      Uri.parse("$_base/api/auth/jwt/refresh/"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"refresh": refresh}),
    );

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final newAccess = data["access"] as String?;
      if (newAccess != null) {
        await setAccess(newAccess);
        return newAccess;
      }
    }
    return null;
  }

  static Future<Map<String, String>?> authHeaders() async {
    final access = await ensureAccessToken();
    if (access == null) return null;
    return {
      "Authorization": "Bearer $access",
      "Content-Type": "application/json",
    };
  }
}
