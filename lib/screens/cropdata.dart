import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:farmapp/models/crop.dart';

class CropDataPage extends StatefulWidget {
  @override
  _CropDataPageState createState() => _CropDataPageState();
}

class _CropDataPageState extends State<CropDataPage> {
  List<Crop> _crops = [];
  List<Crop> _filteredCrops = [];
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchCrops();
    _searchCtrl.addListener(() {
      filterCrops(_searchCtrl.text);
    });
  }

  Future<void> _fetchCrops() async {
    try {
      final response =
          await http.get(Uri.parse('http://10.0.2.2:8001/api/crops/'));

      print("🟢 Status Code: ${response.statusCode}");
      print("🟢 Response Body: ${response.body}");

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _crops = data.map((json) => Crop.fromJson(json)).toList();
          _filteredCrops = _crops;
          _isLoading = false;
        });
      } else {
        throw Exception(
            "Failed to load crops - Status Code: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching crops: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void filterCrops(String query) {
    final filtered = _crops
        .where((crop) => crop.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    setState(() {
      _filteredCrops = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Crop Database"),
        backgroundColor: Colors.green[700],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search Crops',
                prefixIcon: Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          _isLoading
              ? const Expanded(
                  child: Center(child: CircularProgressIndicator()))
              : Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _filteredCrops.length,
                    itemBuilder: (context, index) {
                      final crop = _filteredCrops[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(2, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            crop.imagePath != null && crop.imagePath!.isNotEmpty
                                ? Image.network(
                                    crop.imagePath!,
                                    height: 50,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image,
                                        size: 40),
                                  )
                                : const Icon(Icons.image, size: 40),
                            const SizedBox(height: 10),
                            Text(
                              crop.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}
