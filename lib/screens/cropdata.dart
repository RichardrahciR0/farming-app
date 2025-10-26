// lib/screens/cropdata.dart
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../models/crop.dart';

/// ===========================
/// Environment helpers
/// ===========================
String get kBaseUrl {
  final host = Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';
  return 'http://$host:8000';
}

/// Provide JWT here if your local crops API requires auth.
Future<String?> getAccessToken() async {
  // TODO: Wire up real token if needed (e.g., from secure storage)
  return null;
}

/// ===========================
/// Built-in catalog (offline)
/// ===========================
class _BuiltinInfo {
  final String name;
  final String assetPath;
  final double? spacingMeters;
  final String? harvestTime;
  final List<String> stages;
  final String? pestNotes;

  const _BuiltinInfo({
    required this.name,
    required this.assetPath,
    this.spacingMeters,
    this.harvestTime,
    this.stages = const [],
    this.pestNotes,
  });

  Map<String, dynamic> toJsonMap() => {
        'id': null,
        'name': name,
        'image_path': assetPath, // stays asset path; we detect it in UI
        'spacing': spacingMeters,
        'harvest_time': harvestTime,
        'growth_stages': stages,
        'pest_notes': pestNotes,
      };
}

const Map<String, _BuiltinInfo> _builtinByName = {
  'tomato': _BuiltinInfo(
    name: 'Tomato',
    assetPath: 'media/tomato.png',
    spacingMeters: 0.45,
    harvestTime: '70–100 days',
    stages: ['Seedling', 'Vegetative', 'Flowering', 'Fruit Set', 'Harvest'],
    pestNotes:
        'Watch for aphids, whiteflies, and early/late blight. Avoid wet foliage; rotate beds yearly.',
  ),
  'mint': _BuiltinInfo(
    name: 'Mint',
    assetPath: 'media/mint.png',
    spacingMeters: 0.30,
    harvestTime: '60–90 days (cut-and-come-again)',
    stages: ['Seedling', 'Vegetative', 'Cutback/Regrow', 'Harvest'],
    pestNotes:
        'Prone to rust and aphids; contain roots (spreads aggressively). Keep moist but not soggy.',
  ),
  'coriander': _BuiltinInfo(
    name: 'Coriander',
    assetPath: 'media/coriander.png',
    spacingMeters: 0.20,
    harvestTime: '40–55 days (leaf); 90–120 (seed)',
    stages: ['Seedling', 'Vegetative', 'Bolting', 'Seed'],
    pestNotes:
        'Prefers cool temps; bolts quickly in heat. Watch for aphids and damping-off.',
  ),
  'chives': _BuiltinInfo(
    name: 'Chives',
    assetPath: 'media/chives.png',
    spacingMeters: 0.25,
    harvestTime: '60–80 days',
    stages: ['Seedling', 'Clumping', 'Flowering', 'Harvest'],
    pestNotes: 'Generally tough; occasional thrips/aphids. Divide clumps yearly.',
  ),
  'parsley': _BuiltinInfo(
    name: 'Parsley',
    assetPath: 'media/parsley.png',
    spacingMeters: 0.25,
    harvestTime: '70–90 days',
    stages: ['Seedling', 'Vegetative', 'Cutback/Regrow', 'Harvest'],
    pestNotes: 'Slow starter. Check for caterpillars; harvest outer stems first.',
  ),
  'dill': _BuiltinInfo(
    name: 'Dill',
    assetPath: 'media/dill.png',
    spacingMeters: 0.30,
    harvestTime: '40–60 days (leaf), 85–100 (seed)',
    stages: ['Seedling', 'Vegetative', 'Flowering', 'Seed'],
    pestNotes:
        'Attracts beneficial insects. Susceptible to strong winds; may need staking.',
  ),
  'kale': _BuiltinInfo(
    name: 'Kale',
    assetPath: 'media/kale.png',
    spacingMeters: 0.45,
    harvestTime: '55–75 days',
    stages: ['Seedling', 'Vegetative', 'Leaf Harvest', 'Overwinter'],
    pestNotes: 'Cabbage moths, aphids. Netting helps. Thrives in cool temps.',
  ),
  'asparagus': _BuiltinInfo(
    name: 'Asparagus',
    assetPath: 'media/asparagus.png',
    spacingMeters: 0.45,
    harvestTime: 'Full harvest from year 3',
    stages: ['Crown Establishment', 'Ferns', 'Dormancy', 'Harvest'],
    pestNotes:
        'Perennial. Keep bed weed-free. Watch for asparagus beetle; do not overharvest early years.',
  ),
  'wheat': _BuiltinInfo(
    name: 'Wheat',
    assetPath: 'media/wheat.jpeg',
    spacingMeters: 0.10,
    harvestTime: '90–120 days',
    stages: ['Germination', 'Tillering', 'Booting', 'Heading', 'Ripening'],
    pestNotes: 'Monitor rust, smut, and aphids. Needs full sun, moderate water.',
  ),
};

