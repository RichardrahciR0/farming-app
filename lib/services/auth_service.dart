import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  final _storage = FlutterSecureStorage();

  // Replace with your actual backend IP if testing on a real device
  final String _baseUrl = 'http://192.168.1.103:8000';

  // LOGIN
  Future<bool> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/jwt/create/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.toLowerCase(), // ✅ lowercase for consistency
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _storage.write(key: 'access', value: data['access']);
        await _storage.write(key: 'refresh', value: data['refresh']);
        return true;
      } else {
        print('Login failed: ${response.statusCode}');
        print('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  // SIGN UP
  Future<bool> signup(String email, String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/users/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.toLowerCase(), // ✅ lowercase for consistency
          'username': username,
          'password': password,
          're_password': password,
        }),
      );

      if (response.statusCode == 201) {
        return true;
      } else {
        print('Signup failed: ${response.statusCode}');
        print('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Signup error: $e');
      return false;
    }
  }

  // GET USER DETAILS
  Future<Map<String, dynamic>?> getUser() async {
    try {
      final accessToken = await _storage.read(key: 'access');
      final response = await http.get(
        Uri.parse('$_baseUrl/auth/users/me/'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print("Failed to fetch user: ${response.statusCode}");
        print("Response: ${response.body}");
        return null;
      }
    } catch (e) {
      print('User fetch error: $e');
      return null;
    }
  }

  // LOGOUT
  Future<void> logout() async {
    await _storage.deleteAll();
  }
}
