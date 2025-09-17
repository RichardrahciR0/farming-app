// lib/screens/map_page.dart
// (merged, compact, backend save wired)
// - Sanitizes loaded shapes
// - Filters empty polygons before rendering
// - Drag handles for editing
// - POST new plots, PATCH edited geometry & details via PlotService
// - Zoom/resize FABs
// - Square crop tiles

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';

// API service for saving plots
import '../services/plot_service.dart';

enum DrawTool { pan, point, polygon, rectangle, circle }

// ---- growth stages (ordered) ----
const List<String> kGrowthStages = [
  'Seedling',
  'Vegetative',
  'Flowering',
  'Harvest Ready',
];

class CropItem {
  final String id; // 'orange' (asset) or timestamp (custom)
  final String name; // display name
  final String imagePath; // asset path or file path
  final bool isAsset;
  const CropItem({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.isAsset,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imagePath': imagePath,
        'isAsset': isAsset,
      };

  static CropItem fromJson(Map<String, dynamic> m) => CropItem(
        id: m['id'] as String,
        name: m['name'] as String,
        imagePath: m['imagePath'] as String,
        isAsset: m['isAsset'] as bool,
      );
}

class PlotModel {
  String id;
  String name;
  String? crop; // display name
  List<LatLng> points; // closed polygon/ring (last == first)
  double areaM2;
  String plantedOn; // yyyy-MM-dd

  int growthStageIndex; // 0..kGrowthStages.length-1
  double? targetYieldKg; // optional user goal
  String? expectedHarvest; // yyyy-MM-dd (optional)

  // 'polygon' | 'rectangle' | 'circle' | 'point'
  String shape;
  double? circleCenterLat;
  double? circleCenterLng;
  double? circleRadiusM;

  PlotModel({
    required this.id,
    required this.name,
    required this.points,
    required this.areaM2,
    required this.plantedOn,
    this.crop,
    this.growthStageIndex = 0,
    this.targetYieldKg,
    this.expectedHarvest,
    this.shape = 'polygon',
    this.circleCenterLat,
    this.circleCenterLng,
    this.circleRadiusM,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'crop': crop,
        'points': points.map((p) => [p.latitude, p.longitude]).toList(),
        'areaM2': areaM2,
        'plantedOn': plantedOn,
        'growthStageIndex': growthStageIndex,
        'targetYieldKg': targetYieldKg,
        'expectedHarvest': expectedHarvest,
        'shape': shape,
        'circleCenterLat': circleCenterLat,
        'circleCenterLng': circleCenterLng,
        'circleRadiusM': circleRadiusM,
      };

  static PlotModel fromJson(Map<String, dynamic> m) => PlotModel(
        id: m['id'],
        name: m['name'],
        crop: m['crop'],
        points: (m['points'] as List)
            .map((xy) => LatLng((xy[0] as num).toDouble(), (xy[1] as num).toDouble()))
            .toList(),
        areaM2: (m['areaM2'] as num).toDouble(),
        plantedOn: m['plantedOn'],
        growthStageIndex: (m['growthStageIndex'] ?? 0) as int,
        targetYieldKg: (m['targetYieldKg'] as num?)?.toDouble(),
        expectedHarvest: m['expectedHarvest'],
        shape: (m['shape'] ?? 'polygon') as String,
        circleCenterLat: (m['circleCenterLat'] as num?)?.toDouble(),
        circleCenterLng: (m['circleCenterLng'] as num?)?.toDouble(),
        circleRadiusM: (m['circleRadiusM'] as num?)?.toDouble(),
      );

  String get growthLabel =>
      kGrowthStages[growthStageIndex.clamp(0, kGrowthStages.length - 1)];

  double progress() {
    try {
      if (expectedHarvest != null && expectedHarvest!.isNotEmpty) {
        final start = DateTime.parse(plantedOn);
        final end = DateTime.parse(expectedHarvest!);
        final now = DateTime.now();
        final total = end.difference(start).inDays;
        if (total <= 0) return 1.0;
        final done = now.difference(start).inDays;
        return (done / total).clamp(0, 1).toDouble();
      }
    } catch (_) {}
    if (kGrowthStages.length <= 1) return 0;
    return growthStageIndex / (kGrowthStages.length - 1);
  }

  LatLng? get circleCenter =>
      (circleCenterLat != null && circleCenterLng != null)
          ? LatLng(circleCenterLat!, circleCenterLng!)
          : null;
}

class MapPage extends StatefulWidget {
  const MapPage({Key? key}) : super(key: key);
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _map = MapController();
  DrawTool _tool = DrawTool.pan;

  final List<PlotModel> _plots = [];
  final List<LatLng> _drawing = []; // temp (open) ring while drawing
  List<List<LatLng>> _undoStack = [];
  PlotModel? _selected;

  // rectangle/circle two-step helpers
  LatLng? _anchor; // first tap

  // Drawing helpers
  final Distance _dist = const Distance();
  static const double _snapCloseMeters = 8.0; // tap near first point to finish

  // Crops (assets + user-added)
  final List<CropItem> _crops = [];
  String? _selectedCropId;

  // ---- Weather ----
  static const String _owmApiKey =
      String.fromEnvironment('OWM_API_KEY', defaultValue: 'YOUR_OPENWEATHERMAP_API_KEY');
  final LatLng _initialCenter = const LatLng(-27.4698, 153.0251); // Brisbane
  bool _weatherLoading = false;
  String? _weatherErr;
  double? _weatherTempC;
  String? _weatherMain;

