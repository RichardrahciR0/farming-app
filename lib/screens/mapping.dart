// lib/screens/mapping.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

// ⬇️ Your existing API service
import '../services/plot_service.dart';

/// Tools shown in the floating palette
enum DrawTool { vertex, addMarker, pan, undo }

/// In-memory model for a user plot you draw locally (optional)
class PlotMeta {
  PlotMeta({
    required this.polygon,
    this.name,
    this.spacing,
    this.plantingDate,
  });

  final Polygon polygon;
  String? name;
  String? spacing;
  DateTime? plantingDate;
}

/// Record fetched from the backend (keeps the whole payload in [props])
class ServerPlot {
  final int id;
  final String type; // 'point' | 'polygon' | 'rectangle' | 'circle' | 'multipolygon'
  final Map<String, dynamic> geometry; // GeoJSON
  final Map<String, dynamic> props; // full record (minus geometry ideally)
  final String name;
  final String growthStage;
  final DateTime? plantedAt;

  ServerPlot({
    required this.id,
    required this.type,
    required this.geometry,
    required this.props,
    required this.name,
    required this.growthStage,
    required this.plantedAt,
  });

  static ServerPlot fromJson(Map<String, dynamic> j) {
    // Keep the original for the details sheet
    final mapCopy = Map<String, dynamic>.from(j);

    return ServerPlot(
      id: (j['id'] as num).toInt(),
      type: (j['type'] ?? 'polygon').toString(),
      geometry: Map<String, dynamic>.from(j['geometry'] as Map),
      props: mapCopy,
      name: (j['name'] ?? 'Plot').toString(),
      growthStage: (j['growth_stage'] ?? '').toString(),
      plantedAt: j['planted_at'] != null && (j['planted_at'] as String).isNotEmpty
          ? DateTime.tryParse('${j['planted_at']}T00:00:00')
          : null,
    );
  }
}

class MappingPage extends StatefulWidget {
  const MappingPage({super.key});

  @override
  State<MappingPage> createState() => _MappingPageState();
}

class _MappingPageState extends State<MappingPage> {
  final MapController _map = MapController();

  // ── Local/demo state (optional)
  final List<PlotMeta> _localPlots = <PlotMeta>[];
  final List<LatLng> _workingVertices = <LatLng>[];

  // ── Server data
  final List<ServerPlot> _serverPlots = <ServerPlot>[];
  final List<Polygon> _serverPolygons = <Polygon>[];
  final List<Marker> _serverMarkers = <Marker>[];
  final List<Marker> _serverPolyTapMarkers = <Marker>[]; // invisible centroids

  bool _loading = false;
  String? _error;

  // demo alerts (you can later fetch from API)
  final List<Marker> _alerts = <Marker>[
    Marker(
      point: LatLng(-27.4692, 153.0238),
      width: 36,
      height: 36,
      child: const Icon(Icons.warning, color: Colors.red, size: 32),
    ),
  ];

  // ── UI state
  DrawTool _tool = DrawTool.vertex;
  // layer toggles: Plots | Grid | Heatmap | Alerts
  final List<bool> _layers = [true, false, false, false];

  int _bottomIndex = 1; // home, map, tasks, settings, calendar

  @override
  void initState() {
    super.initState();
    _loadServerPlots();
  }

  // ---------- GeoJSON helpers ----------
  List<LatLng> _parseLinearRing(dynamic ringAny) {
    // Accepts List<[lng,lat]>, drops duplicate closing point if present
    final pts = <LatLng>[];
    if (ringAny is! List) return pts;
    for (final xy in ringAny) {
      if (xy is List && xy.length >= 2) {
        final lng = (xy[0] as num).toDouble();
        final lat = (xy[1] as num).toDouble();
        pts.add(LatLng(lat, lng));
      }
    }
    if (pts.length >= 2) {
      final a = pts.first, b = pts.last;
      if (a.latitude == b.latitude && a.longitude == b.longitude) {
        pts.removeLast(); // open ring for flutter_map
      }
    }
    return pts;
  }

  List<List<LatLng>> _parsePolygonCoords(dynamic polyAny) {
    // GeoJSON Polygon.coordinates: [ [ring0], [hole1], ... ]
    // We render outer ring only for now.
    final out = <List<LatLng>>[];
    if (polyAny is! List || polyAny.isEmpty) return out;
    final ringAny = polyAny.first; // outer ring
    final ring = _parseLinearRing(ringAny);
    if (ring.length >= 3) out.add(ring);
    return out;
  }
  // -------------------------------------

