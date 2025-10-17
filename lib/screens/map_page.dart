// lib/screens/map_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';
// NEW: backend service
import '../services/plot_service.dart';

enum DrawTool { pan, point, rectangle, square, circle, triangle }
enum ScaleScope { selected, sameCrop, all }
enum TaskType { watering, fertilising, weeding, inspection, harvest }
enum LayoutKind { rows, grid, triangular }

const List<String> kGrowthStages = [
  'Seedling',
  'Vegetative',
  'Flowering',
  'Harvest Ready',
];

const int kMaxGeneratedPlants = 6000;
const int kMaxPlantMarkers = 1200;

String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

class CropItem {
  final String id;
  final String name;
  final String imagePath;
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
  String? crop;
  List<LatLng> points;
  double areaM2;
  String plantedOn;

  int growthStageIndex;
  double? targetYieldKg;
  String? expectedHarvest;

  /// whether user set ETA manually (true) or we auto-calc (false)
  bool etaManual;

  String shape;
  double? circleCenterLat;
  double? circleCenterLng;
  double? circleRadiusM;

  bool locked;

  LayoutKind layoutKind;
  double? rowSpacingM;
  double? plantSpacingM;
  List<LatLng> plants;

  /// NEW (for water calc)
  double irrigationEfficiency; // 0–1, default 0.85
  double cropCalibration; // multiplier, default 1.0

