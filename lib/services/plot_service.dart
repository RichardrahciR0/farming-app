// lib/services/plot_service.dart
//
// PlotService
// - Uses AuthService for tokens & base URL
// - 401 auto-refresh retry on GET/POST/PATCH/DELETE
// - GeoJSON helpers (point/polygon/circle as polygon) + area calc
// - CRUD: fetch list/one, create, update geometry, update details, delete
// - Media: upload image, list images, delete image
// - Convenience: create/patch from map shapes (LatLng lists)
//
// Field names follow a typical DRF backend:
//   type, geometry, name, notes, crop, growth_stage, planted_at,
//   expected_harvest, target_yield_kg, area_m2
//
// If your backend differs, tweak the JSON keys in create/update methods.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart';

import 'auth_service.dart';

class PlotService {
  PlotService._();
  static final PlotService _instance = PlotService._();
  factory PlotService() => _instance;

  final _auth = AuthService();

  // ---------------------------------------------------------------------------
  // Auth headers + authed HTTP helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _authHeaders() async {
    var access = await _auth.readAccess();
    if (access == null) throw Exception('Not logged in');

    return {
      'Authorization': 'Bearer $access',
      'Content-Type': 'application/json',
    };
  }

  Future<http.Response> _retry401(
    Future<http.Response> Function(Map<String, String> headers) requestFn,
  ) async {
    var headers = await _authHeaders();
    var res = await requestFn(headers);

    if (res.statusCode == 401) {
      final newAccess = await _auth.refreshAccessToken();
      if (newAccess != null) {
        headers['Authorization'] = 'Bearer $newAccess';
        res = await requestFn(headers);
      }
    }
    return res;
  }

  Future<http.Response> _authedGet(String path) async {
    final url = Uri.parse('${_auth.baseUrl}$path');
    return _retry401((headers) => http.get(url, headers: headers));
  }

  Future<http.Response> _authedPost(String path, Map<String, dynamic> body) async {
    final url = Uri.parse('${_auth.baseUrl}$path');
    return _retry401((headers) => http.post(url, headers: headers, body: jsonEncode(body)));
  }

  Future<http.Response> _authedPatch(String path, Map<String, dynamic> body) async {
    final url = Uri.parse('${_auth.baseUrl}$path');
    return _retry401((headers) => http.patch(url, headers: headers, body: jsonEncode(body)));
  }

  Future<http.Response> _authedDelete(String path) async {
    final url = Uri.parse('${_auth.baseUrl}$path');
    return _retry401((headers) => http.delete(url, headers: headers));
  }

  // ---------------------------------------------------------------------------
  // GEOJSON HELPERS
  // ---------------------------------------------------------------------------

  /// GeoJSON Polygon from CLOSED ring of LatLngs. Coordinates are [lng, lat].
  static Map<String, dynamic> polygonGeoJsonFromLatLngs(List<LatLng> closedRing) {
    final coords = closedRing.map((p) => [p.longitude, p.latitude]).toList();
    return {
      "type": "Polygon",
      "coordinates": [coords],
    };
  }

  /// GeoJSON Point from a LatLng.
  static Map<String, dynamic> pointGeoJsonFromLatLng(LatLng p) {
    return {
      "type": "Point",
      "coordinates": [p.longitude, p.latitude],
    };
  }

  /// Circle approximated as a Polygon (48 sides by default).
  static Map<String, dynamic> circleAsPolygonGeoJson(LatLng center, double radiusM, {int segments = 48}) {
    final dist = const Distance();
    final ring = List.generate(segments, (i) {
      final theta = (i / segments) * 360.0;
      final pt = dist.offset(center, radiusM, theta);
      return [pt.longitude, pt.latitude];
    });
    if (ring.isEmpty || ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1]) {
      ring.add(ring.first);
    }
    return {"type": "Polygon", "coordinates": [ring]};
  }

  /// Area (m^2) for a CLOSED polygon ring (planar approximation around first point).
  static double polygonAreaM2(List<LatLng> closedRing) {
    if (closedRing.length < 3) return 0.0;
    final dist = const Distance();
    final ref = closedRing.first;
    final proj = closedRing.map((p) {
      final dx = dist.distance(LatLng(ref.latitude, p.longitude), ref);
      final dy = dist.distance(LatLng(p.latitude, ref.longitude), ref);
      final sx = (p.longitude >= ref.longitude) ? dx : -dx;
      final sy = (p.latitude >= ref.latitude) ? dy : -dy;
      return (sx, sy);
    }).toList();

    double sum = 0;
    for (var i = 0; i < proj.length - 1; i++) {
      final (x1, y1) = proj[i];
      final (x2, y2) = proj[i + 1];
      sum += x1 * y2 - x2 * y1;
    }
    return (sum.abs() * 0.5);
  }

  // ---------------------------------------------------------------------------
  // API METHODS
  // ---------------------------------------------------------------------------

  /// GET /api/plots/?mine=true
  Future<List<Map<String, dynamic>>> fetchMyPlots() async {
    final res = await _authedGet('/api/plots/?mine=true');
    if (res.statusCode != 200) {
      throw Exception('Fetch plots failed: ${res.statusCode} ${res.body}');
    }
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  /// GET /api/plots/{id}/
  Future<Map<String, dynamic>> fetchPlot(int plotId) async {
    final res = await _authedGet('/api/plots/$plotId/');
    if (res.statusCode != 200) {
      throw Exception('Fetch plot failed: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// POST /api/plots/
  Future<Map<String, dynamic>> createPlot({
    required String type, // 'point' | 'rectangle' | 'circle' | 'polygon'
    required Map<String, dynamic> geometry,
    required String name,
    String notes = '',
    String growthStage = '',
    String? plantedAt, // 'YYYY-MM-DD'
    String? expectedHarvest, // 'YYYY-MM-DD'
    double? targetYieldKg,
    double? areaM2,
    List<double>? circleCenterLngLat, // [lng, lat]
    double? circleRadiusM,
    String? crop,
  }) async {
    final body = <String, dynamic>{
      'type': type,
      'geometry': geometry,
      'name': name,
      'notes': notes,
      'growth_stage': growthStage,
      if (plantedAt != null) 'planted_at': plantedAt,
      if (expectedHarvest != null) 'expected_harvest': expectedHarvest,
      if (targetYieldKg != null) 'target_yield_kg': targetYieldKg,
      if (areaM2 != null) 'area_m2': areaM2,
      if (crop != null) 'crop': crop,
      if (circleCenterLngLat != null) 'circle_center': circleCenterLngLat,
      if (circleRadiusM != null) 'circle_radius_m': circleRadiusM,
    };

    final res = await _authedPost('/api/plots/', body);
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('Create plot failed: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// PATCH /api/plots/{id}/  (geometry-only or type change)
  Future<Map<String, dynamic>> updateGeometry({
    required int plotId,
    required Map<String, dynamic> geometry,
    String? type,                  // optional: if also changing type
    double? areaM2,
    List<double>? circleCenterLngLat,
    double? circleRadiusM,
  }) async {
    final body = <String, dynamic>{
      'geometry': geometry,
      if (type != null) 'type': type,
      if (areaM2 != null) 'area_m2': areaM2,
      if (circleCenterLngLat != null) 'circle_center': circleCenterLngLat,
      if (circleRadiusM != null) 'circle_radius_m': circleRadiusM,
    };

    final res = await _authedPatch('/api/plots/$plotId/', body);
    if (res.statusCode != 200) {
      throw Exception('Update geometry failed: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// PATCH /api/plots/{id}/  (details: name/crop/notes/dates/stage/goal)
  Future<Map<String, dynamic>> updateDetails({
    required int plotId,
    String? name,
    String? crop,
    String? notes,
    String? plantedAt,         // 'YYYY-MM-DD'
    String? expectedHarvest,   // 'YYYY-MM-DD'
    String? growthStage,
    double? targetYieldKg,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (crop != null) 'crop': crop,
      if (notes != null) 'notes': notes,
      if (plantedAt != null) 'planted_at': plantedAt,
      if (expectedHarvest != null) 'expected_harvest': expectedHarvest,
      if (growthStage != null) 'growth_stage': growthStage,
      if (targetYieldKg != null) 'target_yield_kg': targetYieldKg,
    };

    final res = await _authedPatch('/api/plots/$plotId/', body);
    if (res.statusCode != 200) {
      throw Exception('Update details failed: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// DELETE /api/plots/{id}/
  Future<void> deletePlot(int plotId) async {
    final res = await _authedDelete('/api/plots/$plotId/');
    if (res.statusCode != 204) {
      throw Exception('Delete plot failed: ${res.statusCode} ${res.body}');
    }
  }

  // ---------------------------------------------------------------------------
  // MEDIA (images)
  // ---------------------------------------------------------------------------

  /// POST /api/plots/{id}/media/  (multipart)
  Future<Map<String, dynamic>> uploadImage({
    required int plotId,
    required File file,
    String caption = '',
  }) async {
    var access = await _auth.readAccess();
    access ??= await _auth.refreshAccessToken();
    if (access == null) throw Exception('Not logged in');

    Future<http.Response> sendOnce(String bearer) async {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${_auth.baseUrl}/api/plots/$plotId/media/'),
      )
        ..headers['Authorization'] = 'Bearer $bearer'
        ..fields['caption'] = caption
        ..files.add(await http.MultipartFile.fromPath(
          'image',
          file.path,
          filename: p.basename(file.path),
          contentType: MediaType('image', _extToSubtype(p.extension(file.path))),
        ));
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    }

    var res = await sendOnce(access);
    if (res.statusCode == 401) {
      final newAccess = await _auth.refreshAccessToken();
      if (newAccess != null) res = await sendOnce(newAccess);
    }

    if (res.statusCode != 201) {
      throw Exception('Upload image failed: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// GET /api/plots/{id}/media/
  Future<List<Map<String, dynamic>>> listImages(int plotId) async {
    final res = await _authedGet('/api/plots/$plotId/media/');
    if (res.statusCode != 200) {
      throw Exception('List images failed: ${res.statusCode} ${res.body}');
    }
    final List data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  /// DELETE /api/plots/{id}/media/{mediaId}/
  Future<void> deleteImage({required int plotId, required int mediaId}) async {
    final res = await _authedDelete('/api/plots/$plotId/media/$mediaId/');
    if (res.statusCode != 204) {
      throw Exception('Delete image failed: ${res.statusCode} ${res.body}');
    }
  }

  String _extToSubtype(String ext) {
    switch (ext.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'jpeg';
      case '.png':
        return 'png';
      case '.webp':
        return 'webp';
      default:
        return 'jpeg';
    }
  }

  // ---------------------------------------------------------------------------
  // CONVENIENCE: CREATE/PATCH FROM MAP SHAPES
  // ---------------------------------------------------------------------------

  /// Create a plot by passing shape info directly.
  /// shape: 'point' | 'polygon' | 'rectangle' | 'circle'
  /// points: CLOSED ring for polygon/rectangle; length==1 for point
  /// circleCenter/radiusM used only if shape == 'circle'
  Future<Map<String, dynamic>> createPlotFromShape({
    required String shape,
    required String name,
    required String plantedAt,             // 'YYYY-MM-DD'
    String notes = '',
    String growthStage = '',
    String? crop,
    String? expectedHarvest,               // 'YYYY-MM-DD'
    double? targetYieldKg,
    required List<LatLng> points,
    LatLng? circleCenter,
    double? circleRadiusM,
    double? explicitAreaM2,
  }) async {
    Map<String, dynamic> geometry;
    double? areaM2 = explicitAreaM2;

    if (shape == 'point') {
      final p = points.isNotEmpty ? points.first : circleCenter!;
      geometry = pointGeoJsonFromLatLng(p);
      areaM2 = 0;
    } else if (shape == 'circle') {
      if (circleCenter == null || circleRadiusM == null) {
        throw ArgumentError('circleCenter and circleRadiusM required for circle');
      }
      geometry = circleAsPolygonGeoJson(circleCenter, circleRadiusM);
      areaM2 ??= math.pi * circleRadiusM * circleRadiusM;
    } else {
      geometry = polygonGeoJsonFromLatLngs(points);
      areaM2 ??= polygonAreaM2(points);
    }

    return createPlot(
      type: shape,
      geometry: geometry,
      name: name,
      notes: notes,
      growthStage: growthStage,
      plantedAt: plantedAt,
      expectedHarvest: expectedHarvest,
      targetYieldKg: targetYieldKg,
      crop: crop,
      areaM2: areaM2,
      circleCenterLngLat: (shape == 'circle' && circleCenter != null)
          ? [circleCenter.longitude, circleCenter.latitude]
          : null,
      circleRadiusM: (shape == 'circle') ? circleRadiusM : null,
    );
  }

  /// Patch geometry by passing shape info.
  Future<Map<String, dynamic>> updateGeometryFromShape({
    required int plotId,
    required String shape,                 // 'point' | 'polygon' | 'rectangle' | 'circle'
    required List<LatLng> points,          // CLOSED for polygon/rectangle; 1 for point
    LatLng? circleCenter,
    double? circleRadiusM,
    double? explicitAreaM2,
  }) async {
    Map<String, dynamic> geometry;
    double? areaM2 = explicitAreaM2;

    if (shape == 'point') {
      final p = points.isNotEmpty ? points.first : circleCenter!;
      geometry = pointGeoJsonFromLatLng(p);
      areaM2 = 0;
    } else if (shape == 'circle') {
      if (circleCenter == null || circleRadiusM == null) {
        throw ArgumentError('circleCenter and circleRadiusM required for circle');
      }
      geometry = circleAsPolygonGeoJson(circleCenter, circleRadiusM);
      areaM2 ??= math.pi * circleRadiusM * circleRadiusM;
    } else {
      geometry = polygonGeoJsonFromLatLngs(points);
      areaM2 ??= polygonAreaM2(points);
    }

    return updateGeometry(
      plotId: plotId,
      geometry: geometry,
      type: shape,
      areaM2: areaM2,
      circleCenterLngLat: (shape == 'circle' && circleCenter != null)
          ? [circleCenter.longitude, circleCenter.latitude]
          : null,
      circleRadiusM: (shape == 'circle') ? circleRadiusM : null,
    );
  }
}