  Future<void> _loadServerPlots() async {
    setState(() {
      _loading = true;
      _error = null;
      _serverPlots.clear();
      _serverPolygons.clear();
      _serverMarkers.clear();
      _serverPolyTapMarkers.clear();
    });

    try {
      final list = await PlotService().fetchMyPlots();
      final parsed = list.map(ServerPlot.fromJson).toList();

      final polygons = <Polygon>[];
      final markers = <Marker>[];
      final polyTapMarkers = <Marker>[];

      for (final sp in parsed) {
        final gjType = (sp.geometry['type'] ?? '').toString();

        if (gjType == 'Polygon') {
          final coordsAny = sp.geometry['coordinates'];
          final rings = _parsePolygonCoords(coordsAny);
          for (final ring in rings) {
            final points = ring;
            final unique = points.toSet().toList();
            if (unique.length >= 3) {
              polygons.add(
                Polygon(
                  points: points,
                  color: Colors.green.withOpacity(0.30),
                  borderColor: Colors.green.shade700,
                  borderStrokeWidth: 2,
                  label:
                      '${sp.name}${sp.growthStage.isNotEmpty ? ' • ${sp.growthStage}' : ''}',
                ),
              );

              final c = _centroid(points);
              polyTapMarkers.add(
                Marker(
                  point: c,
                  width: 44,
                  height: 44,
                  child: InkWell(
                    onTap: () => _showServerPlotDetails(sp, c),
                    child: const Icon(
                      Icons.crop_square,
                      color: Colors.transparent, // invisible tap target
                      size: 40,
                    ),
                  ),
                ),
              );
            }
          }
        } else if (gjType == 'MultiPolygon') {
          // iterate each polygon’s outer ring
          final multiAny = sp.geometry['coordinates'];
          if (multiAny is List) {
            for (final polyAny in multiAny) {
              final rings = _parsePolygonCoords(polyAny);
              for (final ring in rings) {
                if (ring.length >= 3) {
                  polygons.add(
                    Polygon(
                      points: ring,
                      color: Colors.green.withOpacity(0.30),
                      borderColor: Colors.green.shade700,
                      borderStrokeWidth: 2,
                      label:
                          '${sp.name}${sp.growthStage.isNotEmpty ? ' • ${sp.growthStage}' : ''}',
                    ),
                  );
                  final c = _centroid(ring);
                  polyTapMarkers.add(
                    Marker(
                      point: c,
                      width: 44,
                      height: 44,
                      child: InkWell(
                        onTap: () => _showServerPlotDetails(sp, c),
                        child: const Icon(Icons.crop_square,
                            color: Colors.transparent, size: 40),
                      ),
                    ),
                  );
                }
              }
            }
          }
        } else if (gjType == 'Point') {
          final coords = sp.geometry['coordinates'];
          if (coords is List && coords.length >= 2) {
            final lng = (coords[0] as num).toDouble();
            final lat = (coords[1] as num).toDouble();
            final c = LatLng(lat, lng);
            markers.add(
              Marker(
                point: c,
                width: 40,
                height: 40,
                child: InkWell(
                  onTap: () => _showServerPlotDetails(sp, c),
                  child: Tooltip(
                    message:
                        '${sp.name}${sp.growthStage.isNotEmpty ? ' • ${sp.growthStage}' : ''}\n(Tap for details)',
                    preferBelow: false,
                    child: const Icon(Icons.place, color: Colors.green, size: 32),
                  ),
                ),
              ),
            );
          }
        } else {
          // Circles/rectangles typically stored as Polygon in GeoJSON.
          // If your backend returns 'Circle' with center+radius, approximate on server.
        }
      }

      setState(() {
        _serverPlots.addAll(parsed);
        _serverPolygons.addAll(polygons);
        _serverMarkers.addAll(markers);
        _serverPolyTapMarkers.addAll(polyTapMarkers);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load plots: $e';
      });
    }
  }

  // ── Map interactions (local sketch)
  void _onMapTap(LatLng latlng) {
    if (_tool != DrawTool.vertex) return;

    setState(() {
      _workingVertices.add(latlng);
      if (_workingVertices.length == 4) {
        final polygon = Polygon(
          points: List<LatLng>.from(_workingVertices),
          borderColor: Colors.blueGrey,
          borderStrokeWidth: 2,
          color: Colors.blueGrey.withOpacity(0.30),
        );
        _localPlots.add(PlotMeta(polygon: polygon));
        _workingVertices.clear();
        _openPlotDetails(_localPlots.last);
      }
    });
  }