  // ---- Draggable toolbar (persisted) ----
  double _tbLeft = -1; // -1 => not set yet
  double _tbTop = -1;
  Future<void> _loadToolbarPos() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _tbLeft = sp.getDouble('tb_left') ?? -1;
      _tbTop = sp.getDouble('tb_top') ?? -1;
    });
  }
  Future<void> _saveToolbarPos() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('tb_left', _tbLeft);
    await sp.setDouble('tb_top', _tbTop);
  }

  // ---- Draggable/collapsible weather card (persisted) ----
  double _wxLeft = -1;
  double _wxTop = -1;
  bool _wxCollapsed = true; // start collapsed so it doesn't block taps
  bool _wxVisible = true;
  Future<void> _loadWeatherUiPrefs() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _wxLeft = sp.getDouble('wx_left') ?? -1;
      _wxTop = sp.getDouble('wx_top') ?? -1;
      _wxCollapsed = sp.getBool('wx_collapsed') ?? true;
      _wxVisible = sp.getBool('wx_visible') ?? true;
    });
  }
  Future<void> _saveWeatherUiPrefs() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('wx_left', _wxLeft);
    await sp.setDouble('wx_top', _wxTop);
    await sp.setBool('wx_collapsed', _wxCollapsed);
    await sp.setBool('wx_visible', _wxVisible);
  }

  // circle meta while drawing
  LatLng? _pendingCircleCenter;
  double? _pendingCircleRadiusM;

  // Edit/resize mode state
  bool _resizeMode = false;
  List<LatLng> _editingRing = [];        // polygon/rectangle working vertices (closed)
  LatLng? _editCircleCenter;             // circle center while editing
  double? _editCircleRadiusM;            // circle radius while editing
  LatLng? _editPoint;                    // point position while editing
  // backups for cancel
  List<LatLng>? _backupPoints;
  double? _backupCircleCenterLat;
  double? _backupCircleCenterLng;
  double? _backupCircleRadiusM;

  @override
  void initState() {
    super.initState();
    _initCrops();
    _loadPlots();
    _fetchWeather();
    _loadToolbarPos();
    _loadWeatherUiPrefs();
  }

  // ---------- Crops: defaults + custom ----------
  Future<void> _initCrops() async {
    final defaults = <CropItem>[
      const CropItem(id: 'orange', name: 'Orange', imagePath: 'assets/crops/orange.png', isAsset: true),
      const CropItem(id: 'wheat', name: 'Wheat', imagePath: 'assets/crops/wheat.png', isAsset: true),
      const CropItem(id: 'leafy', name: 'Leafy', imagePath: 'assets/crops/leafy.png', isAsset: true),
      const CropItem(id: 'tree', name: 'Tree', imagePath: 'assets/crops/tree.png', isAsset: true),
      const CropItem(id: 'lettuce', name: 'Lettuce', imagePath: 'assets/crops/lettuce.png', isAsset: true),
    ];
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('custom_crops_v1');
    final custom = <CropItem>[];
    if (raw != null) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      custom.addAll(list.map(CropItem.fromJson));
    }
    setState(() {
      _crops
        ..clear()
        ..addAll([...defaults, ...custom]);
      _selectedCropId = _crops.isNotEmpty ? _crops.first.id : null;
    });
  }

  Future<void> _saveCustomCrops() async {
    final sp = await SharedPreferences.getInstance();
    final customOnly = _crops.where((c) => !c.isAsset).toList();
    await sp.setString(
      'custom_crops_v1',
      jsonEncode(customOnly.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _addCustomCrop() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final nameCtrl = TextEditingController();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New Crop', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(File(picked.path), height: 120, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Crop name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
              onPressed: () {
                final id = DateTime.now().millisecondsSinceEpoch.toString();
                final item = CropItem(
                  id: id,
                  name: nameCtrl.text.trim().isEmpty ? 'Custom' : nameCtrl.text.trim(),
                  imagePath: picked.path,
                  isAsset: false,
                );
                setState(() {
                  _crops.add(item);
                  _selectedCropId = item.id;
                  if (_selected != null) _selected!.crop = item.name;
                });
                _saveCustomCrops();
                Navigator.pop(ctx);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Persistence (with sanitation) ----------
  Future<void> _loadPlots() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('plots_v1');
    if (raw == null) return;

    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final loaded = list.map(PlotModel.fromJson).toList();

    final cleaned = <PlotModel>[];
    for (final p in loaded) {
      if (p.points.isEmpty) continue; // drop truly empty

      if (p.shape != 'point') {
        if (p.points.length == 1) {
          p.points = [p.points.first, p.points.first];
        } else {
          final f = p.points.first, l = p.points.last;
          if (f.latitude != l.latitude || f.longitude != l.longitude) {
            p.points = [...p.points, f];
          }
        }
      }

      if (p.shape == 'circle' &&
          p.circleCenterLat != null &&
          p.circleCenterLng != null) {
        final r = (p.circleRadiusM ?? 0).abs();
        if (r > 0 && p.points.length < 10) {
          final center = LatLng(p.circleCenterLat!, p.circleCenterLng!);
          final ring = List.generate(48, (i) {
            final theta = (i / 48) * 360.0;
            return _dist.offset(center, r, theta);
          });
          p.points = [...ring, ring.first];
          p.areaM2 = math.pi * r * r;
        }
      }

      cleaned.add(p);
    }

    setState(() {
      _plots
        ..clear()
        ..addAll(cleaned);
    });
  }

  Future<void> _savePlots() async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(_plots.map((p) => p.toJson()).toList());
    await sp.setString('plots_v1', raw);
  }

  // ---------- Geometry helpers ----------
  List<LatLng> _withoutClosingPoint(List<LatLng> pts) {
    if (pts.length >= 2) {
      final f = pts.first, l = pts.last;
      if (f.latitude == l.latitude && f.longitude == l.longitude) {
        return pts.sublist(0, pts.length - 1);
      }
    }
    return pts;
  }

  LatLng _centroid(List<LatLng> poly) {
    final pts = _withoutClosingPoint(poly);
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude; lng += p.longitude;
    }
    final n = math.max(1, pts.length);
    return LatLng(lat / n, lng / n);
  }

  double _areaM2(List<LatLng> poly) {
    final pts = _withoutClosingPoint(poly);
    if (pts.length < 3) return 0;
    final ref = pts[0];
    final proj = pts.map((p) {
      final dx = _dist.distance(LatLng(ref.latitude, p.longitude), ref);
      final dy = _dist.distance(LatLng(p.latitude, ref.longitude), ref);
      return Offset(
        p.longitude >= ref.longitude ? dx : -dx,
        p.latitude >= ref.latitude ? dy : -dy,
      );
    }).toList();

    double sum = 0;
    for (int i = 0; i < proj.length; i++) {
      final a = proj[i];
      final b = proj[(i + 1) % proj.length];
      sum += (a.dx * b.dy - b.dx * a.dy);
    }
    return (sum.abs() * 0.5);
  }

  List<LatLng> _ensureClosed(List<LatLng> pts) {
    if (pts.isEmpty) return pts;
    final first = pts.first, last = pts.last;
    if (first.latitude == last.latitude && first.longitude == last.longitude) {
      return pts;
    }
    return [...pts, first];
  }

  // rect/circle return OPEN rings; _finishDrawing will close them
  List<LatLng> _rectOpen(LatLng a, LatLng b) {
    final n = math.max(a.latitude, b.latitude);
    final s = math.min(a.latitude, b.latitude);
    final e = math.max(a.longitude, b.longitude);
    final w = math.min(a.longitude, b.longitude);
    return [
      LatLng(n, w),
      LatLng(n, e),
      LatLng(s, e),
      LatLng(s, w),
    ];
  }

  List<LatLng> _circleOpenFrom(LatLng center, LatLng edge, {int segments = 48}) {
    final r = _dist.distance(center, edge);
    return List.generate(segments, (i) {
      final theta = (i / segments) * 360.0;
      return _dist.offset(center, r, theta);
    });
  }

  Polygon _polygonFor(PlotModel p, {bool selected = false}) => Polygon(
        points: p.points,
        color: (selected ? Colors.green : Colors.green).withOpacity(selected ? 0.45 : 0.28),
        borderColor: selected ? Colors.green.shade900 : Colors.green,
        borderStrokeWidth: selected ? 3 : 2,
        label: '${p.name} • ${p.areaM2.toStringAsFixed(0)} m²'
            '${p.crop != null ? ' • ${p.crop}' : ''}',
      );

  // ---------- Map interactions ----------
  void _onTap(LatLng pt) {
    switch (_tool) {
      case DrawTool.pan:
        _selectPlotAt(pt);
        return;
      case DrawTool.point:
        _startOrReplaceOpen([pt]);
        _finishDrawing();
        return;
      case DrawTool.polygon:
        if (_drawing.length >= 3 && _dist.distance(pt, _drawing.first) <= _snapCloseMeters) {
          _finishDrawing();
        } else {
          setState(() => _drawing.add(pt));
        }
        return;
      case DrawTool.rectangle:
        if (_anchor == null) {
          setState(() => _anchor = pt);
        } else {
          final rectOpen = _rectOpen(_anchor!, pt);
          _startOrReplaceOpen(rectOpen);
          _finishDrawing();
        }
        return;
      case DrawTool.circle:
        if (_anchor == null) {
          setState(() => _anchor = pt);
        } else {
          final center = _anchor!;
          final open = _circleOpenFrom(center, pt, segments: 48);
          _pendingCircleCenter = center;
          _pendingCircleRadiusM = _dist.distance(center, pt);
          _startOrReplaceOpen(open);
          _finishDrawing();
        }
        return;
    }
  }

  void _onLongPress(LatLng pt) {
    if (_tool == DrawTool.polygon && _drawing.length >= 3) {
      _finishDrawing();
      return;
    }
    if (_selected != null) {
      final toDelete = _selected!;
      final idInt = int.tryParse(toDelete.id);
      setState(() {
        _plots.removeWhere((p) => p.id == toDelete.id);
        _selected = null;
      });
      _savePlots();
      if (idInt != null) {
        () async {
          try { await PlotService().deletePlot(idInt); } catch (_) {}
        }();
      }
    }
  }

  void _selectPlotAt(LatLng pt) {
    PlotModel? hit;
    for (final p in _plots.reversed) {
      if (_pointInPolygon(pt, p.points)) {
        hit = p;
        break;
      }
    }
    setState(() => _selected = hit);

    if (_selected != null) {
      _enterResizeFromSelected();
    } else {
      _exitResizeMode();
    }
  }

  bool _pointInPolygon(LatLng p, List<LatLng> poly) {
    final pts = _withoutClosingPoint(poly);
    if (pts.isEmpty) return false;
    bool c = false;
    for (int i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      final pi = pts[i], pj = pts[j];
      final intersect = ((pi.longitude > p.longitude) != (pj.longitude > p.longitude)) &&
          (p.latitude <
              (pj.latitude - pi.latitude) *
                      (p.longitude - pi.longitude) /
                      (pj.longitude - pi.longitude) +
                  pi.latitude);
      if (intersect) c = !c;
    }
    return c;
  }

  void _startOrReplaceOpen(List<LatLng> openRing) {
    setState(() {
      _undoStack.add(List.of(_drawing));
      _drawing
        ..clear()
        ..addAll(openRing);
    });
  }

  Map<String, dynamic> _geometryFor({
    required String shape,               // 'point' | 'polygon' | 'rectangle' | 'circle'
    required List<LatLng> points,        // closed ring for polygon/rectangle
    LatLng? circleCenter,
    double? circleRadiusM,
  }) {
    if (shape == 'point') {
      final p = points.isNotEmpty ? points.first : circleCenter!;
      return {
        'type': 'Point',
        'coordinates': [p.longitude, p.latitude],
      };
    }

    if (shape == 'circle' && circleCenter != null && (circleRadiusM ?? 0) > 0) {
      // Send circle meta as well (optional for your API)
      return {
        'type': 'Circle',
        'center': [circleCenter.longitude, circleCenter.latitude],
        'radiusMeters': circleRadiusM!.toDouble(),
      };
    }

    final ring = points.map((p) => [p.longitude, p.latitude]).toList();
    return {
      'type': 'Polygon',
      'coordinates': [ring],
    };
  }

  void _finishDrawing() {
    if (_drawing.isEmpty) return;

    final closed = _ensureClosed(_drawing);
    final cropName = () {
      if (_selectedCropId == null) return null;
      final i = _crops.indexWhere((c) => c.id == _selectedCropId);
      if (i < 0) return null;
      return _crops[i].name;
    }();

    String shape = 'polygon';
    if (_tool == DrawTool.rectangle) shape = 'rectangle';
    if (_tool == DrawTool.circle) shape = 'circle';
    if (_tool == DrawTool.point) shape = 'point';

    final area = (shape == 'circle' && _pendingCircleRadiusM != null)
        ? math.pi * _pendingCircleRadiusM! * _pendingCircleRadiusM!
        : _areaM2(closed);

    final plot = PlotModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // temp; may be replaced by server id
      name: 'Plot ${_plots.length + 1}',
      crop: cropName,
      points: closed,
      areaM2: area,
      plantedOn: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      growthStageIndex: 0,
      shape: shape,
      circleCenterLat: (shape == 'circle') ? _pendingCircleCenter?.latitude : null,
      circleCenterLng: (shape == 'circle') ? _pendingCircleCenter?.longitude : null,
      circleRadiusM: (shape == 'circle') ? _pendingCircleRadiusM : null,
      expectedHarvest: null,
      targetYieldKg: null,
    );

    setState(() {
      _plots.add(plot);
      _selected = plot;
      _drawing.clear();
      _anchor = null;
      _pendingCircleCenter = null;
      _pendingCircleRadiusM = null;
      _undoStack.clear();
    });
    _savePlots();

    // ALSO save to the backend
    () async {
      try {
        final geometry = _geometryFor(
          shape: plot.shape,
          points: plot.points,
          circleCenter: plot.circleCenter,
          circleRadiusM: plot.circleRadiusM,
        );

        final created = await PlotService().createPlot(
          type: plot.shape,
          geometry: geometry,
          name: plot.name,
          notes: '',
          crop: plot.crop,
          growthStage: kGrowthStages[plot.growthStageIndex],
          plantedAt: plot.plantedOn,
          expectedHarvest: plot.expectedHarvest,
          targetYieldKg: plot.targetYieldKg,
          areaM2: plot.areaM2,
          circleCenterLngLat: (plot.shape == 'circle' && plot.circleCenter != null)
              ? [plot.circleCenter!.longitude, plot.circleCenter!.latitude]
              : null,
          circleRadiusM: (plot.shape == 'circle') ? plot.circleRadiusM : null,
        );

        // keep server id for future PATCH
        final newId = created['id']?.toString();
        if (newId != null && mounted) {
          setState(() => plot.id = newId);
          _savePlots();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Plot saved to server')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Server save failed: $e')),
          );
        }
      }
    }();

    _enterResizeFromSelected();
  }

  void _undo() {
    if (_drawing.isNotEmpty) {
      setState(() => _drawing.removeLast());
      return;
    }
    if (_plots.isNotEmpty) {
      setState(() {
        _plots.removeLast();
        _selected = null;
      });
      _savePlots();
    }
  }

  void _clearAll() {
    setState(() {
      _plots.clear();
      _drawing.clear();
      _anchor = null;
      _selected = null;
      _undoStack.clear();
    });
    _savePlots();
  }

  // ---------- Resizing (grow/shrink) ----------
  void _resizeSelected(double factor) {
    if (_selected == null) return;
    final p = _selected!;
    if (p.shape == 'point') return;

    if (p.shape == 'circle' && p.circleCenter != null && p.circleRadiusM != null) {
      final newR = (p.circleRadiusM! * factor).clamp(0.0, double.infinity);
      final newPts = List.generate(48, (i) {
        final theta = (i / 48) * 360.0;
        return _dist.offset(p.circleCenter!, newR, theta);
      });
      final closed = _ensureClosed(newPts);
      setState(() {
        p
          ..circleRadiusM = newR
          ..points = closed
          ..areaM2 = math.pi * newR * newR;
      });
      _savePlots();
      return;
    }

    final open = _withoutClosingPoint(p.points);
    if (open.isEmpty) return;
    final center = _centroid(p.points);
    final scaledOpen = open.map((pt) {
      final d = _dist.distance(center, pt);
      final bearing = _dist.bearing(center, pt);
      return _dist.offset(center, d * factor, bearing);
    }).toList();
    final closed = _ensureClosed(scaledOpen);
    setState(() {
      p
        ..points = closed
        ..areaM2 = _areaM2(closed);
    });
    _savePlots();
  }

  // --- edit/resize helpers ---
  void _enterResizeFromSelected() {
    if (_selected == null) return;
    final p = _selected!;
    _resizeMode = true;

    // backup
    _backupPoints = List<LatLng>.from(p.points);
    _backupCircleCenterLat = p.circleCenterLat;
    _backupCircleCenterLng = p.circleCenterLng;
    _backupCircleRadiusM  = p.circleRadiusM;

    // prime working copies
    _editingRing = [];
    _editCircleCenter = null;
    _editCircleRadiusM = null;
    _editPoint = null;

    switch (p.shape) {
      case 'polygon':
      case 'rectangle':
        _editingRing = List<LatLng>.from(p.points);
        if (_editingRing.isNotEmpty) {
          final f = _editingRing.first, l = _editingRing.last;
          if (f.latitude != l.latitude || f.longitude != l.longitude) {
            _editingRing.add(f);
          }
        }
        break;
      case 'circle':
        if (p.circleCenter != null && p.circleRadiusM != null) {
          _editCircleCenter = p.circleCenter;
          _editCircleRadiusM = p.circleRadiusM;
        } else if (p.points.length >= 2) {
          final c = _centroid(p.points);
          _editCircleCenter = c;
          _editCircleRadiusM = _dist.distance(c, p.points.first);
        }
        break;
      case 'point':
        if (p.points.isNotEmpty) _editPoint = p.points.first;
        break;
      default:
        break;
    }
    setState(() {});
  }

  void _exitResizeMode() {
    setState(() {
      _resizeMode = false;
      _editingRing = [];
      _editCircleCenter = null;
      _editCircleRadiusM = null;
      _editPoint = null;
      _backupPoints = null;
      _backupCircleCenterLat = null;
      _backupCircleCenterLng = null;
      _backupCircleRadiusM = null;
    });
  }

  List<DragMarker> _buildHandlesForSelected() {
    if (_selected == null) return const [];
    final p = _selected!;
    final handles = <DragMarker>[];

    if (p.shape == 'polygon' || p.shape == 'rectangle') {
      if (_editingRing.isEmpty) return const [];
      for (var i = 0; i < _editingRing.length; i++) {
        final idx = i;
        handles.add(
          DragMarker(
            point: _editingRing[idx],
            size: const Size(28, 28),
            offset: const Offset(0, 0),
            builder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                color: Colors.blueAccent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            onDragUpdate: (_, newPos) {
              setState(() {
                _editingRing[idx] = newPos;
                if (idx == 0) _editingRing[_editingRing.length - 1] = newPos;
                if (idx == _editingRing.length - 1) _editingRing[0] = newPos;
                final closed = _ensureClosed(_editingRing);
                p.points = closed;
                p.areaM2 = _areaM2(closed);
              });
            },
          ),
        );
      }
      return handles;
    }

    if (p.shape == 'circle' && _editCircleCenter != null) {
      final center = _editCircleCenter!;
      final radius = (_editCircleRadiusM ?? 5).toDouble();

      // center handle
      handles.add(
        DragMarker(
          point: center,
          size: const Size(28, 28),
          builder: (_, __, ___) => Container(
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
          onDragUpdate: (_, newPos) {
            setState(() {
              _editCircleCenter = newPos;
              final ring = List.generate(48, (i) {
                final theta = (i / 48) * 360.0;
                return _dist.offset(newPos, radius, theta);
              });
              p
                ..points = _ensureClosed(ring)
                ..circleCenterLat = newPos.latitude
                ..circleCenterLng = newPos.longitude
                ..circleRadiusM  = radius
                ..areaM2 = math.pi * radius * radius;
            });
          },
        ),
      );

      // radius handle (east)
      final radiusHandle = _dist.offset(center, radius, 90);
      handles.add(
        DragMarker(
          point: radiusHandle,
          size: const Size(24, 24),
          builder: (_, __, ___) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.green, width: 3),
            ),
          ),
          onDragUpdate: (_, newPos) {
            final d = _dist.distance(_editCircleCenter!, newPos).clamp(1.0, 100000.0);
            setState(() {
              _editCircleRadiusM = d;
              final ring = List.generate(48, (i) {
                final theta = (i / 48) * 360.0;
                return _dist.offset(_editCircleCenter!, d, theta);
              });
              p
                ..points = _ensureClosed(ring)
                ..circleRadiusM = d
                ..areaM2 = math.pi * d * d;
            });
          },
        ),
      );
      return handles;
    }

    if (p.shape == 'point' && _editPoint != null) {
      handles.add(
        DragMarker(
          point: _editPoint!,
          size: const Size(28, 28),
          builder: (_, __, ___) => Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
          onDragUpdate: (_, newPos) {
            setState(() {
              _editPoint = newPos;
              p.points = _ensureClosed([newPos]);
              p.areaM2 = 0;
            });
          },
        ),
      );
      return handles;
    }

    return handles;
  }

  Future<void> _editSelectedDetails() async {
    if (_selected == null) return;

    final name = TextEditingController(text: _selected!.name);
    final spacing = TextEditingController();
    final date = TextEditingController(text: _selected!.plantedOn);

    int stageIndex = _selected!.growthStageIndex;
    final targetYield = TextEditingController(
      text: _selected!.targetYieldKg == null ? '' : _selected!.targetYieldKg!.toStringAsFixed(0),
    );
    final expectedHarvest = TextEditingController(text: _selected!.expectedHarvest ?? '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Plot Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(decoration: _inp('Name'), controller: name),
              const SizedBox(height: 10),
              TextField(decoration: _inp('Spacing'), controller: spacing),
              const SizedBox(height: 10),
              TextField(
                readOnly: true,
                controller: date,
                decoration: _inp('Planting Date').copyWith(
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                onTap: () async {
                  FocusScope.of(context).unfocus();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(date.text) ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    date.text = DateFormat('yyyy-MM-dd').format(picked);
                  }
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: stageIndex,
                decoration: _inp('Growth Stage'),
                items: List.generate(
                  kGrowthStages.length,
                  (i) => DropdownMenuItem<int>(
                    value: i,
                    child: Text(kGrowthStages[i]),
                  ),
                ),
                onChanged: (v) => stageIndex = v ?? stageIndex,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: targetYield,
                keyboardType: TextInputType.number,
                decoration: _inp('Target Yield (kg)'),
              ),
              const SizedBox(height: 10),
              TextField(
                readOnly: true,
                controller: expectedHarvest,
                decoration: _inp('Expected Harvest').copyWith(
                  suffixIcon: const Icon(Icons.event),
                ),
                onTap: () async {
                  FocusScope.of(context).unfocus();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(expectedHarvest.text) ??
                        (DateTime.tryParse(date.text) ?? DateTime.now()).add(const Duration(days: 60)),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    expectedHarvest.text = DateFormat('yyyy-MM-dd').format(picked);
                  }
                },
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () async {
                  setState(() {
                    _selected!
                      ..name = name.text.trim().isEmpty ? _selected!.name : name.text.trim()
                      ..plantedOn = date.text
                      ..growthStageIndex = stageIndex
                      ..targetYieldKg = targetYield.text.trim().isEmpty
                          ? null
                          : double.tryParse(targetYield.text.trim())
                      ..expectedHarvest = expectedHarvest.text.trim().isEmpty
                          ? null
                          : expectedHarvest.text.trim();
                  });
                  _savePlots();

                  // --- Persist details to server (PATCH) ---
                  final idInt = int.tryParse(_selected!.id);
                  if (idInt != null) {
                    try {
                      await PlotService().updateDetails(
                        plotId: idInt,
                        name: _selected!.name,
                        crop: _selected!.crop,
                        plantedAt: _selected!.plantedOn,
                        expectedHarvest: _selected!.expectedHarvest,
                        growthStage: kGrowthStages[_selected!.growthStageIndex],
                        targetYieldKg: _selected!.targetYieldKg,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Details saved to server')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Server save failed: $e')),
                        );
                      }
                    }
                  }

                  if (mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static InputDecoration _inp(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );

  // ---- Weather fetch ----
  Future<void> _fetchWeather() async {
    if (_owmApiKey.isEmpty || _owmApiKey == 'YOUR_OPENWEATHERMAP_API_KEY') {
      setState(() {
        _weatherErr = 'Add your OpenWeatherMap API key';
        _weatherLoading = false;
      });
      return;
    }
    setState(() {
      _weatherLoading = true;
      _weatherErr = null;
    });
    try {
      final uri = Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?lat=${_initialCenter.latitude}&lon=${_initialCenter.longitude}&units=metric&appid=$_owmApiKey');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final main = j['main'] as Map<String, dynamic>;
        final weatherArr = j['weather'] as List;
        setState(() {
          _weatherTempC = (main['temp'] as num?)?.toDouble();
          _weatherMain = (weatherArr.isNotEmpty ? weatherArr.first['main'] : '')?.toString();
          _weatherLoading = false;
        });
      } else {
        setState(() {
          _weatherErr = 'Weather error ${res.statusCode}';
          _weatherLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _weatherErr = 'Weather fetch failed';
        _weatherLoading = false;
      });
    }
  }

  // ---------- UI ----------
  Widget _toolButton(IconData icon, DrawTool t) {
    final isSel = _tool == t;
    return Material(
      color: isSel ? Colors.green[50] : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          setState(() {
            _tool = t;
            _drawing.clear();
            _anchor = null;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: isSel ? Colors.green[700] : Colors.black87),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final polygons = _plots
        .where((p) => p.points.isNotEmpty)
        .map((p) => _polygonFor(p, selected: _selected?.id == p.id))
        .toList(growable: true);

    if (_drawing.length >= 2) {
      polygons.add(Polygon(
        points: _ensureClosed(_drawing),
        color: Colors.blue.withOpacity(0.18),
        borderColor: Colors.blue,
        borderStrokeWidth: 2,
      ));
    }

    final previewLines = <Polyline>[];
    if (_drawing.length >= 2) {
      previewLines.add(Polyline(points: _drawing, strokeWidth: 3, color: Colors.blueAccent));
    }
    final vertexMarkers = <Marker>[
      for (final p in _drawing)
        Marker(
          point: p,
          width: 18,
          height: 18,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blueAccent, width: 2),
            ),
          ),
        ),
    ];

    final progress = _selected?.progress() ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('Mapping', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Edit selected',
            icon: const Icon(Icons.edit),
            onPressed: _selected == null ? null : _editSelectedDetails,
          ),
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
            onPressed: _plots.isEmpty && _drawing.isEmpty ? null : _undo,
          ),
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_outline),
            onPressed: _plots.isEmpty && _drawing.isEmpty ? null : _clearAll,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 16.0,
              onTap: (_, pt) => _onTap(pt),
              onLongPress: (_, pt) => _onLongPress(pt),
            ),
            children: [
              TileLayer(
                // single endpoint per OSM guidance
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.lim.farmapp',
              ),
              PolylineLayer(polylines: previewLines),
              PolygonLayer(polygons: polygons),
              MarkerLayer(markers: vertexMarkers),
              if (_resizeMode && _selected != null)
                DragMarkers(markers: _buildHandlesForSelected()),
            ],
          ),

          // ---- On-map zoom / resize buttons (bottom-right) ----
          Positioned(
            right: 12,
            bottom: 92,
            child: Column(
              children: [
                _MapFab(
                  icon: Icons.add,
                  onTap: () => _map.move(_map.camera.center, (_map.camera.zoom + 1).clamp(1, 20)),
                ),
                const SizedBox(height: 8),
                _MapFab(
                  icon: Icons.remove,
                  onTap: () => _map.move(_map.camera.center, (_map.camera.zoom - 1).clamp(1, 20)),
                ),
                const SizedBox(height: 16),
                _MapFab(
                  icon: Icons.zoom_in_map,
                  onTap: _selected == null ? () {} : () => _resizeSelected(1.1),
                ),
                const SizedBox(height: 8),
                _MapFab(
                  icon: Icons.zoom_out_map,
                  onTap: _selected == null ? () {} : () => _resizeSelected(0.9),
                ),
              ],
            ),
          ),

          // ---- Draggable toolbar (right) ----
          Builder(
            builder: (ctx) {
              final size = MediaQuery.of(ctx).size;
              const toolbarWidth = 56.0;
              final defaultLeft = size.width - toolbarWidth - 12.0;
              final defaultTop = 110.0;
              final left = (_tbLeft < 0) ? defaultLeft : _tbLeft;
              final top = (_tbTop < 0) ? defaultTop : _tbTop;

              // rough height estimate for clamping
              const estimatedToolbarHeight = 56.0 + 8 * 40.0;

              return Positioned(
                left: left,
                top: top,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    final curLeft = (_tbLeft < 0) ? defaultLeft : _tbLeft;
                    final curTop = (_tbTop < 0) ? defaultTop : _tbTop;
                    setState(() {
                      _tbLeft = (curLeft + details.delta.dx)
                          .clamp(0.0, size.width - toolbarWidth);
                      _tbTop = (curTop + details.delta.dy)
                          .clamp(0.0, size.height - estimatedToolbarHeight);
                    });
                  },
                  onPanEnd: (_) => _saveToolbarPos(),
                  onDoubleTap: () {
                    setState(() {
                      _tbLeft = defaultLeft;
                      _tbTop = defaultTop;
                    });
                    _saveToolbarPos();
                  },
                  child: Container(
                    width: toolbarWidth,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _toolButton(Icons.open_with, DrawTool.pan),
                        const SizedBox(height: 6),
                        _toolButton(Icons.place, DrawTool.point),
                        const SizedBox(height: 6),
                        _toolButton(Icons.gesture, DrawTool.polygon),
                        const SizedBox(height: 6),
                        _toolButton(Icons.crop_square, DrawTool.rectangle),
                        const SizedBox(height: 6),
                        _toolButton(Icons.circle_outlined, DrawTool.circle),
                        const Divider(height: 18, indent: 10, endIndent: 10),
                        IconButton(
                          tooltip: 'Finish shape',
                          onPressed: _drawing.isNotEmpty ? _finishDrawing : null,
                          icon: const Icon(Icons.check),
                          color: _drawing.isNotEmpty ? Colors.green[700] : Colors.black26,
                        ),
                        IconButton(
                          tooltip: 'Shrink selection',
                          onPressed: _selected == null ? null : () => _resizeSelected(0.9),
                          icon: const Icon(Icons.remove),
                          color: _selected == null ? Colors.black26 : Colors.black87,
                        ),
                        IconButton(
                          tooltip: 'Grow selection',
                          onPressed: _selected == null ? null : () => _resizeSelected(1.1),
                          icon: const Icon(Icons.add),
                          color: _selected == null ? Colors.black26 : Colors.black87,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // ---- Weather card (draggable, collapsible, dismissible) ----
          if (_wxVisible)
            Builder(
              builder: (ctx) {
                final size = MediaQuery.of(ctx).size;
                const cardWidth = 200.0;
                const chipSize = 44.0;
                final defaultLeft = 12.0;
                final defaultTop = 110.0;
                final left = (_wxLeft < 0) ? defaultLeft : _wxLeft;
                final top = (_wxTop < 0) ? defaultTop : _wxTop;
                final estHeight = _wxCollapsed ? chipSize : 92.0;

                Widget collapsedChip() => Container(
                      width: chipSize,
                      height: chipSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
                      ),
                      child: const Center(child: Icon(Icons.cloud)),
                    );

                Widget expandedCard() => Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Container(
                        width: cardWidth,
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.cloud, size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _weatherLoading
                                  ? const Text('Loading weather…')
                                  : (_weatherErr != null
                                      ? Text(_weatherErr!, style: const TextStyle(color: Colors.red))
                                      : Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _weatherMain ?? '--',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700, fontSize: 13),
                                            ),
                                            Text(
                                              _weatherTempC == null
                                                  ? '-- °C'
                                                  : '${_weatherTempC!.toStringAsFixed(1)} °C',
                                              style: const TextStyle(fontSize: 13),
                                            ),
                                          ],
                                        )),
                            ),
                            Column(
                              children: [
                                IconButton(
                                  tooltip: 'Refresh',
                                  icon: const Icon(Icons.refresh),
                                  onPressed: _fetchWeather,
                                ),
                                IconButton(
                                  tooltip: 'Minimize',
                                  icon: const Icon(Icons.expand_more),
                                  onPressed: () {
                                    setState(() => _wxCollapsed = true);
                                    _saveWeatherUiPrefs();
                                  },
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    );

                return Positioned(
                  left: left,
                  top: top,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      final curLeft = (_wxLeft < 0) ? defaultLeft : _wxLeft;
                      final curTop = (_wxTop < 0) ? defaultTop : _wxTop;
                      setState(() {
                        _wxLeft = (curLeft + details.delta.dx)
                            .clamp(0.0, size.width - (_wxCollapsed ? chipSize : cardWidth));
                        _wxTop = (curTop + details.delta.dy)
                            .clamp(0.0, size.height - estHeight);
                      });
                    },
                    onPanEnd: (_) => _saveWeatherUiPrefs(),
                    onDoubleTap: () {
                      setState(() => _wxCollapsed = !_wxCollapsed);
                      _saveWeatherUiPrefs();
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _wxCollapsed ? collapsedChip() : expandedCard(),
                        if (!_wxCollapsed)
                          Positioned(
                            right: -8,
                            top: -8,
                            child: InkWell(
                              onTap: () {
                                setState(() => _wxVisible = false);
                                _saveWeatherUiPrefs();
                              },
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),

          // ---- Bottom card: My Crops + details + growth/goal ----
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('My Crops',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),

                    // --- Square crop tiles ---
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        itemCount: _crops.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            // Add-new tile
                            return SizedBox(
                              width: 84,
                              child: Column(
                                children: [
                                  InkWell(
                                    onTap: _addCustomCrop,
                                    child: Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: const [
                                          BoxShadow(blurRadius: 6, color: Colors.black12, offset: Offset(0, 2)),
                                        ],
                                      ),
                                      child: const Icon(Icons.add, size: 28),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const SizedBox(
                                    width: 64,
                                    child: Text('Add', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            );
                          }

                          final crop = _crops[i - 1];
                          final sel = _selectedCropId == crop.id;

                          return _CropSquareTile(
                            name: crop.name,
                            selected: sel,
                            isAsset: crop.isAsset,
                            imagePath: crop.imagePath,
                            onTap: () {
                              setState(() {
                                _selectedCropId = crop.id;
                                if (_selected != null) {
                                  _selected!.crop = crop.name;
                                  _savePlots();
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            readOnly: true,
                            controller: TextEditingController(text: _selected?.name ?? ''),
                            decoration: _inp('Name'),
                            onTap: _editSelectedDetails,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            readOnly: true,
                            controller: TextEditingController(
                                text: _selected == null
                                    ? ''
                                    : '${_selected!.areaM2.toStringAsFixed(0)} m²'),
                            decoration: _inp('Area'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      readOnly: true,
                      controller: TextEditingController(text: _selected?.plantedOn ?? ''),
                      decoration: _inp('Planting Date')
                          .copyWith(suffixIcon: const Icon(Icons.calendar_today)),
                      onTap: _editSelectedDetails,
                    ),
                    const SizedBox(height: 10),

                    if (_selected != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Growth: ${_selected!.growthLabel}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _editSelectedDetails,
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Update'),
                          )
                        ],
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: Colors.grey.shade200,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(progress >= 1 ? Colors.green : Colors.lightGreen),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selected!.expectedHarvest == null
                                  ? 'Harvest: —'
                                  : 'Harvest: ${_selected!.expectedHarvest}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            _selected!.targetYieldKg == null
                                ? 'Goal: —'
                                : 'Goal: ${_selected!.targetYieldKg!.toStringAsFixed(0)} kg',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: ''),
        ],
        onTap: (_) {},
      ),
    );
  }
}

// Small FAB used by the map zoom/resize controls
class _MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapFab({required this.icon, required this.onTap, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white)),
      ),
    );
  }
}

// --- Helper: square crop tile used in the bottom strip ---
class _CropSquareTile extends StatelessWidget {
  final String name;
  final bool selected;
  final bool isAsset;
  final String imagePath;
  final VoidCallback onTap;

  const _CropSquareTile({
    required this.name,
    required this.selected,
    required this.isAsset,
    required this.imagePath,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const double tileSide = 64;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 84,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: tileSide,
              height: tileSide,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black12, offset: Offset(0, 2))],
                border: Border.all(color: selected ? Colors.green : Colors.transparent, width: selected ? 2 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: isAsset
                  ? Image.asset(imagePath, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported))
                  : Image.file(File(imagePath), fit: BoxFit.cover),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: tileSide,
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
