class Crop {
  final int id;
  final String name;
  final String spacing;
  final String harvest;
  final String? imagePath;

  Crop({
    required this.id,
    required this.name,
    required this.spacing,
    required this.harvest,
    this.imagePath,
  });

  factory Crop.fromJson(Map<String, dynamic> json) {
    final rawImage = json['image'] as String?;
    final fixedImage = rawImage != null
        ? rawImage.replaceFirst('http://127.0.0.1', 'http://10.0.2.2')
        : null;

    return Crop(
      id: json['id'] as int,
      name: json['name'] as String,
      spacing: json['spacing'] as String,
      harvest: json['harvest_time'] as String, // corrected key
      imagePath: fixedImage,
    );
  }
}