  void _undo() {
    if (_workingVertices.isNotEmpty) {
      setState(() => _workingVertices.removeLast());
      return;
    }
    if (_localPlots.isNotEmpty) {
      setState(() => _localPlots.removeLast());
    }
  }

  // ── Layers
  void _toggleLayer(int idx) {
    setState(() {
      for (int i = 0; i < _layers.length; i++) {
        _layers[i] = i == idx;
      }
    });
  }

  // ── Local add/edit (sketch)
  Future<void> _openPlotDetails(PlotMeta plot) async {
    final nameCtrl = TextEditingController(text: plot.name ?? '');
    final spacingCtrl = TextEditingController(text: plot.spacing ?? '');
    final dateCtrl = TextEditingController(
      text: plot.plantingDate != null
          ? DateFormat('yyyy-MM-dd').format(plot.plantingDate!)
          : '',
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: spacingCtrl,
                decoration: const InputDecoration(
                  labelText: 'Spacing',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: dateCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Planting Date',
                  suffixIcon: Icon(Icons.calendar_today),
                  border: OutlineInputBorder(),
                ),
                onTap: () async {
                  FocusScope.of(context).unfocus();
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: plot.plantingDate ?? now,
                    firstDate: DateTime(now.year - 5),
                    lastDate: DateTime(now.year + 5),
                  );
                  if (picked != null) {
                    dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                  }
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    setState(() {
                      plot.name = nameCtrl.text.trim().isEmpty
                          ? null
                          : nameCtrl.text.trim();
                      plot.spacing = spacingCtrl.text.trim().isNotEmpty
                          ? spacingCtrl.text.trim()
                          : null;
                      if (dateCtrl.text.trim().isNotEmpty) {
                        plot.plantingDate =
                            DateTime.tryParse('${dateCtrl.text}T00:00:00');
                      } else {
                        plot.plantingDate = null;
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Server plot detail sheet (shows *everything* from Layout Planning)
  Future<void> _showServerPlotDetails(ServerPlot sp, LatLng center) async {
    final fmt = DateFormat('yyyy-MM-dd');
    // Build display pairs from props, excluding geometry & internal keys
    final excluded = {'geometry'};
    final entries = <MapEntry<String, String>>[];

    sp.props.forEach((k, v) {
      if (excluded.contains(k)) return;

      if (v == null) return;
      String valStr;
      if (k == 'planted_at' && v is String && v.isNotEmpty) {
        final dt = DateTime.tryParse('${v}T00:00:00');
        valStr = dt != null ? fmt.format(dt) : v.toString();
      } else if (v is List) {
        valStr = v.map((e) => e.toString()).join(', ');
      } else if (v is Map) {
        valStr = v.map((kk, vv) => MapEntry(kk, vv?.toString() ?? '')).toString();
      } else {
        valStr = v.toString();
      }

      // Beautify label (snake_case → Title Case)
      final label = k
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');

      entries.add(MapEntry(label, valStr));
    });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    sp.type.toLowerCase().contains('point')
                        ? Icons.place
                        : Icons.terrain,
                    color: Colors.green[700],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sp.name.isEmpty ? 'Plot #${sp.id}' : sp.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (sp.growthStage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Text(
                        sp.growthStage,
                        style: TextStyle(
                          color: Colors.green[900],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (sp.plantedAt != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Planted: ${fmt.format(sp.plantedAt!)}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              const SizedBox(height: 8),

              // Key/Value list of *all* properties (from Layout Planning)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        e.key,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        e.value.isEmpty ? '—' : e.value,
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),

              // CTA: jump to Layout Planning (MapPage) to edit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit in Layout Planning'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    // IMPORTANT:
                    // 1) Pass plotId as STRING to match PlotModel.id in MapPage
                    // 2) Pass center fallback so MapPage can pan/zoom even if IDs don't match
                    await Navigator.pushNamed(context, '/map', arguments: {
                      'plotId': sp.id.toString(),
                      'center': {'lat': center.latitude, 'lng': center.longitude},
                    });
                    // when user returns from Layout Planning, refresh server plots
                    if (mounted) _loadServerPlots();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── UI bits
  Widget _toolFab(DrawTool tool, IconData icon) {
    final selected = _tool == tool;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selected ? Colors.green : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black54),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: IconButton(
        icon: Icon(icon, color: selected ? Colors.white : Colors.black),
        onPressed: () {
          if (tool == DrawTool.undo) {
            _undo();
          } else {
            setState(() => _tool = tool);
          }
        },
      ),
    );
  }

  List<Polygon> get _localPolygons =>
      _localPlots.map((p) => p.polygon).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(padding: EdgeInsets.zero, children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Colors.green[700]),
            child: const SizedBox.shrink(),
          ),
          _drawerItem('Dashboard', '/'),
          _drawerItem('Layout Planning', '/map'),
          _drawerItem('Mapping', '/mapping'),
          _drawerItem('Task Manager', '/tasks'),
          _drawerItem('Settings', '/settings'),
          _drawerItem('Crop Database', '/cropdata'),
          _drawerItem('Calendar', '/calendar'),
          _drawerItem('Weather', '/weather'),
        ]),
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: const Text('Mapping', style: TextStyle(color: Colors.black)),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.black),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh server plots',
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: _loadServerPlots,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black),
            onPressed: () {
              if (_localPlots.isEmpty) return;
              _openPlotDetails(_localPlots.last);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: const LatLng(-27.4698, 153.0251), // Brisbane
              initialZoom: 16,
              onTap: (_, latlng) => _onMapTap(latlng),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.lim.farmapp',
              ),

              // --- SERVER LAYERS ---
              if (_layers[0] && _serverPolygons.isNotEmpty)
                PolygonLayer(polygons: _serverPolygons),
              if (_layers[0] && _serverMarkers.isNotEmpty)
                MarkerLayer(markers: _serverMarkers),
              if (_layers[0] && _serverPolyTapMarkers.isNotEmpty)
                MarkerLayer(markers: _serverPolyTapMarkers),

              // --- LOCAL SKETCH LAYERS (optional) ---
              if (_layers[0] && _localPolygons.isNotEmpty)
                PolygonLayer(polygons: _localPolygons),
              if (_layers[3]) MarkerLayer(markers: _alerts),
            ],
          ),

