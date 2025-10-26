import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://192.168.1.106:8000/api';

  // Save JWT tokens after login
  static Future<void> saveTokens(String accessToken, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', accessToken);
    await prefs.setString('refresh_token', refreshToken);
  }

  // Get access token from storage
  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  // Save dashboard layout to backend
  static Future<bool> saveDashboardConfig(List<Map<String, dynamic>> widgets) async {
    final token = await getAccessToken();
    if (token == null) return false;

    final url = Uri.parse('$baseUrl/dashboard/');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'widgets': widgets}),
    );

    return response.statusCode == 200 || response.statusCode == 201;
  }

  // Load dashboard layout from backend
  static Future<List<Map<String, dynamic>>> loadDashboardConfig() async {
    final token = await getAccessToken();
    if (token == null) return [];

    final url = Uri.parse('$baseUrl/dashboard/');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['widgets']);
    }

    return [];
  }
}
