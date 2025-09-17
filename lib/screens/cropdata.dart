import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../models/crop.dart';

/// --- Environment ---
/// Base URL to your backend (Android emulator uses 10.0.2.2)
String get kBaseUrl {
  final host = Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';
  return 'http://$host:8000';
}

/// Provide JWT here if your local crops API requires auth.
Future<String?> getAccessToken() async {
  // TODO: Wire up real token if needed (e.g., from secure storage)
  return null;
}

class CropDataPage extends StatefulWidget {
  const CropDataPage({super.key});

  @override
  State<CropDataPage> createState() => _CropDataPageState();
}

class _CropDataPageState extends State<CropDataPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<Crop> _all = [];
  List<Crop> _filtered = [];
  bool _isLoading = true;
  String? _error;

  /// Toggle: Local (your DB) vs Global (external API via Django proxy)
  bool _useGlobal = true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _fetchCrops(); // initial load
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------------
  // Helpers
  // ---------------------------

  List<Crop> _parseCropListFromBody(String body) {
    final data = jsonDecode(body);
    if (data is List) {
      return data
          .map((e) => Crop.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data is Map && data['results'] is List) {
      return (data['results'] as List)
          .map((e) => Crop.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  String? _imageUrlFor(Crop c) {
    final img = c.imagePath;
    if (img.isEmpty) return null;
    if (_useGlobal) return img; // already absolute from external proxy
    if (img.startsWith('http')) return img;
    // assume Django serves MEDIA/ on kBaseUrl
    return '$kBaseUrl$img';
  }

  // ---------------------------
  // Fetchers (Local / Global)
  // ---------------------------

  /// GET /api/crops/
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

  /// POST /api/crops/ (JSON)
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

  /// POST /api/crops/ (multipart with optional image)
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

  /// DELETE /api/crops/{id}/
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

  /// GET /api/external/crops/?q=...
  /// Expects: { "results": [ { id, name, image_path, spacing, harvest_time, growth_stages, pest_notes }, ... ] }
  Future<List<Crop>> _fetchGlobalCrops(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse('$kBaseUrl/api/external/crops/').replace(
      queryParameters: {
        'q': query.trim(),
        'page': '$page',
        'limit': '24',
        'details': '1', // ask backend for richer images
      },
    );
    final resp = await http.get(uri, headers: {'Accept': 'application/json'});
    if (resp.statusCode != 200) {
      throw Exception('External API error: ${resp.statusCode}');
    }

    final Map<String, dynamic> json = jsonDecode(resp.body);
    final List results = (json['results'] as List?) ?? [];
    return results
        .map<Crop>((e) => Crop.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Save a "global" crop into local DB
  Future<void> _saveGlobalToLocal(Crop c) async {
    final payload = {
      'name': c.name,
      'image_path': c.imagePath, // keep remote URL if you want
      'spacing': c.spacing,
      'harvest_time': c.harvestTime,
      'growth_stages': c.growthStages,
      'pest_notes': c.pestNotes,
    };
    await _createCrop(payload);
    if (!_useGlobal) {
      await _fetchCrops();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to My Crops')),
      );
    }
  }

  /// Unified fetch
  Future<void> _fetchCrops() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<Crop> list;
      if (_useGlobal) {
        final q = _searchCtrl.text;
        if (q.trim().isEmpty) {
          setState(() {
            _isLoading = false;
            _all = [];
            _filtered = [];
            _error = "Type a crop name to search the global catalog.";
          });
          return;
        }
        list = await _fetchGlobalCrops(q);
        _all = list;
        _filtered = list;
      } else {
        list = await _fetchLocalCrops();
        _all = list;
        _filtered = _filterByQuery(list, _searchCtrl.text);
      }
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

  // ---------------------------
  // Search & filter
  // ---------------------------

  List<Crop> _filterByQuery(List<Crop> src, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List.of(src);
    return src.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  void _onSearchChanged() {
    if (_useGlobal) {
      _fetchCrops();
    } else {
      setState(() {
        _filtered = _filterByQuery(_all, _searchCtrl.text);
      });
    }
  }

  Future<void> _onRefresh() async {
    await _fetchCrops();
  }

  // ---------------------------
  // Create / Delete UI
  // ---------------------------

  Future<void> _openAddDialog() async {
    final nameCtrl = TextEditingController();
    final imgCtrl = TextEditingController(); // for URL (optional)
    final spacingCtrl = TextEditingController();
    final harvestCtrl = TextEditingController();
    final stagesCtrl = TextEditingController(); // comma-separated
    final pestCtrl = TextEditingController();

    final formKey = GlobalKey<FormState>();
    final picker = ImagePicker();
    File? pickedFile;

    Future<void> pickFrom(ImageSource src) async {
      final x = await picker.pickImage(source: src, imageQuality: 90);
      if (x != null) {
        pickedFile = File(x.path);
      }
    }

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: const Text('Add Crop'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (pickedFile != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          pickedFile!,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Gallery'),
                          onPressed: () async {
                            await pickFrom(ImageSource.gallery);
                            setD(() {});
                          },
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Camera'),
                          onPressed: () async {
                            await pickFrom(ImageSource.camera);
                            setD(() {});
                          },
                        ),
                        const Spacer(),
                        if (pickedFile != null)
                          IconButton(
                            tooltip: 'Remove photo',
                            onPressed: () {
                              pickedFile = null;
                              setD(() {});
                            },
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Optional: paste an image URL if not uploading
                    TextFormField(
                      controller: imgCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Image URL (optional if uploading)',
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name *'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: spacingCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Spacing (m)'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    TextFormField(
                      controller: harvestCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Harvest Time'),
                    ),
                    TextFormField(
                      controller: stagesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Growth Stages (comma-separated)',
                      ),
                    ),
                    TextFormField(
                      controller: pestCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Pest Notes'),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  final spacing = spacingCtrl.text.trim().isEmpty
                      ? null
                      : double.tryParse(spacingCtrl.text.trim());

                  final stages = stagesCtrl.text
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();

                  try {
                    if (pickedFile != null) {
                      // Multipart (with file)
                      final fields = <String, String>{
                        'name': nameCtrl.text.trim(),
                        if (imgCtrl.text.trim().isNotEmpty)
                          'image_path': imgCtrl.text.trim(),
                        if (spacing != null) 'spacing': spacing.toString(),
                        if (harvestCtrl.text.trim().isNotEmpty)
                          'harvest_time': harvestCtrl.text.trim(),
                        if (stages.isNotEmpty) 'growth_stages': jsonEncode(stages),
                        if (pestCtrl.text.trim().isNotEmpty)
                          'pest_notes': pestCtrl.text.trim(),
                      };
                      await _createCropMultipart(
                        fields: fields,
                        imageFile: pickedFile,
                      );
                    } else {
                      // JSON (URL or no image)
                      final payload = {
                        'name': nameCtrl.text.trim(),
                        'image_path': imgCtrl.text.trim(),
                        'spacing': spacing,
                        'harvest_time': harvestCtrl.text.trim().isEmpty
                            ? null
                            : harvestCtrl.text.trim(),
                        'growth_stages': stages,
                        'pest_notes': pestCtrl.text.trim().isNotEmpty
                            ? pestCtrl.text.trim()
                            : null,
                      };
                      await _createCrop(payload);
                    }

                    if (mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Create failed: $e')),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    if (created == true) {
      if (_useGlobal) setState(() => _useGlobal = false);
      await _fetchCrops();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Crop added')),
        );
      }
    }
  }

  Future<void> _confirmDelete(Crop c) async {
    if (c.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Crop'),
        content: Text('Delete “${c.name}”? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _deleteCrop(c.id!);
        await _fetchCrops();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }

  // ---------------------------
  // Detail sheet
  // ---------------------------

  void _openDetail(Crop crop) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final img = _imageUrlFor(crop);

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
              if (img != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    img,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image, size: 48),
                  ),
                ),
              const SizedBox(height: 16),
              _kv('Spacing', crop.spacing != null ? '${crop.spacing} m' : 'Unknown'),
              _kv('Harvest Time', crop.harvestTime ?? 'Unknown'),
              const SizedBox(height: 8),
              const Text(
                'Growth Stages',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
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
              const Text(
                'Pest Notes',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(crop.pestNotes?.isNotEmpty == true ? crop.pestNotes! : 'No notes.'),
              const SizedBox(height: 16),

              // Actions footer
              Row(
                children: [
                  if (_useGlobal)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await _saveGlobalToLocal(crop);
                            if (mounted) Navigator.pop(context);
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Save failed: $e')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.download_done),
                        label: const Text('Save to My Crops'),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
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
            child: Text(
              k,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // Build
  // ---------------------------

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : (_error != null)
            ? Center(
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: _error == "Type a crop name to search the global catalog."
                        ? Colors.black54
                        : Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            : (_filtered.isEmpty)
                ? const Center(child: Text('No crops to display.'))
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final crop = _filtered[i];
                      final img = _imageUrlFor(crop);

                      final menu = (!_useGlobal && crop.id != null)
                          ? PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'delete') _confirmDelete(crop);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Delete'),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink();

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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [menu],
                              ),
                              Expanded(
                                child: (img != null)
                                    ? Image.network(
                                        img,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => const Icon(
                                          Icons.image_not_supported_outlined,
                                          size: 40,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.local_florist_outlined,
                                        size: 40,
                                      ),
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
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Crop Database'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Add Crop',
            icon: const Icon(Icons.add),
            onPressed: _openAddDialog,
          ),
          // Local / Global toggle
          Row(
            children: [
              const Text('Local', style: TextStyle(fontSize: 12)),
              Switch(
                value: _useGlobal,
                onChanged: (v) {
                  setState(() => _useGlobal = v);
                  _fetchCrops();
                },
              ),
              const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Text('Global', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddDialog,
        tooltip: 'Add Crop',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText:
                    _useGlobal ? 'Search global plants...' : 'Search crops...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              onSubmitted: (_) => _fetchCrops(),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}