List<Crop> _builtInCatalog([String query = '']) {
  final q = query.trim().toLowerCase();
  final entries = _builtinByName.values.where((b) {
    if (q.isEmpty) return true;
    return b.name.toLowerCase().contains(q);
  });
  return entries.map((b) => Crop.fromJson(b.toJsonMap())).toList(growable: false);
}

/// ===========================
/// Page (Built-in + Local + Add)
/// ===========================
class CropDataPage extends StatefulWidget {
  const CropDataPage({super.key});

  @override
  State<CropDataPage> createState() => _CropDataPageState();
}

class _CropDataPageState extends State<CropDataPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<Crop> _all = [];       // merged built-in + local
  List<Crop> _filtered = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _loadAll(initial: true);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  /// ===========================
  /// Helpers
  /// ===========================
  List<Crop> _parseCropListFromBody(String body) {
    final data = jsonDecode(body);
    if (data is List) {
      return data.map((e) => Crop.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (data is Map && data['results'] is List) {
      return (data['results'] as List)
          .map((e) => Crop.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  ImageProvider? _imageProviderFor(Crop c) {
    final path = c.imagePath;
    if (path.isEmpty) return null;

    // Asset in /media
    if (!path.startsWith('http') && !path.startsWith('/')) {
      return AssetImage(path);
    }

    // Local Django served '/media/...'
    if (path.startsWith('/')) {
      return NetworkImage('$kBaseUrl$path');
    }

    // Full URL already
    return NetworkImage(path);
  }

  List<Crop> _filterByQuery(List<Crop> src, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List.of(src);
    return src.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  void _onSearchChanged() {
    setState(() {
      _filtered = _filterByQuery(_all, _searchCtrl.text);
    });
  }

  /// ===========================
  /// Local API
  /// ===========================
  Future<List<Crop>> _fetchLocalCrops() async {
    final uri = Uri.parse('$kBaseUrl/api/crops/');
    final token = await getAccessToken();
    final resp = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (resp.statusCode == 200) {
      return _parseCropListFromBody(resp.body);
    } else if (resp.statusCode == 401) {
      throw Exception('Unauthorized (401)');
    } else {
      throw Exception('Server error: ${resp.statusCode}');
    }
  }

  Future<Crop> _createCrop(Map<String, dynamic> payload) async {
    final uri = Uri.parse('$kBaseUrl/api/crops/');
    final token = await getAccessToken();
    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );
    if (resp.statusCode == 201 || resp.statusCode == 200) {
      return Crop.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw Exception('Create failed: ${resp.statusCode} ${resp.body}');
  }

  Future<Crop> _createCropMultipart({
    required Map<String, String> fields,
    File? imageFile,
  }) async {
    final uri = Uri.parse('$kBaseUrl/api/crops/');
    final token = await getAccessToken();

    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll({
        if (token != null) 'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });

    fields.forEach((k, v) {
      if (v.isNotEmpty) req.fields[k] = v;
    });

    if (imageFile != null) {
      final ext = p.extension(imageFile.path).toLowerCase();
      final mime = (ext == '.png')
          ? MediaType('image', 'png')
          : (ext == '.webp')
              ? MediaType('image', 'webp')
              : MediaType('image', 'jpeg');

      req.files.add(await http.MultipartFile.fromPath(
        'image', // Django ImageField name
        imageFile.path,
        contentType: mime,
        filename: p.basename(imageFile.path),
      ));
    }

    final resp = await req.send();
    final body = await resp.stream.bytesToString();

    if (resp.statusCode == 201 || resp.statusCode == 200) {
      return Crop.fromJson(jsonDecode(body) as Map<String, dynamic>);
    }
    throw Exception('Create (multipart) failed: ${resp.statusCode} $body');
  }

  Future<void> _deleteCrop(int id) async {
    final uri = Uri.parse('$kBaseUrl/api/crops/$id/');
    final token = await getAccessToken();
    final resp = await http.delete(
      uri,
      headers: {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('Delete failed: ${resp.statusCode} ${resp.body}');
    }
  }

  /// ===========================
  /// Unified load (Built-in + Local)
  /// ===========================
  Future<void> _loadAll({bool initial = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final builtins = _builtInCatalog(_searchCtrl.text);
      List<Crop> locals = [];
      try {
        locals = await _fetchLocalCrops();
      } catch (e) {
        // Don’t fail page for a 401/5xx — just show built-ins and message.
        _error = e.toString();
      }

      // Merge: built-ins first, then locals. (Optionally de-dupe by name)
      final merged = <Crop>[];
      final seen = <String>{};
      for (final c in [...builtins, ...locals]) {
        final key = c.name.trim().toLowerCase();
        if (!seen.contains(key)) {
          seen.add(key);
          merged.add(c);
        }
      }

      _all = merged;
      _filtered = _filterByQuery(merged, _searchCtrl.text);
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _all = [];
        _filtered = [];
      });
    }
  }

  Future<void> _onRefresh() => _loadAll();

  /// ===========================
  /// Add Crop UI (creates Local)
  /// ===========================
  Future<void> _showAddCropSheet() async {
    final nameCtrl = TextEditingController();
    final spacingCtrl = TextEditingController();
    final harvestCtrl = TextEditingController();
    final stagesCtrl = TextEditingController(); // comma-separated
    final pestsCtrl = TextEditingController();
    File? imageFile;

    Future<void> pickImage() async {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (picked != null) {
        imageFile = File(picked.path);
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image selected')),
        );
      }
    }

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Add Crop',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: spacingCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Spacing (meters)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: harvestCtrl,
                  decoration: const InputDecoration(labelText: 'Harvest Time (e.g. 70–100 days)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: stagesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Growth Stages (comma-separated)',
                    hintText: 'Seedling, Vegetative, Flowering, Harvest',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pestsCtrl,
                  decoration: const InputDecoration(labelText: 'Pest Notes'),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: pickImage,
                      icon: const Icon(Icons.image),
                      label: const Text('Pick Image (optional)'),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'If no image is selected, the crop will be created without an image.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Create'),
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Name is required')),
                        );
                        return;
                      }

                      // Prepare fields for multipart (string-only).
                      final fields = <String, String>{
                        'name': name,
                        if (spacingCtrl.text.trim().isNotEmpty)
                          'spacing': spacingCtrl.text.trim(),
                        if (harvestCtrl.text.trim().isNotEmpty)
                          'harvest_time': harvestCtrl.text.trim(),
                        if (stagesCtrl.text.trim().isNotEmpty)
                          // Send JSON list as string; adjust if your API expects CSV
                          'growth_stages': jsonEncode(
                            stagesCtrl.text
                                .split(',')
                                .map((s) => s.trim())
                                .where((s) => s.isNotEmpty)
                                .toList(),
                          ),
                        if (pestsCtrl.text.trim().isNotEmpty)
                          'pest_notes': pestsCtrl.text.trim(),
                      };

                      try {
                        // Prefer multipart when image is present; else JSON create.
                        final created = imageFile != null
                            ? await _createCropMultipart(fields: fields, imageFile: imageFile)
                            : await _createCrop(fields.map((k, v) => MapEntry(k, v)));

                        // Update lists in memory
                        setState(() {
                          _all = [..._all, created];
                          _filtered = _filterByQuery(_all, _searchCtrl.text);
                        });
                        // ignore: use_build_context_synchronously
                        Navigator.pop(ctx);
                        // ignore: use_build_context_synchronously
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Created "${created.name}"')),
                        );
                      } catch (e) {
                        // ignore: use_build_context_synchronously
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Create failed: $e')),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// ===========================
  /// Build
  /// ===========================
  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : (_error != null && _all.isEmpty)
            ? Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              )
            : (_filtered.isEmpty)
                ? const Center(child: Text('No crops to display.'))
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final crop = _filtered[i];
                      final provider = _imageProviderFor(crop);

                      return InkWell(
                        onTap: () => _openDetail(crop),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
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
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Expanded(
                                child: provider != null
                                    ? Image(image: provider, fit: BoxFit.contain)
                                    : const Icon(Icons.local_florist_outlined, size: 40),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                crop.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F6),
      appBar: AppBar(
        title: const Text('Crop Database'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: Column(
        children: [
          // Search input across merged list
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search crops...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.deepPurple.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.deepPurple.shade400),
                ),
              ),
            ),
          ),
          if (_error != null && _all.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.orange),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: RefreshIndicator(onRefresh: _onRefresh, child: body),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCropSheet,
        icon: const Icon(Icons.add),
        label: const Text('Add Crop'),
      ),
    );
  }

  /// Detail sheet reused from your original
  void _openDetail(Crop crop) {
    final imgProvider = _imageProviderFor(crop);
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      crop.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (imgProvider != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image(
                    image: imgProvider,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 16),
              _kv('Spacing', crop.spacing != null ? '${crop.spacing} m' : 'Unknown'),
              _kv('Harvest Time', crop.harvestTime ?? 'Unknown'),
              const SizedBox(height: 8),
              const Text('Growth Stages', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (crop.growthStages.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in crop.growthStages)
                      Chip(
                        label: Text(s),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                )
              else
                const Text('No stages provided.'),
              const SizedBox(height: 12),
              const Text('Pest Notes', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(crop.pestNotes?.isNotEmpty == true ? crop.pestNotes! : 'No notes.'),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: const TextStyle(color: Colors.black87)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}