          if (_loading)
            const Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),

          if (_error != null)
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Material(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade800),
                  ),
                ),
              ),
            ),

          if (_layers[1])
            Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          if (_layers[2])
            Positioned.fill(
              child: IgnorePointer(
                child: Container(color: Colors.red.withOpacity(0.20)),
              ),
            ),
          Positioned(
            right: 12,
            top: 110,
            child: Column(
              children: [
                _toolFab(DrawTool.vertex, Icons.edit),
                _toolFab(DrawTool.addMarker, Icons.add_location_alt),
                _toolFab(DrawTool.pan, Icons.open_with),
                _toolFab(DrawTool.undo, Icons.undo),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 84,
            child: Center(
              child: ToggleButtons(
                isSelected: _layers,
                onPressed: _toggleLayer,
                borderRadius: BorderRadius.circular(12),
                selectedColor: Colors.white,
                color: Colors.black,
                fillColor: Colors.green,
                children: const [
                  _Pill(text: 'Plots'),
                  _Pill(text: 'Grid'),
                  _Pill(text: 'Heatmap'),
                  _Pill(text: 'Alerts'),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        onTap: (i) {
          setState(() => _bottomIndex = i);
          switch (i) {
            case 0:
              Navigator.pushNamed(context, '/');
              break;
            case 1:
              break;
            case 2:
              Navigator.pushNamed(context, '/tasks');
              break;
            case 3:
              Navigator.pushNamed(context, '/settings');
              break;
            case 4:
              Navigator.pushNamed(context, '/calendar');
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: ''),
        ],
      ),
    );
  }

  Widget _drawerItem(String title, String route) {
    return ListTile(
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        Navigator.pushNamed(context, route);
      },
    );
  }

  // --- Geometry helpers ---
  LatLng _centroid(List<LatLng> points) {
    // Polygon centroid (simple average fallback for degenerate cases)
    double signedArea = 0;
    double cx = 0;
    double cy = 0;

    for (int i = 0; i < points.length; i++) {
      final p0 = points[i];
      final p1 = points[(i + 1) % points.length];
      final a = (p0.longitude * p1.latitude) - (p1.longitude * p0.latitude);
      signedArea += a;
      cx += (p0.longitude + p1.longitude) * a;
      cy += (p0.latitude + p1.latitude) * a;
    }
    if (signedArea.abs() < 1e-9) {
      // fallback
      final avgLat =
          points.fold<double>(0, (s, p) => s + p.latitude) / points.length;
      final avgLng =
          points.fold<double>(0, (s, p) => s + p.longitude) / points.length;
      return LatLng(avgLat, avgLng);
    }
    signedArea *= 0.5;
    cx /= (6.0 * signedArea);
    cy /= (6.0 * signedArea);
    return LatLng(cy, cx);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