  /// NEW: backend id for this plot (if synced)
  int? serverId;

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
    this.etaManual = false,
    this.shape = 'rectangle',
    this.circleCenterLat,
    this.circleCenterLng,
    this.circleRadiusM,
    this.locked = false,
    this.layoutKind = LayoutKind.rows,
    this.rowSpacingM,
    this.plantSpacingM,
    List<LatLng>? plants,
    this.irrigationEfficiency = 0.85,
    this.cropCalibration = 1.0,
    this.serverId,
  }) : plants = plants ?? <LatLng>[];

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
        'etaManual': etaManual,
        'shape': shape,
        'circleCenterLat': circleCenterLat,
        'circleCenterLng': circleCenterLng,
        'circleRadiusM': circleRadiusM,
        'locked': locked,
        'layoutKind': layoutKind.name,
        'rowSpacingM': rowSpacingM,
        'plantSpacingM': plantSpacingM,
        'plants': plants.map((p) => [p.latitude, p.longitude]).toList(),
        'irrigationEfficiency': irrigationEfficiency,
        'cropCalibration': cropCalibration,
        'serverId': serverId, // NEW
      };

  static PlotModel fromJson(Map<String, dynamic> m) => PlotModel(
        id: m['id'],
        name: m['name'],
        crop: m['crop'],
        points: (m['points'] as List)
            .map((xy) =>
                LatLng((xy[0] as num).toDouble(), (xy[1] as num).toDouble()))
            .toList(),
        areaM2: (m['areaM2'] as num).toDouble(),
        plantedOn: m['plantedOn'],
        growthStageIndex: (m['growthStageIndex'] ?? 0) as int,
        targetYieldKg: (m['targetYieldKg'] as num?)?.toDouble(),
        expectedHarvest: m['expectedHarvest'],
        etaManual: (m['etaManual'] ?? false) as bool,
        shape: (m['shape'] ?? 'rectangle') as String,
        circleCenterLat: (m['circleCenterLat'] as num?)?.toDouble(),
        circleCenterLng: (m['circleCenterLng'] as num?)?.toDouble(),
        circleRadiusM: (m['circleRadiusM'] as num?)?.toDouble(),
        locked: (m['locked'] ?? false) as bool,
        layoutKind: () {
          final v = (m['layoutKind'] ?? 'rows') as String;
          return LayoutKind.values
              .firstWhere((x) => x.name == v, orElse: () => LayoutKind.rows);
        }(),
        rowSpacingM: (m['rowSpacingM'] as num?)?.toDouble(),
        plantSpacingM: (m['plantSpacingM'] as num?)?.toDouble(),
        plants: ((m['plants'] as List?) ?? const [])
            .map((xy) => LatLng(
                  (xy[0] as num).toDouble(),
                  (xy[1] as num).toDouble(),
                ))
            .toList(),
        irrigationEfficiency:
            (m['irrigationEfficiency'] as num?)?.toDouble() ?? 0.85,
        cropCalibration: (m['cropCalibration'] as num?)?.toDouble() ?? 1.0,
        serverId: (m['serverId'] as num?)?.toInt(), // NEW
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

class TaskItem {
  String id;
  String plotId;
  String plotName;
  String? crop;
  TaskType type;
  String title;
  DateTime due;
  int? repeatEveryDays;
  bool done;

  TaskItem({
    required this.id,
    required this.plotId,
    required this.plotName,
    required this.type,
    required this.title,
    required this.due,
    this.crop,
    this.repeatEveryDays,
    this.done = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'plotId': plotId,
        'plotName': plotName,
        'crop': crop,
        'type': type.name,
        'title': title,
        'due': due.toIso8601String(),
        'repeatEveryDays': repeatEveryDays,
        'done': done,
      };

  static TaskItem fromJson(Map<String, dynamic> m) => TaskItem(
        id: m['id'],
        plotId: m['plotId'],
        plotName: m['plotName'],
        crop: m['crop'],
        type: TaskType.values.firstWhere((t) => t.name == m['type']),
        title: m['title'],
        due: DateTime.parse(m['due']),
        repeatEveryDays: m['repeatEveryDays'],
        done: (m['done'] ?? false) as bool,
      );
}

// ===== Crop care profiles (with maturityDays + water mm/day) =====
class CropCareProfile {
  final int wateringEveryDaysSeedling;
  final int wateringEveryDaysVeg;
  final int fertiliseAfterDaysFromPlanting;
  final int weedingEveryDays;
  final int preHarvestInspectionDaysBefore;
  final int maturityDays;

  // NEW water baselines (mm per m² per day)
  final double waterSeedlingMmPerDay;
  final double waterVegMmPerDay;
  final double waterFlowerMmPerDay;

  const CropCareProfile({
    required this.wateringEveryDaysSeedling,
    required this.wateringEveryDaysVeg,
    required this.fertiliseAfterDaysFromPlanting,
    required this.weedingEveryDays,
    required this.preHarvestInspectionDaysBefore,
    required this.maturityDays,
    required this.waterSeedlingMmPerDay,
    required this.waterVegMmPerDay,
    required this.waterFlowerMmPerDay,
  });

  double waterForStageMmPerDay(int stageIndex) {
    if (stageIndex <= 0) return waterSeedlingMmPerDay;
    if (stageIndex == 1) return waterVegMmPerDay;
    return waterFlowerMmPerDay;
  }
}

const Map<String, CropCareProfile> kCropProfiles = {
  'tomato': CropCareProfile(
    wateringEveryDaysSeedling: 1,
    wateringEveryDaysVeg: 2,
    fertiliseAfterDaysFromPlanting: 21,
    weedingEveryDays: 7,
    preHarvestInspectionDaysBefore: 10,
    maturityDays: 90,
    waterSeedlingMmPerDay: 3.0,
    waterVegMmPerDay: 4.5,
    waterFlowerMmPerDay: 5.5,
  ),
  'mint': CropCareProfile(
    wateringEveryDaysSeedling: 1,
    wateringEveryDaysVeg: 2,
    fertiliseAfterDaysFromPlanting: 14,
    weedingEveryDays: 10,
    preHarvestInspectionDaysBefore: 7,
    maturityDays: 60,
    waterSeedlingMmPerDay: 3.0,
    waterVegMmPerDay: 4.0,
    waterFlowerMmPerDay: 4.0,
  ),
  'coriander': CropCareProfile(
    wateringEveryDaysSeedling: 1,
    wateringEveryDaysVeg: 2,
    fertiliseAfterDaysFromPlanting: 10,
    weedingEveryDays: 10,
    preHarvestInspectionDaysBefore: 7,
    maturityDays: 45,
    waterSeedlingMmPerDay: 2.0,
    waterVegMmPerDay: 3.0,
    waterFlowerMmPerDay: 3.0,
  ),
  'wheat': CropCareProfile(
    wateringEveryDaysSeedling: 1,
    wateringEveryDaysVeg: 2,
    fertiliseAfterDaysFromPlanting: 25,
    weedingEveryDays: 10,
    preHarvestInspectionDaysBefore: 10,
    maturityDays: 120,
    waterSeedlingMmPerDay: 2.0,
    waterVegMmPerDay: 3.0,
    waterFlowerMmPerDay: 3.5,
  ),
};

// ---------- Days-to-harvest DTO ----------
class DaysToHarvest {
  final int daysLeft;
  final int dayNumber;
  final int totalDays;
  final DateTime eta;
  const DaysToHarvest(this.daysLeft, this.dayNumber, this.totalDays, this.eta);
}

InputDecoration _inp(String label) => InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );

class _Bounds {
  final LatLng nw;
  final LatLng se;
  const _Bounds(this.nw, this.se);
}

class MapPage extends StatefulWidget {
  const MapPage({Key? key}) : super(key: key);
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {

  // === NOTIFICATION HELPERS (ADD INSIDE _MapPageState) ===

// stable int from a task id string
int _notifIdFor(String s) => s.hashCode & 0x7fffffff;

/// Schedule notifications for all tasks belonging to a plot.
/// Skips done/past tasks.
Future<void> _scheduleNotificationsForPlot(PlotModel p) async {
  await NotificationService.I.requestPermissions(); // safe to call multiple times
  for (final t in _tasks.where((x) => x.plotId == p.id)) {
    if (t.done) continue;
    if (t.due.isBefore(DateTime.now().subtract(const Duration(minutes: 1)))) {
      continue;
    }
    await NotificationService.I.schedule(
      id: _notifIdFor(t.id),
      title: t.title,
      body: 'Plot: ${t.plotName}${t.crop != null ? ' (${t.crop})' : ''}',
      whenLocal: t.due,
      payload: t.id,
    );
  }
}

/// Cancel any pending notifications for a plot (use on delete)
Future<void> _cancelNotificationsForPlot(PlotModel p) async {
  for (final t in _tasks.where((x) => x.plotId == p.id)) {
    await NotificationService.I.cancel(_notifIdFor(t.id));
  }
}

  final MapController _map = MapController();
  final Distance _dist = const Distance();

  DrawTool _tool = DrawTool.pan;

  final List<PlotModel> _plots = [];
  final List<LatLng> _drawing = [];
  PlotModel? _selected;

  bool _lockNewUntilSaved = false;

  LatLng? _anchor;
  LatLng? _anchor2;

  final List<CropItem> _crops = [];
  String? _selectedCropId;

  double _tbLeft = -1, _tbTop = -1;

  LatLng? _pendingCircleCenter;
  double? _pendingCircleRadiusM;

  bool _resizeMode = false;
  bool _scaleActive = false;
  List<LatLng>? _scaleBaseOpenPoints;
  double? _scaleBaseRadiusM;
  LatLng? _scaleCenter;

  double _scaleSlider = 1.0;
  ScaleScope _scaleScope = ScaleScope.selected;
  final Map<String, List<LatLng>> _scopeBaseOpen = {};
  final Map<String, double?> _scopeBaseRadius = {};
  final Map<String, LatLng> _scopeBaseCenter = {};

  late TextEditingController _selNameCtrl;
  late TextEditingController _selAreaCtrl;
  late TextEditingController _selPlantingDateCtrl;

  final _rowSpacingCtrl = TextEditingController();
  final _plantSpacingCtrl = TextEditingController();
  final _targetCountCtrl = TextEditingController();

  final List<TaskItem> _tasks = [];

  final LatLng _initialCenter = const LatLng(-27.4698, 153.0251);

  bool _showWeather = false;
  String? _weatherText;
  Timer? _weatherDebounce;

  double? _currentTempC; // NEW for water calc

  // NEW: route-arg handling flag
  bool _handledArgs = false;

  Future<void> _fetchWeatherFor(LatLng at) async {
  HttpClient? client;
  try {
    client = HttpClient();
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=${at.latitude}&longitude=${at.longitude}'
      '&current=temperature_2m,wind_speed_10m',
    );
    final req = await client.getUrl(uri);
    final res = await req.close();
    final body = await res.transform(const Utf8Decoder()).join();
    final m = jsonDecode(body) as Map<String, dynamic>;
    final cur = Map<String, dynamic>.from(m['current'] ?? {});
    final t = (cur['temperature_2m'] as num?)?.toDouble();
    final w = (cur['wind_speed_10m'] as num?)?.toDouble();
    setState(() {
      _currentTempC = t;
      _weatherText = (t == null || w == null)
          ? 'Weather unavailable'
          : '${t.toStringAsFixed(1)}°C · wind ${w.toStringAsFixed(1)} m/s';
    });
  } catch (_) {
    setState(() => _weatherText = 'Weather unavailable');
  } finally {
    client?.close(force: true);
  }
}


  final List<String> _history = [];
  final List<String> _future = [];
  void _pushHistory() {
    _history.add(jsonEncode(_plots.map((p) => p.toJson()).toList()));
    if (_history.length > 50) _history.removeAt(0);
    _future.clear();
  }

  void _restoreFromJson(String snap) {
    final list = (jsonDecode(snap) as List)
        .map((e) => PlotModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    setState(() {
      _plots
        ..clear()
        ..addAll(list);
      _selected = null;
    });
  }

  bool _isNameTaken(String name, {String? exceptId}) {
    final n = name.trim().toLowerCase();
    for (final p in _plots) {
      if (exceptId != null && p.id == exceptId) continue;
      if (p.name.trim().toLowerCase() == n) return true;
    }
    return false;
  }

  // ======== BACKEND SYNC HELPERS ========

  String _backendShape(PlotModel p) {
    switch (p.shape) {
      case 'point':
        return 'point';
      case 'circle':
        return 'circle';
      case 'rectangle':
      case 'square':
        return 'rectangle';
      default:
        return 'polygon'; // triangle / freeform etc.
    }
  }

  Future<void> _saveToBackend(PlotModel p) async {
    final svc = PlotService();
    final shape = _backendShape(p);
    final open = _withoutClosingPoint(p.points);

    try {
      if (p.serverId == null) {
        // CREATE
        final res = await svc.createPlotFromShape(
          shape: shape,
          name: p.name,
          plantedAt: p.plantedOn, // 'YYYY-MM-DD'
          notes: '',
          growthStage: p.growthLabel,
          crop: p.crop,
          expectedHarvest: p.etaManual ? p.expectedHarvest : null,
          targetYieldKg: p.targetYieldKg,
          points:
              open.isNotEmpty ? open : (p.circleCenter != null ? [p.circleCenter!] : []),
          circleCenter: p.circleCenter,
          circleRadiusM: p.circleRadiusM,
          explicitAreaM2: p.areaM2,
        );
        setState(() => p.serverId = (res['id'] as num).toInt());
      } else {
        // UPDATE
        await svc.updateGeometryFromShape(
          plotId: p.serverId!,
          shape: shape,
          points:
              open.isNotEmpty ? open : (p.circleCenter != null ? [p.circleCenter!] : []),
          circleCenter: p.circleCenter,
          circleRadiusM: p.circleRadiusM,
          explicitAreaM2: p.areaM2,
        );
        await svc.updateDetails(
          plotId: p.serverId!,
          name: p.name,
          crop: p.crop,
          plantedAt: p.plantedOn,
          expectedHarvest: p.etaManual ? p.expectedHarvest : null,
          growthStage: p.growthLabel,
          targetYieldKg: p.targetYieldKg,
        );
      }
    } catch (e) {
      _showSnack('Backend sync failed: $e');
    }
  }

  Future<void> _deleteFromBackend(PlotModel p) async {
    if (p.serverId == null) return;
    try {
      await PlotService().deletePlot(p.serverId!);
    } catch (e) {
      _showSnack('Delete on server failed: $e');
    }
  }

  // ======================================

  Future<void> _saveSelectedWithValidation() async {
  if (_selected == null) return;
  final p = _selected!;
  final nm = p.name.trim();
  if (nm.isEmpty) {
    _showSnack('Please give the plot a name.');
    return;
  }
  if (_isNameTaken(nm, exceptId: p.id)) {
    _showSnack('That plot name already exists. Use a unique name.');
    return;
  }
  if (p.crop == null || p.crop!.trim().isEmpty) {
    _showSnack('Pick the crop for this plot first.');
    return;
  }
  final hasGoal = (p.targetYieldKg ?? 0) > 0;
  final stageChosen = p.growthStageIndex != 0 || p.expectedHarvest != null;
  if (!hasGoal && !stageChosen) {
    _showSnack('Enter a yield goal (kg) OR set a growth stage via Update.');
    await _editSelectedDetails();
    return;
  }

  setState(() => p.locked = true);
  await _savePlots();

  // --- generate tasks ---
  await _regenerateTasksForPlot(p);

  // Schedule notifications for this plot’s tasks
await NotificationService.I.requestPermissions();
await _scheduleNotificationsForPlot(p);

final created = _tasks.where((t) => t.plotId == p.id).length;
_showSnack('Generated $created tasks for "${p.name}"');
await _saveToBackend(p);


  // 👇 Add these three lines:
  
  _showSnack('Plot saved.');
}


  @override
  void initState() {
    super.initState();
    _selNameCtrl = TextEditingController();
    _selAreaCtrl = TextEditingController();
    _selPlantingDateCtrl = TextEditingController();
    _initCrops();
    _loadPlots();
    _loadTasks();
    _loadToolbarPos();
    _fetchWeatherFor(_initialCenter);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledArgs) return;
    _handledArgs = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final plotIdStr = args['plotId']?.toString();
      final centerMap = args['center'];
      LatLng? center;
      if (centerMap is Map) {
        final lat = (centerMap['lat'] as num?)?.toDouble();
        final lng = (centerMap['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) center = LatLng(lat, lng);
      }

      if (plotIdStr != null) {
        final wantId = int.tryParse(plotIdStr);
        final match = _plots.where((p) => p.serverId == wantId).toList();
        if (match.isNotEmpty) {
          setState(() => _selected = match.first);
          _syncSelectedToFields();
          center ??= (_selected!.shape == 'circle' && _selected!.circleCenter != null)
              ? _selected!.circleCenter
              : _centroid(_selected!.points);
        }
      }

      if (center != null) {
        _map.move(center, _map.camera.zoom);
      }
    }
  }

  @override
  void dispose() {
    _selNameCtrl.dispose();
    _selAreaCtrl.dispose();
    _selPlantingDateCtrl.dispose();
    _rowSpacingCtrl.dispose();
    _plantSpacingCtrl.dispose();
    _targetCountCtrl.dispose();
    _weatherDebounce?.cancel();
    super.dispose();
  }

  void _updateSelectedCropIdFromPlot() {
    final plotCrop = _selected?.crop?.trim();
    String? id;
    if (plotCrop != null && plotCrop.isNotEmpty) {
      final lc = plotCrop.toLowerCase();
      for (final c in _crops) {
        if (c.name.toLowerCase() == lc) {
          id = c.id;
          break;
        }
      }
    }
    setState(() {
      _selectedCropId = id;
    });
  }

  void _syncSelectedToFields() {
    _selNameCtrl.text = _selected?.name ?? '';
    _selAreaCtrl.text =
        _selected == null ? '' : '${_selected!.areaM2.toStringAsFixed(0)} m²';
    _selPlantingDateCtrl.text = _selected?.plantedOn ?? '';
    if (_selected != null) {
      _rowSpacingCtrl.text =
          (_selected!.rowSpacingM ?? 1.0).toStringAsFixed(1);
      _plantSpacingCtrl.text =
          (_selected!.plantSpacingM ?? 0.5).toStringAsFixed(1);
    } else {
      _rowSpacingCtrl.text = '';
      _plantSpacingCtrl.text = '';
    }
    _updateSelectedCropIdFromPlot();
  }

  Color _colorForPlot(PlotModel p) {
  String stage = p.growthLabel;
  // If you want to *derive* a visual “ready” color by ETA, do it without mutating:
  try {
    if ((p.expectedHarvest != null) && p.expectedHarvest!.trim().isNotEmpty) {
      final due = DateTime.parse(p.expectedHarvest!);
      if (!DateTime.now().isBefore(due)) {
        stage = 'Harvest Ready';
      }
    }
  } catch (_) {}
  if (stage == 'Seedling') return Colors.red;
  if (stage == 'Harvest Ready') return Colors.green;
  return Colors.amber;
}


  Color _dotColorForPlot(PlotModel p) {
    final label = p.growthLabel;
    if (label == 'Seedling') return Colors.red.shade700;
    if (label == 'Harvest Ready') return Colors.green.shade700;
    return Colors.amber.shade700;
  }

  Future<void> _confirmAndDeleteSelected() async {
    if (_selected == null) return;
    final p = _selected!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete plot?'),
        content:
            Text('Are you sure you want to delete "${p.name}" and its tasks?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      // Cancel notifications for this plot before deleting
      await _cancelNotificationsForPlot(p);

      _pushHistory();
      setState(() {
        _plots.removeWhere((x) => x.id == p.id);
        _tasks.removeWhere((t) => t.plotId == p.id);
        _selected = null;
        _lockNewUntilSaved = false;
        _selectedCropId = null;
      });
      await _savePlots();
      await _saveTasks();
      

      await _deleteFromBackend(p); // NEW
      _syncSelectedToFields();
    }
  }

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

  Future<void> _initCrops() async {
    final defaults = <CropItem>[
      const CropItem(
          id: 'tomato',
          name: 'Tomato',
          imagePath: 'media/tomato.png',
          isAsset: true),
      const CropItem(
          id: 'mint', name: 'Mint', imagePath: 'media/mint.png', isAsset: true),
      const CropItem(
          id: 'coriander',
          name: 'Coriander',
          imagePath: 'media/coriander.png',
          isAsset: true),
      const CropItem(
          id: 'chives',
          name: 'Chives',
          imagePath: 'media/chives.png',
          isAsset: true),
      const CropItem(
          id: 'parsley',
          name: 'Parsley',
          imagePath: 'media/parsley.png',
          isAsset: true),
      const CropItem(
          id: 'dill', name: 'Dill', imagePath: 'media/dill.png', isAsset: true),
      const CropItem(
          id: 'kale', name: 'Kale', imagePath: 'media/kale.png', isAsset: true),
      const CropItem(
          id: 'asparagus',
          name: 'Asparagus',
          imagePath: 'media/asparagus.png',
          isAsset: true),
      const CropItem(
          id: 'wheat',
          name: 'Wheat',
          imagePath: 'media/wheat.jpeg',
          isAsset: true),
    ];
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('custom_crops_v1');
    final custom = <CropItem>[];
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
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
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final nameCtrl = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Crop name'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Basil'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameCtrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    setState(() {
      _crops.add(CropItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        imagePath: picked.path,
        isAsset: false,
      ));
      _selectedCropId = _crops.last.id;
    });

    await _saveCustomCrops();
  }

  Future<void> _loadPlots() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('plots_v1');
    if (raw == null) {
      _pushHistory();
      return;
    }
    final list = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    setState(() {
      _plots
        ..clear()
        ..addAll(list.map(PlotModel.fromJson));
    });
    _pushHistory();
    _updateSelectedCropIdFromPlot();
  }

  Future<void> _savePlots() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      'plots_v1',
      jsonEncode(_plots.map((p) => p.toJson()).toList()),
    );
    setState(() => _lockNewUntilSaved = false);
  }

  Future<void> _loadTasks() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('tasks_v1');
    if (raw == null) return;
    final list = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map(TaskItem.fromJson)
        .toList();
    setState(() {
      _tasks
        ..clear()
        ..addAll(list);
    });
  }

  Future<void> _saveTasks() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      'tasks_v1',
      jsonEncode(_tasks.map((t) => t.toJson()).toList()),
    );
  }

  List<LatLng> _withoutClosingPoint(List<LatLng> pts) {
    if (pts.length >= 2) {
      final f = pts.first, l = pts.last;
      if (f.latitude == l.latitude && f.longitude == l.longitude) {
        return pts.sublist(0, pts.length - 1);
      }
    }
    return pts;
  }

  List<LatLng> _ensureClosed(List<LatLng> pts) {
    if (pts.isEmpty) return pts;
    final first = pts.first, last = pts.last;
    if (first.latitude == last.latitude && first.longitude == last.longitude) {
      return pts;
    }
    return [...pts, first];
  }

  List<LatLng> _rectOpen(LatLng a, LatLng b) {
    final n = math.max(a.latitude, b.latitude);
    final s = math.min(a.latitude, b.latitude);
    final e = math.max(a.longitude, b.longitude);
    final w = math.min(a.longitude, b.longitude);
    return [LatLng(n, w), LatLng(n, e), LatLng(s, e), LatLng(s, w)];
  }

  List<LatLng> _squareOpen(LatLng a, LatLng b) {
    final dyM = _dist.distance(
        LatLng(a.latitude, a.longitude), LatLng(b.latitude, a.longitude));
    final dxM = _dist.distance(
        LatLng(a.latitude, a.longitude), LatLng(a.latitude, b.longitude));
    final sideM = math.max(dxM, dyM);

    final north = b.latitude >= a.latitude;
    final east = b.longitude >= a.longitude;

    final toLat = _dist.offset(a, sideM, north ? 0 : 180).latitude;
    final toLng = _dist.offset(a, sideM, east ? 90 : 270).longitude;

    final n = north ? toLat : a.latitude;
    final s = north ? a.latitude : toLat;
    final e = east ? toLng : a.longitude;
    final w = east ? a.longitude : toLng;

    return [LatLng(n, w), LatLng(n, e), LatLng(s, e), LatLng(s, w)];
  }

  double _areaM2(List<LatLng> poly) {
    final pts = _withoutClosingPoint(poly);
    if (pts.length < 3) return 0;
    final ref = pts[0];
    final proj = pts
        .map((p) {
          final dx = _dist.distance(LatLng(ref.latitude, p.longitude), ref);
          final dy = _dist.distance(LatLng(p.latitude, ref.longitude), ref);
          return Offset(
              p.longitude >= ref.longitude ? dx : -dx,
              p.latitude >= ref.latitude ? dy : -dy);
        })
        .toList();
    double sum = 0;
    for (int i = 0; i < proj.length; i++) {
      final a = proj[i], b = proj[(i + 1) % proj.length];
      sum += (a.dx * b.dy - b.dx * a.dy);
    }
    return (sum.abs() * 0.5);
  }

  List<LatLng> _circleRing(LatLng c, double r, {int segments = 48}) =>
      List.generate(
          segments, (i) => _dist.offset(c, r, (i / segments) * 360.0))
        ..add(_dist.offset(c, r, 0));

  LatLng _centroid(List<LatLng> poly) {
    final pts = _withoutClosingPoint(poly);
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    final n = math.max(1, pts.length);
    return LatLng(lat / n, lng / n);
  }

  bool _pointInPolygon(LatLng p, List<LatLng> poly) {
    final pts = _withoutClosingPoint(poly);
    if (pts.isEmpty) return false;
    bool c = false;
    for (int i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      final pi = pts[i], pj = pts[j];
      final intersect = ((pi.longitude > p.longitude) !=
              (pj.longitude > p.longitude)) &&
          (p.latitude <
              (pj.latitude - pi.latitude) *
                      (p.longitude - pi.longitude) /
                      (pj.longitude - pi.longitude) +
                  pi.latitude);
      if (intersect) c = !c;
    }
    return c;
  }

  bool _insidePlot(LatLng p, List<LatLng> poly) => _pointInPolygon(p, poly);

  List<LatLng> _pointsAlong(LatLng a, LatLng b, double spacingM) {
    final total = _dist.distance(a, b);
    if (spacingM <= 0 || total <= 0) return const [];
    final n = (total / spacingM).floor();
    if (n <= 0) return const [];
    final brg = _dist.bearing(a, b);
    return List.generate(n, (i) => _dist.offset(a, spacingM * (i + 1), brg));
  }

  _Bounds _boundsOf(List<LatLng> closed) {
    final open = _withoutClosingPoint(closed);
    double n = -90, s = 90, e = -180, w = 180;
    for (final p in open) {
      n = math.max(n, p.latitude);
      s = math.min(s, p.latitude);
      e = math.max(e, p.longitude);
      w = math.min(w, p.longitude);
    }
    return _Bounds(LatLng(n, w), LatLng(s, e));
  }

  List<LatLng> _generateRowLayout(
      PlotModel p, double rowSpacingM, double plantSpacingM) {
    final pts = <LatLng>[];
    final center = (p.shape == 'circle' && p.circleCenter != null)
        ? p.circleCenter!
        : _centroid(p.points);
    final b = _boundsOf(p.points);
    final north = b.nw.latitude;
    final south = b.se.latitude;
    double curLat = north;
    int safe = 0;
    while (curLat >= south &&
        safe++ < 2000 &&
        pts.length < kMaxGeneratedPlants) {
      final westPt = LatLng(curLat, b.nw.longitude);
      final eastPt = LatLng(curLat, b.se.longitude);
      final linePts = _pointsAlong(westPt, eastPt, plantSpacingM);
      for (final q in linePts) {
        if (pts.length >= kMaxGeneratedPlants) break;
        if (_insidePlot(q, p.points)) pts.add(q);
      }
      curLat =
          _dist.offset(LatLng(curLat, center.longitude), rowSpacingM, 180).latitude;
    }
    return pts;
  }

  List<LatLng> _generateGridLayout(
      PlotModel p, double rowSpacingM, double plantSpacingM) {
    final pts = <LatLng>[];
    final b = _boundsOf(p.points);

    final widthM = _dist.distance(
      LatLng(b.nw.latitude, b.nw.longitude),
      LatLng(b.nw.latitude, b.se.longitude),
    );
    final heightM = _dist.distance(
      LatLng(b.nw.latitude, b.nw.longitude),
      LatLng(b.se.latitude, b.nw.longitude),
    );

    int rows = math.max(2, (heightM / rowSpacingM).round() + 1);
    int cols = math.max(2, (widthM / plantSpacingM).round() + 1);

    final double dy = heightM / (rows - 1);
    final double dx = widthM / (cols - 1);

    int safe = 0;
    for (int r = 0; r < rows && pts.length < kMaxGeneratedPlants; r++) {
      final lat = _dist
          .offset(LatLng(b.nw.latitude, b.nw.longitude), r * dy, 180)
          .latitude;

      for (int c = 0; c < cols && pts.length < kMaxGeneratedPlants; c++) {
        final lon =
            _dist.offset(LatLng(lat, b.nw.longitude), c * dx, 90).longitude;
        final q = LatLng(lat, lon);

        if (_insidePlot(q, p.points)) pts.add(q);

        if (++safe > 200000) break;
      }
    }
    return pts;
  }

  List<LatLng> _generateTriangularLayout(
      PlotModel p, double rowSpacingM, double plantSpacingM) {
    final pts = <LatLng>[];
    final b = _boundsOf(p.points);
    bool offsetRow = false;
    int safeRows = 0;
    for (double lat = b.nw.latitude;
        lat >= b.se.latitude &&
            safeRows++ < 2000 &&
            pts.length < kMaxGeneratedPlants;
        lat = _dist
            .offset(LatLng(lat, b.nw.longitude), rowSpacingM * 0.866, 180)
            .latitude) {
      double startLon = b.nw.longitude;
      if (offsetRow) {
        startLon =
            _dist.offset(LatLng(lat, startLon), plantSpacingM * 0.5, 90).longitude;
      }
      int safeCols = 0;
      for (double lon = startLon;
          lon <= b.se.longitude &&
              safeCols++ < 2000 &&
              pts.length < kMaxGeneratedPlants;
          lon = _dist.offset(LatLng(lat, lon), plantSpacingM, 90).longitude) {
        final q = LatLng(lat, lon);
        if (_insidePlot(q, p.points)) pts.add(q);
      }
      offsetRow = !offsetRow;
    }
    return pts;
  }

  List<LatLng> _generateLayoutPoints(
      PlotModel p, LayoutKind kind, double rowSpacingM, double plantSpacingM) {
    switch (kind) {
      case LayoutKind.rows:
        return _generateRowLayout(p, rowSpacingM, plantSpacingM);
      case LayoutKind.grid:
        return _generateGridLayout(p, rowSpacingM, plantSpacingM);
      case LayoutKind.triangular:
        return _generateTriangularLayout(p, rowSpacingM, plantSpacingM);
    }
  }

  double _perPlantYieldGuessKg(String? cropName) {
    if (cropName == null) return 0.0;
    final c = cropName.toLowerCase();
    if (c.contains('tomato')) return 2.5;
    if (c.contains('mint')) return 0.10;
    if (c.contains('coriander')) return 0.08;
    if (c.contains('wheat')) return 0.04;
    return 0.0;
  }

  // ===== Profile, ETA, and day-tracker helpers =====
  CropCareProfile _profileFor(String? cropName) {
    const def = CropCareProfile(
      wateringEveryDaysSeedling: 1,
      wateringEveryDaysVeg: 2,
      fertiliseAfterDaysFromPlanting: 21,
      weedingEveryDays: 10,
      preHarvestInspectionDaysBefore: 7,
      maturityDays: 60,
      waterSeedlingMmPerDay: 2.5,
      waterVegMmPerDay: 3.5,
      waterFlowerMmPerDay: 4.0,
    );
    if (cropName == null || cropName.trim().isEmpty) return def;
    final lc = cropName.toLowerCase();
    for (final e in kCropProfiles.entries) {
      if (lc.contains(e.key)) return e.value;
    }
    return def;
  }

  DateTime _autoHarvestDate(PlotModel p) {
    final planting = DateTime.tryParse(p.plantedOn) ?? DateTime.now();
    final prof = _profileFor(p.crop);
    return planting.add(Duration(days: prof.maturityDays));
  }

  DaysToHarvest _daysInfo(PlotModel p) {
    final today = DateTime.now();
    final planting = DateTime.tryParse(p.plantedOn) ?? today;

    // Use manual ETA if present; otherwise auto from crop maturity
    final eta = (p.etaManual && (p.expectedHarvest ?? '').trim().isNotEmpty)
        ? (DateTime.tryParse(p.expectedHarvest!) ?? _autoHarvestDate(p))
        : _autoHarvestDate(p);

    final total = (eta.difference(planting).inDays).clamp(1, 100000);
    final done = (today.difference(planting).inDays).clamp(0, total);
    final left = (eta.difference(today).inDays).clamp(0, 100000);

    return DaysToHarvest(left, done + 1, total, eta);
  }

  /// ======== WATER: liters/day for a plot (shown in sheet) ========
  double _litersPerDayForPlot({
    required PlotModel p,
    required int stageIndex,
    double? airTempC,
  }) {
    final prof = _profileFor(p.crop);
    final baseMm = prof.waterForStageMmPerDay(stageIndex);
    // +3% per °C above 20, -3% below, clamp 0.5–1.5
    double tempF = 1.0;
    if (airTempC != null) {
      tempF = (1.0 + 0.03 * (airTempC - 20.0)).clamp(0.5, 1.5);
    }
    final mmPerDay = baseMm * tempF * p.cropCalibration;
    // 1 mm = 1 L/m²; divide by efficiency to account for losses (e.g., 0.85)
    final eff = p.irrigationEfficiency.clamp(0.50, 0.99);
    final grossL = p.areaM2 * mmPerDay;
    return grossL / eff;
  }
  // ================================================================

  void _onTap(LatLng pt) async {
    if (_lockNewUntilSaved &&
        _tool != DrawTool.pan &&
        _tool != DrawTool.point &&
        _drawing.isEmpty) {
      _showSnack('Save or delete the current plot first.');
      return;
    }

    switch (_tool) {
      case DrawTool.pan:
        _selectPlotAt(pt);
        return;
      case DrawTool.point:
        _startOrReplaceOpen([pt]);
        await _finishDrawing();
        return;
      case DrawTool.rectangle:
        if (_anchor == null) {
          setState(() => _anchor = pt);
        } else {
          final open = _rectOpen(_anchor!, pt);
          _startOrReplaceOpen(open);
          await _finishDrawing();
        }
        return;
      case DrawTool.square:
        if (_anchor == null) {
          setState(() => _anchor = pt);
        } else {
          final open = _squareOpen(_anchor!, pt);
          _startOrReplaceOpen(open);
          await _finishDrawing();
        }
        return;
      case DrawTool.circle:
        if (_anchor == null) {
          setState(() => _anchor = pt);
        } else {
          final center = _anchor!;
          final r = _dist.distance(center, pt);
          _pendingCircleCenter = center;
          _pendingCircleRadiusM = r;
          _startOrReplaceOpen(_circleRing(center, r, segments: 48));
          await _finishDrawing();
        }
        return;
      case DrawTool.triangle:
        if (_anchor == null) {
          setState(() => _anchor = pt);
        } else if (_anchor2 == null) {
          setState(() => _anchor2 = pt);
          _startOrReplaceOpen([_anchor!, _anchor2!]);
        } else {
          final open = [_anchor!, _anchor2!, pt];
          _startOrReplaceOpen(open);
          await _finishDrawing();
          setState(() {
            _anchor = null;
            _anchor2 = null;
          });
        }
        return;
    }
  }

  void _onLongPress(LatLng pt) {
    if (_selected != null) {
      _confirmAndDeleteSelected();
      return;
    }
  }

  void _selectPlotAt(LatLng pt) {
    PlotModel? hit;
    for (final p in _plots.reversed) {
      if (p.shape == 'circle' && p.circleCenter != null) {
        final d = _dist.distance(p.circleCenter!, pt);
        if ((p.circleRadiusM ?? 0) > 0 && d <= (p.circleRadiusM ?? 0)) {
          hit = p;
          break;
        }
      } else if (_pointInPolygon(pt, p.points)) {
        hit = p;
        break;
      }
    }
    setState(() {
      _selected = hit;
      _scaleSlider = 1.0;
      if (_selected != null) _beginScaleBase();
    });
    _updateSelectedCropIdFromPlot();
    _syncSelectedToFields();
  }

  void _startOrReplaceOpen(List<LatLng> openRing) {
    setState(() {
      _drawing
        ..clear()
        ..addAll(openRing);
    });
  }

  Future<void> _finishDrawing() async {
    if (_drawing.isEmpty) return;

    final closed = _ensureClosed(_drawing);

    String? cropName;
    if (_selectedCropId != null && _crops.isNotEmpty) {
      final found = _crops.firstWhere(
          (c) => c.id == _selectedCropId!,
          orElse: () => _crops.first);
      cropName = found.name;
    }

    String shape = 'rectangle';
    if (_tool == DrawTool.square) shape = 'square';
    if (_tool == DrawTool.circle) shape = 'circle';
    if (_tool == DrawTool.point) shape = 'point';
    if (_tool == DrawTool.triangle) shape = 'triangle';

    final area = (shape == 'circle' && _pendingCircleRadiusM != null)
        ? math.pi * _pendingCircleRadiusM! * _pendingCircleRadiusM!
        : _areaM2(closed);

    final plot = PlotModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Plot ${_plots.length + 1}',
      crop: cropName,
      points: closed,
      areaM2: area,
      plantedOn: _fmt(DateTime.now()),
      growthStageIndex: 0,
      shape: shape,
      circleCenterLat:
          (shape == 'circle') ? _pendingCircleCenter?.latitude : null,
      circleCenterLng:
          (shape == 'circle') ? _pendingCircleCenter?.longitude : null,
      circleRadiusM: (shape == 'circle') ? _pendingCircleRadiusM : null,
      locked: false,
      etaManual: false, // new plot starts as auto-ETA
      irrigationEfficiency: 0.85,
      cropCalibration: 1.0,
      serverId: null, // NEW
    );

    // Set an initial auto ETA from crop (if any)
    plot.expectedHarvest = _fmt(_autoHarvestDate(plot));

    _pushHistory();
    setState(() {
      _plots.add(plot);
      _selected = plot;
      _drawing.clear();
      _anchor = null;
      _anchor2 = null;
      _pendingCircleCenter = null;
      _pendingCircleRadiusM = null;
      _scaleSlider = 1.0;
      _beginScaleBase();
      _lockNewUntilSaved = true;
    });

    await _savePlots();
    await _saveToBackend(plot);
    _updateSelectedCropIdFromPlot();
    _syncSelectedToFields();

    _showSnack(
        "Plot added. Resize first, then tap ‘Update’ below to edit details or pick a crop.");
  }

  Future<void> _undoLastUnsavedNewPlot() async {
  // Before: if (_plots.isNotEmpty && !_lockNewUntilSaved) { ... }
  if (_plots.isNotEmpty && _lockNewUntilSaved) {
    _pushHistory();
    final removed = _plots.last;
    setState(() {
      _plots.removeLast();
      _tasks.removeWhere((t) => t.plotId == removed.id);
      _selected = null;
      _selectedCropId = null;
    });
    await _cancelNotificationsForPlot(removed);
    await _savePlots();
    await _saveTasks();
    _syncSelectedToFields();
  }
}



  void _beginScaleBase() {
    if (_selected == null) return;
    final p = _selected!;
    _scaleCenter = (p.shape == 'circle' && p.circleCenter != null)
        ? p.circleCenter
        : _centroid(p.points);
    if (p.shape == 'circle' && p.circleRadiusM != null) {
      _scaleBaseRadiusM = p.circleRadiusM;
      _scaleBaseOpenPoints = _withoutClosingPoint(p.points);
    } else {
      _scaleBaseOpenPoints = _withoutClosingPoint(p.points);
      _scaleBaseRadiusM = null;
    }
  }

  void _applyScaleFromBase(double factor, {bool useFreshBase = false}) {
    if (_selected == null) return;
    final p = _selected!;
    if (p.locked) return;
    if (useFreshBase) _beginScaleBase();
    if (_scaleCenter == null || _scaleBaseOpenPoints == null) return;

    if (p.shape == 'circle' &&
        p.circleCenter != null &&
        _scaleBaseRadiusM != null) {
      final newR = (_scaleBaseRadiusM! * factor).clamp(0.0, double.infinity);
      final newPts = List.generate(48, (i) {
        final theta = (i / 48) * 360.0;
        return _dist.offset(_scaleCenter!, newR, theta);
      });
      final closed = _ensureClosed(newPts);
      setState(() {
        p
          ..circleRadiusM = newR
          ..points = closed
          ..areaM2 = math.pi * newR * newR;
      });
      return;
    }

    final scaledOpen = _scaleBaseOpenPoints!.map((pt) {
      final d = _dist.distance(_scaleCenter!, pt);
      final bearing = _dist.bearing(_scaleCenter!, pt);
      return _dist.offset(_scaleCenter!, d * factor, bearing);
    }).toList();
    final closed = _ensureClosed(scaledOpen);
    setState(() {
      p
        ..points = closed
        ..areaM2 = _areaM2(closed);
    });
  }

  List<PlotModel> _plotsForScope() {
    switch (_scaleScope) {
      case ScaleScope.selected:
        return _selected == null ? <PlotModel>[] : <PlotModel>[_selected!];
      case ScaleScope.sameCrop:
        if (_selected?.crop == null) return <PlotModel>[];
        return _plots.where((p) => p.crop == _selected!.crop).toList();
      case ScaleScope.all:
        return List<PlotModel>.from(_plots);
    }
  }

  void _beginScopeBases() {
    _scopeBaseOpen.clear();
    _scopeBaseRadius.clear();
    _scopeBaseCenter.clear();
    for (final p in _plotsForScope()) {
      final center = (p.shape == 'circle' && p.circleCenter != null)
          ? p.circleCenter!
          : _centroid(p.points);
      _scopeBaseCenter[p.id] = center;
      _scopeBaseOpen[p.id] = _withoutClosingPoint(p.points);
      _scopeBaseRadius[p.id] = (p.shape == 'circle') ? p.circleRadiusM : null;
    }
  }

  void _applyScaleToScope(double factor) {
    final targets = _plotsForScope();
    if (targets.isEmpty) return;
    setState(() {
      for (final p in targets) {
        if (p.locked) continue;
        final center = _scopeBaseCenter[p.id];
        final open = _scopeBaseOpen[p.id];
        if (center == null || open == null) continue;

        final baseR = _scopeBaseRadius[p.id];

        if (p.shape == 'circle' && p.circleCenter != null && baseR != null) {
          final newR = (baseR * factor).clamp(0.0, double.infinity);
          final newPts = List.generate(48, (i) {
            final theta = (i / 48) * 360.0;
            return _dist.offset(center, newR, theta);
          });
          p
            ..circleRadiusM = newR
            ..points = _ensureClosed(newPts)
            ..areaM2 = math.pi * newR * newR;
        } else if (p.shape == 'point') {
          p.points = _ensureClosed(<LatLng>[open.first]);
          p.areaM2 = 0;
        } else {
          final scaledOpen = open.map((pt) {
            final d = _dist.distance(center, pt);
            final bearing = _dist.bearing(center, pt);
            return _dist.offset(center, d * factor, bearing);
          }).toList();
          final closed = _ensureClosed(scaledOpen);
          p
            ..points = closed
            ..areaM2 = _areaM2(closed);
        }
      }
    });
  }

  void _resizeByFactor(double factor) {
    _pushHistory();
    _beginScopeBases();
    _applyScaleToScope(factor);
    _savePlots();
  }

  Future<void> _regenerateTasksForPlot(PlotModel p) async {
    _tasks.removeWhere((t) => t.plotId == p.id);

    final prof = _profileFor(p.crop);
    final now = DateTime.now();

    DateTime planting;
    try {
      planting = DateTime.parse(p.plantedOn);
    } catch (_) {
      planting = now;
    }

    DateTime? harvest;
    if (p.etaManual && p.expectedHarvest != null && p.expectedHarvest!.trim().isNotEmpty) {
      try {
        harvest = DateTime.parse(p.expectedHarvest!);
      } catch (_) {}
    } else {
      harvest = _autoHarvestDate(p);
    }

    final wateringEvery = (p.growthStageIndex <= 0)
        ? prof.wateringEveryDaysSeedling
        : prof.wateringEveryDaysVeg;

    _tasks.add(TaskItem(
      id: 'wtr_${p.id}_${DateTime.now().millisecondsSinceEpoch}',
      plotId: p.id,
      plotName: p.name,
      crop: p.crop,
      type: TaskType.watering,
      title: 'Water ${p.name} (${p.crop ?? "Crop"})',
      due: now,
      repeatEveryDays: wateringEvery,
    ));

    final fertDue =
        planting.add(Duration(days: prof.fertiliseAfterDaysFromPlanting));
    if (fertDue.isAfter(now.subtract(const Duration(days: 1)))) {
      _tasks.add(TaskItem(
        id: 'fer_${p.id}_${fertDue.millisecondsSinceEpoch}',
        plotId: p.id,
        plotName: p.name,
        crop: p.crop,
        type: TaskType.fertilising,
        title: 'Fertilise ${p.name}',
        due: fertDue,
      ));
    }

    _tasks.add(TaskItem(
      id: 'weed_${p.id}_${DateTime.now().millisecondsSinceEpoch}',
      plotId: p.id,
      plotName: p.name,
      crop: p.crop,
      type: TaskType.weeding,
      title: 'Weeding: ${p.name}',
      due: now.add(const Duration(days: 2)),
      repeatEveryDays: prof.weedingEveryDays,
    ));

    if (harvest != null) {
      final inspDue =
          harvest.subtract(Duration(days: prof.preHarvestInspectionDaysBefore));
      if (inspDue.isAfter(now)) {
        _tasks.add(TaskItem(
          id: 'insp_${p.id}_${inspDue.millisecondsSinceEpoch}',
          plotId: p.id,
          plotName: p.name,
          crop: p.crop,
          type: TaskType.inspection,
          title: 'Inspect ${p.name} before harvest',
          due: inspDue,
        ));
      }
      _tasks.add(TaskItem(
        id: 'harv_${p.id}_${harvest.millisecondsSinceEpoch}',
        plotId: p.id,
        plotName: p.name,
        crop: p.crop,
        type: TaskType.harvest,
        title: 'Harvest ${p.name}',
        due: harvest,
      ));
    }

    await _saveTasks();
  }

  Future<String?> _exportTasksToICS() async {
    try {
      final buf = StringBuffer()
        ..writeln('BEGIN:VCALENDAR')
        ..writeln('VERSION:2.0')
        ..writeln('PRODID:-//FarmApp//Tasks//EN');

      String fmt(DateTime d) {
        final z = d.toUtc();
        String two(int x) => x.toString().padLeft(2, '0');
        return '${z.year}${two(z.month)}${two(z.day)}T${two(z.hour)}${two(z.minute)}${two(z.second)}Z';
      }

      for (final t in _tasks) {
        buf
          ..writeln('BEGIN:VEVENT')
          ..writeln('UID:${t.id}@farmapp')
          ..writeln('DTSTAMP:${fmt(DateTime.now())}')
          ..writeln('DTSTART:${fmt(t.due)}')
          ..writeln('SUMMARY:${t.title.replaceAll('\n', ' ')}')
          ..writeln(
              'DESCRIPTION:Plot ${t.plotName}${t.crop != null ? " (${t.crop})" : ""}')
          ..writeln('END:VEVENT');
      }
      buf.writeln('END:VCALENDAR');

      final path =
          '/sdcard/Download/farm_tasks_${DateTime.now().millisecondsSinceEpoch}.ics';
      final file = File(path);
      await file.writeAsString(buf.toString());
      return file.path;
    } catch (_) {
      return null;
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- Target count fitter ----------
  Future<void> _fitTargetCountForSelected() async {
    if (_selected == null) {
      _showSnack('Tap a plot first.');
      return;
    }
    final p = _selected!;
    final target = int.tryParse(_targetCountCtrl.text.trim() == ''
        ? '0'
        : _targetCountCtrl.text.trim());
    if (target == null || target <= 0) {
      _showSnack('Enter a target plant count (e.g., 450).');
      return;
    }

    final baseRow = math.max(0.1,
        double.tryParse(_rowSpacingCtrl.text.trim()) ?? (p.rowSpacingM ?? 1.0));
    final basePlant = math.max(
        0.1,
        double.tryParse(_plantSpacingCtrl.text.trim()) ??
            (p.plantSpacingM ?? 0.5));

    int countFor(double m) {
      final pts = _generateLayoutPoints(
          p, p.layoutKind, baseRow * m, basePlant * m);
      return pts.length.clamp(0, kMaxGeneratedPlants);
    }

    double mLo = 0.2;
    double mHi = 5.0;
    int cLo = countFor(mLo);
    int cHi = countFor(mHi);

    if (target > cLo) {
      _showSnack(
          'Too many plants for this plot. Reduce target or enlarge the plot.');
      return;
    }
    int guard = 0;
    while (target < cHi && guard++ < 12) {
      mHi *= 1.8;
      cHi = countFor(mHi);
    }

    double bestM = mHi;
    int bestC = cHi;
    for (int it = 0; it < 30; it++) {
      final mid = (mLo + mHi) * 0.5;
      final c = countFor(mid);
      if ((c - target).abs() < (bestC - target).abs()) {
        bestC = c;
        bestM = mid;
      }
      if (c > target) {
        mLo = mid;
      } else {
        mHi = mid;
      }
    }

    final newRow = (baseRow * bestM).clamp(0.1, 9999.0);
    final newPlant = (basePlant * bestM).clamp(0.1, 9999.0);
    final pts =
        _generateLayoutPoints(p, p.layoutKind, newRow, newPlant).take(kMaxGeneratedPlants);

    _pushHistory();
    setState(() {
      p.rowSpacingM = newRow;
      p.plantSpacingM = newPlant;
      p.plants
        ..clear()
        ..addAll(pts);
      _rowSpacingCtrl.text = newRow.toStringAsFixed(2);
      _plantSpacingCtrl.text = newPlant.toStringAsFixed(2);
    });
    _savePlots();

    _showSnack(
        'Fitted ${p.plants.length} plants. Spacing: ${newRow.toStringAsFixed(2)} m × ${newPlant.toStringAsFixed(2)} m');
  }
  // ----------------------------------------

  @override
  Widget build(BuildContext context) {
    final polygons = <Polygon>[];
for (final p in _plots) {
  // Skip non-area shapes or malformed polygons
  final open = _withoutClosingPoint(p.points);
  if (p.shape == 'point' || open.length < 3) continue;

  final selected = _selected?.id == p.id;
  final baseColor = _colorForPlot(p);
  polygons.add(
    Polygon(
      points: p.points,
      color: baseColor.withOpacity(selected ? 0.45 : 0.28),
      borderColor: selected ? Colors.blue : baseColor,
      borderStrokeWidth: selected ? 3 : 2,
      isFilled: true,
    ),
  );
}

// Preview polygon only if it’s actually an area
if (_drawing.length >= 2) {
  final preview = _ensureClosed(_drawing);
  if (_withoutClosingPoint(preview).length >= 3) {
    polygons.add(
      Polygon(
        points: preview,
        color: Colors.red.withOpacity(0.18),
        borderColor: Colors.red,
        borderStrokeWidth: 2,
        isFilled: true,
      ),
    );
  }
}


    final List<Marker> markers = [];
    for (final p in _plots) {
      final LatLng at = p.shape == 'circle' && p.circleCenter != null
          ? p.circleCenter!
          : _centroid(p.points);
      final int pct = (p.progress() * 100).clamp(0, 100).round();
      markers.add(
        Marker(
          point: at,
          width: 54,
          height: 30,
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(blurRadius: 4, color: Colors.black26)
              ],
            ),
            child: Text(
              '$pct%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );

      final int total = p.plants.length;
      final int drawCount = math.min(total, kMaxPlantMarkers);
      if (drawCount > 0) {
        final double step = total / drawCount;
        final Color dot = _dotColorForPlot(p);
        for (int j = 0; j < drawCount; j++) {
          final int idx = (j * step).floor().clamp(0, total - 1);
          final plant = p.plants[idx];
          markers.add(
            Marker(
              point: plant,
              width: 10,
              height: 10,
              alignment: Alignment.center,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
            ),
          );
        }
      }
    }

    final mapCore = FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _initialCenter,
        initialZoom: 16.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.drag |
              InteractiveFlag.flingAnimation |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.scrollWheelZoom |
              InteractiveFlag.rotate,
        ),
        onTap: (_, pt) => _onTap(pt),
        onLongPress: (_, __) => _onLongPress(__),
        onPositionChanged: (_, __) {
          _weatherDebounce?.cancel();
          _weatherDebounce = Timer(const Duration(milliseconds: 600), () {
            if (_showWeather) _fetchWeatherFor(_map.camera.center);
          });
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.farmapp',
        ),
        PolygonLayer(polygons: polygons),
        MarkerLayer(markers: markers),
        if (_selected != null &&
            _selected!.shape != 'circle' &&
            !_selected!.locked)
          DragMarkers(
            markers: [
              ..._withoutClosingPoint(_selected!.points)
                  .asMap()
                  .entries
                  .map((e) {
                final i = e.key;
                final pt = e.value;
                return DragMarker(
                  point: pt,
                  size: const Size(22, 22),
                  offset: const Offset(-11, -11),
                  builder: (context, latLng, isDragging) => Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (_selected!.shape == 'square' ||
                                _selected!.shape == 'rectangle' ||
                                _selected!.shape == 'triangle')
                            ? Colors.blue
                            : Colors.red,
                        width: 2,
                      ),
                    ),
                  ),
                  onDragUpdate: (details, newPt) {
                    if (_selected!.locked) return;
                    _pushHistory();
                    setState(() {
                      if (_selected!.shape == 'square') {
                        _updateSquareVertex(i, newPt);
                      } else if (_selected!.shape == 'rectangle') {
                        final open = _withoutClosingPoint(_selected!.points);
                        if (open.length == 4) {
                          final oppIndex = (i + 2) % 4;
                          final anchor = open[oppIndex];
                          final rect = _rectOpen(anchor, newPt);
                          _selected!.points = _ensureClosed(rect);
                          _selected!.areaM2 = _areaM2(_selected!.points);
                        }
                      } else if (_selected!.shape == 'triangle') {
                        final open = _withoutClosingPoint(_selected!.points);
                        if (open.length == 3) {
                          final updated = List<LatLng>.from(open);
                          updated[i] = newPt;
                          _selected!.points = _ensureClosed(updated);
                          _selected!.areaM2 = _areaM2(_selected!.points);
                        }
                      }
                    });
                    _savePlots();
                    _syncSelectedToFields();
                  },
                );
              }).toList(),
              DragMarker(
                point: _centroid(_selected!.points),
                size: const Size(22, 22),
                offset: const Offset(-11, -11),
                builder: (context, latLng, isDragging) => Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                  child:
                      const Icon(Icons.open_with, size: 14, color: Colors.blue),
                ),
                onDragUpdate: (details, newCenter) {
                  if (_selected!.locked) return;
                  _pushHistory();
                  setState(() {
                    final oldCenter = _centroid(_selected!.points);
                    final d = _dist.distance(oldCenter, newCenter);
                    final b = _dist.bearing(oldCenter, newCenter);
                    final open = _withoutClosingPoint(_selected!.points);
                    final moved =
                        open.map((pt) => _dist.offset(pt, d, b)).toList();
                    _selected!.points = _ensureClosed(moved);
                  });
                  _savePlots();
                  _syncSelectedToFields();
                },
              ),
            ],
          ),
        if (_selected != null &&
            _selected!.shape == 'circle' &&
            _selected!.circleCenter != null &&
            !_selected!.locked)
          DragMarkers(
            markers: [
              DragMarker(
                point: _dist.offset(
                  _selected!.circleCenter!,
                  _selected!.circleRadiusM ?? 20,
                  0,
                ),
                size: const Size(22, 22),
                offset: const Offset(-11, -11),
                builder: (context, latLng, isDragging) => Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                ),
                onDragUpdate: (details, newPt) {
                  if (_selected!.locked) return;
                  _pushHistory();
                  setState(() {
                    final r =
                        _dist.distance(_selected!.circleCenter!, newPt);
                    _selected!
                      ..circleRadiusM = r
                      ..points = _circleRing(_selected!.circleCenter!, r);
                    _selected!.areaM2 = math.pi * r * r;
                  });
                  _savePlots();
                  _syncSelectedToFields();
                },
              ),
              DragMarker(
                point: _selected!.circleCenter!,
                size: const Size(22, 22),
                offset: const Offset(-11, -11),
                builder: (context, latLng, isDragging) => Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                  child:
                      const Icon(Icons.open_with, size: 14, color: Colors.blue),
                ),
                onDragUpdate: (details, newCenter) {
                  if (_selected!.locked) return;
                  _pushHistory();
                  setState(() {
                    _selected!
                      ..circleCenterLat = newCenter.latitude
                      ..circleCenterLng = newCenter.longitude
                      ..points = _circleRing(
                        newCenter,
                        _selected!.circleRadiusM ?? 0,
                      );
                  });
                  _savePlots();
                  _syncSelectedToFields();
                },
              ),
            ],
          ),
      ],
    );

    final mapWidget =
        (_resizeMode && _selected != null && !_selected!.locked)
            ? GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: (_) {
                  _scaleActive = false;
                },
                onScaleUpdate: (d) {
                  if (_selected == null || _selected!.locked) return;
                  if (!_scaleActive && (d.scale - 1.0).abs() > 0.01) {
                    _scaleActive = true;
                    _beginScaleBase();
                  }
                  if (_scaleActive) {
                    final factor = d.scale.clamp(0.2, 5.0);
                    _applyScaleFromBase(factor);
                  }
                },
                onScaleEnd: (_) {
                  if (_scaleActive) {
                    _scaleActive = false;
                    _savePlots();
                    _beginScaleBase();
                    _syncSelectedToFields();
                  }
                },
                child: mapCore,
              )
            : mapCore;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title:
            const Text('Mapping', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Export tasks to calendar (.ics)',
            icon: const Icon(Icons.event_available),
            onPressed: () async {
              final path = await _exportTasksToICS();
              if (path != null) {
                _showSnack('ICS saved: $path');
              } else {
                _showSnack('Could not export calendar.');
              }
            },
          ),
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
            onPressed: _history.isEmpty
                ? null
                : () async {
                    if (_history.isEmpty) return;
                    final snap = _history.removeLast();
                    _future.add(
                        jsonEncode(_plots.map((p) => p.toJson()).toList()));
                    _restoreFromJson(snap);
                    await _savePlots();
                    _syncSelectedToFields();
                  },
          ),
          IconButton(
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
            onPressed: _future.isEmpty
                ? null
                : () async {
                    if (_future.isEmpty) return;
                    final snap = _future.removeLast();
                    _history.add(
                        jsonEncode(_plots.map((p) => p.toJson()).toList()));
                    _restoreFromJson(snap);
                    await _savePlots();
                    _syncSelectedToFields();
                  },
          ),
          IconButton(
            tooltip: 'Lock & Save (all)',
            icon: const Icon(Icons.save),
            onPressed: () async {
              _pushHistory();
              setState(() {
                for (final p in _plots) {
                  p.locked = true;
                }
                _lockNewUntilSaved = false;
              });
              await _savePlots();
              for (final p in _plots) {
                await _saveToBackend(p);}
              _showSnack('Plots saved & synced');
            },
          ),
          IconButton(
            tooltip: 'Undo (last unsaved new plot)',
            icon: const Icon(Icons.history_toggle_off),
            onPressed: _plots.isEmpty || _lockNewUntilSaved == false
                ? null
                : _undoLastUnsavedNewPlot,
          ),
          IconButton(
            tooltip: 'Delete selected',
            icon: const Icon(Icons.delete),
            onPressed: _selected == null ? null : _confirmAndDeleteSelected,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          mapWidget,
          Positioned(
            right: 12,
            bottom: 92,
            child: Column(
              children: [
                _MapFab(
                  icon: Icons.add,
                  onTap: () => _map.move(
                    _map.camera.center,
                    (_map.camera.zoom + 1).clamp(1, 20),
                  ),
                ),
                const SizedBox(height: 8),
                _MapFab(
                  icon: Icons.remove,
                  onTap: () => _map.move(
                    _map.camera.center,
                    (_map.camera.zoom - 1).clamp(1, 20),
                  ),
                ),
                const SizedBox(height: 16),
                _MapFab(
                    icon: Icons.zoom_in_map,
                    onTap: () => _resizeByFactor(1.1)),
                const SizedBox(height: 8),
                _MapFab(
                    icon: Icons.zoom_out_map,
                    onTap: () => _resizeByFactor(0.9)),
              ],
            ),
          ),
          Positioned(
            left: 12,
            bottom: 92,
            child: _MapFab(
              icon: Icons.wb_sunny_outlined,
              onTap: () {
                setState(() => _showWeather = !_showWeather);
                if (_showWeather) _fetchWeatherFor(_map.camera.center);
              },
            ),
          ),
          if (_showWeather && _weatherText != null)
            Positioned(
              left: 12,
              bottom: 150,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(blurRadius: 8, color: Colors.black12)
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_queue, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _weatherText!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          LayoutBuilder(
            builder: (ctx, constraints) {
              const w = 56.0;
              final defaultLeft = 12.0;
              final defaultTop = 90.0;
              final left = (_tbLeft < 0) ? defaultLeft : _tbLeft;
              final top = (_tbTop < 0) ? defaultTop : _tbTop;
              final estH = 56.0 + 7 * 40.0;

              return Positioned(
                left: left,
                top: top,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    final curL = (_tbLeft < 0) ? defaultLeft : _tbLeft;
                    final curT = (_tbTop < 0) ? defaultTop : _tbTop;
                    setState(() {
                      _tbLeft = (curL + d.delta.dx)
                          .clamp(0.0, constraints.maxWidth - w);
                      _tbTop = (curT + d.delta.dy)
                          .clamp(0.0, constraints.maxHeight - estH);
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
                    width: w,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(blurRadius: 8, color: Colors.black12)
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _toolButton(Icons.open_with, DrawTool.pan),
                        const SizedBox(height: 6),
                        _toolButton(Icons.place, DrawTool.point),
                        const SizedBox(height: 6),
                        _toolButton(Icons.crop_16_9, DrawTool.rectangle),
                        const SizedBox(height: 6),
                        _toolButton(
                            Icons.check_box_outline_blank, DrawTool.square),
                        const SizedBox(height: 6),
                        _toolButton(Icons.circle_outlined, DrawTool.circle),
                        const SizedBox(height: 6),
                        _toolButton(Icons.change_history, DrawTool.triangle),
                        const Divider(height: 18, indent: 10, endIndent: 10),
                        IconButton(
                          tooltip: 'Finish shape',
                          onPressed: _drawing.isNotEmpty ? _finishDrawing : null,
                          icon: const Icon(Icons.check),
                          color:
                              _drawing.isNotEmpty ? Colors.green[700] : Colors.black26,
                        ),
                        IconButton(
                          tooltip: _resizeMode || _selected?.locked == true
                              ? 'Exit Resize Mode'
                              : 'Resize Mode (pinch)',
                          icon: Icon(_resizeMode
                              ? Icons.back_hand
                              : Icons.back_hand_outlined),
                          color: _resizeMode ? Colors.green[700] : Colors.black87,
                          onPressed: () {
                            if (_selected?.locked == true) {
                              _showSnack('Plot is locked');
                              return;
                            }
                            setState(() => _resizeMode = !_resizeMode);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.20,
            minChildSize: 0.12,
            maxChildSize: 0.88,
            snap: true,
            snapSizes: const [0.20, 0.55, 0.88],
            builder: (context, scrollController) =>
                _buildMyCropsSheet(scrollController),
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

  Widget _buildMyCropsSheet(ScrollController sc) {
    final progress = _selected?.progress() ?? 0;

    // NEW: if a plot is selected, compute water for today
    double? liters;
    double? mmPerM2;
    if (_selected != null) {
      final stage = _selected!.growthStageIndex;
      final prof = _profileFor(_selected!.crop);
      mmPerM2 = prof.waterForStageMmPerDay(stage) *
          ((_currentTempC == null)
              ? 1.0
              : (1.0 + 0.03 * (_currentTempC! - 20.0)).clamp(0.5, 1.5)) *
          _selected!.cropCalibration;
      liters = _litersPerDayForPlot(
        p: _selected!,
        stageIndex: stage,
        airTempC: _currentTempC,
      );
    }

    return Material(
      color: Colors.white,
      elevation: 10,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Text('My Crops',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (_selected != null)
                    TextButton.icon(
                      onPressed: _editSelectedDetails,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit…'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  itemCount: _crops.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    if (i == 0) {
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
                                    BoxShadow(
                                        blurRadius: 6,
                                        color: Colors.black12,
                                        offset: Offset(0, 2))
                                  ],
                                ),
                                child: const Icon(Icons.add, size: 28),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const SizedBox(
                              width: 64,
                              child: Text('Add',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12)),
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
                      onTap: () async {
                        setState(() {
                          _selectedCropId = crop.id;
                          if (_selected != null) {
                            _selected!.crop = crop.name;
                            if (!_selected!.etaManual) {
                              _selected!.expectedHarvest =
                                  _fmt(_autoHarvestDate(_selected!));
                            }
                          }
                        });
                        if (_selected != null) {
                          await _savePlots();
                          await _regenerateTasksForPlot(_selected!);
                          await _saveToBackend(_selected!);
                          _syncSelectedToFields();
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    readOnly: true,
                    controller: _selNameCtrl,
                    decoration: _inp('Name'),
                    onTap: _editSelectedDetails,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    readOnly: true,
                    controller: _selAreaCtrl,
                    decoration: _inp('Area'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                readOnly: true,
                controller: _selPlantingDateCtrl,
                decoration: _inp('Planting Date')
                    .copyWith(suffixIcon: const Icon(Icons.calendar_today)),
                onTap: _editSelectedDetails,
              ),
              const SizedBox(height: 10),
              if (_selected != null) ...[
                Row(children: [
                  Expanded(
                    child: Text(
                      'Growth: ${_selected!.growthLabel}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _editSelectedDetails,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Update'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _saveSelectedWithValidation,
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ]),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        progress >= 1 ? Colors.green : Colors.lightGreen),
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Text(
                      (_selected!.etaManual && (_selected!.expectedHarvest ?? '').isNotEmpty)
                          ? 'Harvest: ${_selected!.expectedHarvest} (manual)'
                          : 'Harvest: ${_fmt(_autoHarvestDate(_selected!))} (auto)',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    _selected!.targetYieldKg == null
                        ? 'Goal: —'
                        : 'Goal: ${_selected!.targetYieldKg!.toStringAsFixed(0)} kg',
                    style: const TextStyle(fontSize: 12),
                  ),
                ]),
                const SizedBox(height: 6),
                // Day tracker
                Builder(
                  builder: (_) {
                    final info = _daysInfo(_selected!);
                    return Row(
                      children: [
                        const Icon(Icons.hourglass_bottom, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${info.daysLeft} days left (Day ${info.dayNumber} of ${info.totalDays}) – ETA ${_fmt(info.eta)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                // NEW: Water today
                if (liters != null && mmPerM2 != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.water_drop_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Water today ~ ${liters.toStringAsFixed(0)} L '
                          '(${mmPerM2!.toStringAsFixed(1)} L/m²/day · eff ${( (_selected!.irrigationEfficiency * 100).round() )}%)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),

                // ---- Scope size controls (kept) ----
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.group_work_outlined, size: 18),
                        const SizedBox(width: 8),
                        const Text('Apply to'),
                        const SizedBox(width: 10),
                        DropdownButton<ScaleScope>(
                          value: _scaleScope,
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _scaleScope = v);
                            _scaleSlider = 1.0;
                          },
                          items: const [
                            DropdownMenuItem(
                                value: ScaleScope.selected,
                                child: Text('Selected')),
                            DropdownMenuItem(
                                value: ScaleScope.sameCrop,
                                child: Text('Same crop')),
                            DropdownMenuItem(
                                value: ScaleScope.all,
                                child: Text('All plots')),
                          ],
                        ),
                        const Spacer(),
                        Text('Size: ${(100 * _scaleSlider).round()}%'),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setState(() => _scaleSlider = 1.0);
                            _beginScopeBases();
                            _applyScaleToScope(1.0);
                            _savePlots();
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                    Slider(
                      value: _scaleSlider,
                      min: 0.5,
                      max: 2.0,
                      divisions: 30,
                      label: '${(100 * _scaleSlider).round()}%',
                      onChangeStart: (_) => _beginScopeBases(),
                      onChanged: (v) {
                        setState(() => _scaleSlider = v);
                        _applyScaleToScope(v);
                      },
                      onChangeEnd: (_) {
                        _savePlots();
                        _beginScopeBases();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const Text('Layout',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(children: [
                  const Text('Type:'),
                  const SizedBox(width: 10),
                  DropdownButton<LayoutKind>(
                    value: _selected!.layoutKind,
                    items: const [
                      DropdownMenuItem(
                          value: LayoutKind.rows, child: Text('Rows')),
                      DropdownMenuItem(
                          value: LayoutKind.grid, child: Text('Grid')),
                      DropdownMenuItem(
                          value: LayoutKind.triangular,
                          child: Text('Triangular')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selected!.layoutKind = v);
                      _savePlots();
                    },
                  ),
                  const Spacer(),
                  Text('Plants: ${_selected!.plants.length}'),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _targetCountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inp('Target plant count (optional)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _fitTargetCountForSelected,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[700],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Fit count'),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _rowSpacingCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inp('Row spacing (m)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _plantSpacingCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inp('Plant spacing (m)'),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                if (_selected!.rowSpacingM != null &&
                    _selected!.plantSpacingM != null)
                  Text(
                    'Spacing: ${_selected!.rowSpacingM!.toStringAsFixed(2)} m × ${_selected!.plantSpacingM!.toStringAsFixed(2)} m',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.grid_on, size: 16),
                      label: const Text('Generate Layout'),
                      onPressed: () {
                        final p = _selected!;
                        final rowS =
                            double.tryParse(_rowSpacingCtrl.text.trim()) ?? 1.0;
                        final plantS =
                            double.tryParse(_plantSpacingCtrl.text.trim()) ??
                                0.5;

                        if (rowS <= 0 || plantS <= 0) {
                          _showSnack('Spacing must be > 0');
                          return;
                        }
                        if (rowS < 0.1 || plantS < 0.1) {
                          _showSnack('Spacing too small. Use ≥ 0.1 m');
                          return;
                        }

                        final pts = _generateLayoutPoints(
                            p, p.layoutKind, rowS, plantS);
                        _pushHistory();
                        setState(() {
                          p.rowSpacingM = rowS;
                          p.plantSpacingM = plantS;
                          p.plants
                            ..clear()
                            ..addAll(pts.take(kMaxGeneratedPlants));
                          final per = _perPlantYieldGuessKg(p.crop);
                          if (per > 0) {
                            p.targetYieldKg = per * p.plants.length;
                          }
                        });
                        _savePlots();
                        _showSnack(
                            'Layout generated: ${p.plants.length} plants (capped).');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () {
                        if (_selected == null) return;
                        _pushHistory();
                        setState(() => _selected!.plants.clear());
                        _savePlots();
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editSelectedDetails() async {
    if (_selected == null) return;

    final name = TextEditingController(text: _selected!.name);
    final spacing = TextEditingController();
    final date = TextEditingController(text: _selected!.plantedOn);

    int stageIndex = _selected!.growthStageIndex;
    final targetYield = TextEditingController(
      text: _selected!.targetYieldKg == null
          ? ''
          : _selected!.targetYieldKg!.toStringAsFixed(0),
    );
    final expectedHarvest =
        TextEditingController(text: _selected!.etaManual ? (_selected!.expectedHarvest ?? '') : '');

    // NEW: water controls
    final effCtrl =
        TextEditingController(text: (_selected!.irrigationEfficiency * 100).round().toString());
    final calCtrl =
        TextEditingController(text: _selected!.cropCalibration.toStringAsFixed(2));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Plot Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(decoration: _inp('Name'), controller: name),
            const SizedBox(height: 10),
            TextField(decoration: _inp('Notes / Spacing'), controller: spacing),
            const SizedBox(height: 10),
            TextField(
              readOnly: true,
              controller: date,
              decoration: _inp('Planting Date')
                  .copyWith(suffixIcon: const Icon(Icons.calendar_today)),
              onTap: () async {
                FocusScope.of(context).unfocus();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(date.text) ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  date.text = _fmt(picked);
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
                      value: i, child: Text(kGrowthStages[i]))),
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
              readOnly: false,
              controller: expectedHarvest,
              decoration: _inp('Expected Harvest (leave blank for auto)')
                  .copyWith(suffixIcon: const Icon(Icons.event)),
              onTap: () async {
                FocusScope.of(context).unfocus();
                final base = DateTime.tryParse(date.text) ?? DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(expectedHarvest.text) ??
                      base.add(const Duration(days: 60)),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  expectedHarvest.text = _fmt(picked);
                }
              },
            ),
            const SizedBox(height: 10),
            // NEW: water tuning inputs
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: effCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inp('Irrigation efficiency (%)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: calCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _inp('Crop calibration (×)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () async {
                FocusScope.of(ctx).unfocus();

                if (_selected == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text('No plot selected. Tap a plot first.')),
                  );
                  return;
                }

                final candidateName =
                    name.text.trim().isEmpty ? _selected!.name : name.text.trim();
                if (candidateName.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text('Please enter a name for the plot.')),
                  );
                  return;
                }
                if (_isNameTaken(candidateName, exceptId: _selected!.id)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'That plot name already exists. Use a unique name.')),
                  );
                  return;
                }

                double? targetYieldVal;
                if (targetYield.text.trim().isNotEmpty) {
                  final parsed = double.tryParse(targetYield.text.trim());
                  if (parsed == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                          content: Text('Target Yield must be a number.')),
                    );
                    return;
                  }
                  targetYieldVal = parsed;
                }

                // manual/auto ETA logic
                final harvestText = expectedHarvest.text.trim();
                final isManualEta = harvestText.isNotEmpty;

                // parse water tuning
                final effPct = int.tryParse(effCtrl.text.trim());
                final eff = ((effPct ?? 85) / 100).clamp(0.5, 0.99);
                final cal = double.tryParse(calCtrl.text.trim()) ?? 1.0;

                _pushHistory();
                setState(() {
                  _selected!
                    ..name = candidateName
                    ..plantedOn = date.text.trim()
                    ..growthStageIndex = stageIndex
                    ..targetYieldKg = targetYieldVal
                    ..etaManual = isManualEta
                    ..expectedHarvest = isManualEta ? harvestText : null
                    ..irrigationEfficiency = eff
                    ..cropCalibration = cal;

                  if (!_selected!.etaManual) {
                    _selected!.expectedHarvest = _fmt(_autoHarvestDate(_selected!));
                  }
                });

                await _savePlots();
                await _regenerateTasksForPlot(_selected!);
                _syncSelectedToFields();

                if (mounted) Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Plot details saved.')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Text('Save'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _updateSquareVertex(int draggedIndex, LatLng newCorner) {
    if (_selected == null) return;
    final p = _selected!;
    if (p.shape != 'square' || p.locked) return;

    final open = _withoutClosingPoint(p.points);
    if (open.length != 4) return;

    final oppIndex = (draggedIndex + 2) % 4;
    final anchor = open[oppIndex];

    final sq = _squareOpen(anchor, newCorner);

    int bestK = 0;
    double bestD = double.infinity;
    for (int k = 0; k < 4; k++) {
      final d = _dist.distance(sq[k], newCorner);
      if (d < bestD) {
        bestD = d;
        bestK = k;
      }
    }
    final rotated =
        List<LatLng>.generate(4, (i) => sq[(bestK - draggedIndex + i) & 3]);

    p.points = _ensureClosed(rotated);
    p.areaM2 = _areaM2(p.points);
  }

  Widget _toolButton(IconData icon, DrawTool t) {
    final isSel = _tool == t;
    return Material(
      color: isSel ? Colors.green[50] : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          if (_lockNewUntilSaved &&
              (t == DrawTool.rectangle ||
                  t == DrawTool.square ||
                  t == DrawTool.circle ||
                  t == DrawTool.point ||
                  t == DrawTool.triangle)) {
            _showSnack('Save or delete the current plot first.');
            return;
          }
          setState(() {
            _tool = t;
            _drawing.clear();
            _anchor = null;
            _anchor2 = null;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon,
              size: 22, color: isSel ? Colors.green[700] : Colors.black87),
        ),
      ),
    );
  }
}

void nullSafe() {}

class _MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapFab({required this.icon, required this.onTap, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child:
            SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white)),
      ),
    );
  }
}

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
                boxShadow: const [
                  BoxShadow(
                      blurRadius: 6, color: Colors.black12, offset: Offset(0, 2))
                ],
                border: Border.all(
                  color: selected ? Colors.green : Colors.transparent,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: isAsset
                  ? Image.asset(
                      imagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.image_not_supported),
                    )
                  : Image.file(
                      File(imagePath),
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: tileSide,
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
