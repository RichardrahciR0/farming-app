import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Replace with same IP as auth backend if needed
  final baseUrl = "http://10.0.2.2:8001/api";

  Future<List<Map<String, dynamic>>> fetchCrops() async {
    final response = await http.get(Uri.parse('$baseUrl/crops/'));
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load crops: ${response.statusCode}');
    }
  }

  Future<bool> addCrop(String name, String spacing, String harvest) async {
    final response = await http.post(
      Uri.parse('$baseUrl/crops/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'spacing': spacing,
        'harvest': harvest,
      }),
    );
    return response.statusCode == 201;
  }

  Future<bool> updateCrop(int id, String name, String spacing, String harvest) async {
    final response = await http.put(
      Uri.parse('$baseUrl/crops/$id/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'spacing': spacing,
        'harvest': harvest,
      }),
    );
    return response.statusCode == 200;
  }

  Future<bool> deleteCrop(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/crops/$id/'),
    );
    return response.statusCode == 204;
  }
}
