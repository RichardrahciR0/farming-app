import 'dart:convert';

class Crop {
  final int? id;
  final String name;

  /// Full URL or empty string. (accepts image_path | imagePath | image)
  final String imagePath;

  /// Meters between plants.
  final double? spacing;

  /// E.g. ["Dormant", "Bloom", "Harvest"]
  final List<String> growthStages;

  /// E.g. "Autumn"
  final String? harvestTime;

  /// Optional text notes
  final String? pestNotes;

  const Crop({
    this.id,
    required this.name,
    required this.imagePath,
    this.spacing,
    this.growthStages = const [],
    this.harvestTime,
    this.pestNotes,
  });

  /// Accepts BOTH snake_case (Django) and camelCase (client) keys.
  factory Crop.fromJson(Map<String, dynamic> json) {
    String? _pickStr(List<String> keys) {
      for (final k in keys) {
        if (json[k] != null) return json[k]?.toString();
      }
      return null;
    }

    double? _pickDouble(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v == null) continue;
        if (v is num) return v.toDouble();
        final d = double.tryParse(v.toString());
        if (d != null) return d;
      }
      return null;
    }

    List<String> _pickStringList(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v == null) continue;
        if (v is List) return v.map((e) => e.toString()).toList();
        if (v is String) {
          return v
              .split(RegExp(r'[,\|]'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }
      return const [];
    }

    int? _pickInt(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v == null) continue;
        if (v is int) return v;
        return int.tryParse(v.toString());
      }
      return null;
    }

    return Crop(
      id: _pickInt(const ['id', 'pk']),
      name: _pickStr(const ['name']) ?? 'Crop',
      // IMPORTANT: also accept snake_case from backend proxy
      imagePath: _pickStr(const ['image_path', 'imagePath', 'image']) ?? '',
      spacing: _pickDouble(const ['spacing']),
      growthStages: _pickStringList(const ['growth_stages', 'growthStages']),
      harvestTime: _pickStr(const ['harvest_time', 'harvestTime']),
      pestNotes: _pickStr(const ['pest_notes', 'pestNotes']),
    );
  }

  /// By default, serialize to Django-style snake_case for POST/PATCH.
  Map<String, dynamic> toJson({bool snakeCase = true}) {
    if (snakeCase) {
      return {
        if (id != null) 'id': id,
        'name': name,
        'image': imagePath,
        'spacing': spacing,
        'growth_stages': growthStages,
        'harvest_time': harvestTime,
        'pest_notes': pestNotes,
      };
    } else {
      return {
        if (id != null) 'id': id,
        'name': name,
        'imagePath': imagePath,
        'spacing': spacing,
        'growthStages': growthStages,
        'harvestTime': harvestTime,
        'pestNotes': pestNotes,
      };
    }
  }

  Crop copyWith({
    int? id,
    String? name,
    String? imagePath,
    double? spacing,
    List<String>? growthStages,
    String? harvestTime,
    String? pestNotes,
  }) {
    return Crop(
      id: id ?? this.id,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      spacing: spacing ?? this.spacing,
      growthStages: growthStages ?? this.growthStages,
      harvestTime: harvestTime ?? this.harvestTime,
      pestNotes: pestNotes ?? this.pestNotes,
    );
  }

  /// If your backend returns a relative `image` like `/media/crops/a.jpg`,
  /// this will prepend the base origin.
  String withBaseForImage(String baseUrl) {
    if (imagePath.isEmpty) return imagePath;
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }
    final left = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final right = imagePath.startsWith('/') ? imagePath : '/$imagePath';
    return '$left$right';
  }

  static List<Crop> listFromJsonString(String body) {
    final dynamic data = jsonDecode(body);
    if (data is List) {
      return data.map((e) => Crop.fromJson(e as Map<String, dynamic>)).toList();
    } else if (data is Map && data['results'] is List) {
      // Convenience if you ever pass the external response directly here
      return (data['results'] as List)
          .map((e) => Crop.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return const [];
  }
}
