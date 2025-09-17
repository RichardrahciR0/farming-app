import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'jwt_helper.dart';

/// Saves/loads the user's dashboard layout to Django.
/// Uses JwtHelper for auto-refreshing tokens.
class DashboardService {
  DashboardService({
    AuthService? auth,
    List<String>? baseUrls,
  }) : _auth = auth ?? AuthService() {
    final preferred = _auth.getBaseUrl(); // legacy compat from AuthService
    final defaults = <String>[
      'http://10.0.2.2:8000',  // Android emulator -> host machine
      'http://127.0.0.1:8000', // iOS simulator / desktop
      'http://192.168.1.101:8000',
      'http://192.168.1.103:8000',
    ];
    _baseUrls = <String>{
      if (preferred != null) preferred,
      ...defaults,
      if (baseUrls != null) ...baseUrls,
    }.toList(growable: false);
  }

  final AuthService _auth;
  late final List<String> _baseUrls;

  Future<http.Response?> _attemptRequest(
    Future<http.Response> Function(String baseUrl, Map<String, String> headers) builder,
  ) async {
    final headers = await JwtHelper.authHeaders();
    if (headers == null) {
      _log('No auth headers (not logged in or refresh failed).');
      return null;
    }
    for (final base in _baseUrls) {
      try {
        final resp = await builder(base, headers);
        _log('[$base] -> ${resp.statusCode}');
        return resp;
      } catch (e) {
        _log('[$base] network error: $e');
      }
    }
    return null;
  }

  /// POST /api/dashboard/
  Future<bool> saveLayout(List<Map<String, dynamic>> widgets) async {
    final body = jsonEncode({'widgets': widgets});
    _log('Saving layout with ${widgets.length} items…');

    final resp = await _attemptRequest((base, headers) {
      final url = Uri.parse('$base/api/dashboard/');
      _log('POST $url');
      _log('Request JSON: $body');
      return http.post(url, headers: headers, body: body);
    });

    if (resp == null) return false;
    _log('Response ${resp.statusCode}: ${resp.body}');
    return resp.statusCode == 200 || resp.statusCode == 201;
  }

  /// GET /api/dashboard/
  Future<List<Map<String, dynamic>>> loadLayout() async {
    final resp = await _attemptRequest((base, headers) {
      final url = Uri.parse('$base/api/dashboard/');
      _log('GET $url');
      return http.get(url, headers: headers);
    });

    if (resp == null) return [];
    _log('Response ${resp.statusCode}: ${resp.body}');
    if (resp.statusCode == 200) {
      try {
        final data = jsonDecode(resp.body);
        final raw = data['widgets'];
        if (raw is List) {
          return List<Map<String, dynamic>>.from(raw);
        }
      } catch (e) {
        _log('JSON decode error: $e');
      }
    }
    return [];
  }

  void _log(String msg) {
    if (kDebugMode) print('[DASHBOARD] $msg');
  }
}
