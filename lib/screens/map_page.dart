import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

import 'home_page.dart';
import 'mapping.dart';
import 'task_page.dart';
import 'add_task.dart';
import 'settings_page.dart';
import 'notifications_page.dart';
import 'cropdata.dart';
import 'calender_page.dart';
import 'weather_page.dart';

enum DrawTool { point, rectangle, circle, pan }

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  DrawTool _activeTool = DrawTool.point;

  final List<Polygon> _plots = [];
  final List<LatLng> _currentPoints = [];

  void _onMapTap(LatLng point) {
    switch (_activeTool) {
      case DrawTool.point:
        _addPoint(point);
        break;
      case DrawTool.rectangle:
        _createRectangle(point);
        break;
      case DrawTool.circle:
        _createCircle(point);
        break;
      case DrawTool.pan:
        break;
    }
  }

  void _addPoint(LatLng point) {
    setState(() {
      _currentPoints.add(point);
      if (_currentPoints.length == 4) {
        _finishPlot();
      }
    });
  }

  void _createRectangle(LatLng center) {
    const offset = 0.001;
    final rect = [
      LatLng(center.latitude + offset, center.longitude - offset),
      LatLng(center.latitude + offset, center.longitude + offset),
      LatLng(center.latitude - offset, center.longitude + offset),
      LatLng(center.latitude - offset, center.longitude - offset),
    ];
    setState(() {
      _plots.add(_makePoly(rect));
    });
  }

  void _createCircle(LatLng center) {
    const radiusMeters = 100.0;
    const segments = 32;
    final dist = Distance();
    final pts = List<LatLng>.generate(segments, (i) {
      final theta = (i / segments) * 2 * math.pi;
      return dist.offset(center, radiusMeters, theta * 180 / math.pi);
    });
    setState(() {
      _plots.add(_makePoly(pts));
    });
  }

  void _finishPlot() {
    _plots.add(_makePoly(List.of(_currentPoints)));
    _currentPoints.clear();
  }

  Polygon _makePoly(List<LatLng> pts) {
    final label = 'Plot ${_plots.length + 1}';
    return Polygon(
      points: pts,
      borderColor: Colors.green,
      borderStrokeWidth: 2,
      color: Colors.green.withOpacity(0.4),
      label: label,
    );
  }

  void _clearPlots() {
    setState(() {
      _plots.clear();
      _currentPoints.clear();
    });
  }

  void _showAddDetailsOverlay() {
    final nameCtrl = TextEditingController();
    final spacingCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add Details',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                hintText: 'Name',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: spacingCtrl,
              decoration: InputDecoration(
                hintText: 'Spacing',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: dateCtrl,
              readOnly: true,
              decoration: InputDecoration(
                hintText: 'Planting Date',
                suffixIcon: Icon(Icons.calendar_today),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onTap: () async {
                FocusScope.of(context).unfocus();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                }
              },
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Save', style: TextStyle(fontSize: 16)),
            ),
            SizedBox(height: 16),
          ],
        ),
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

  Widget _toolButton(DrawTool tool, IconData icon) {
    final isSelected = _activeTool == tool;
    return IconButton(
      icon: Icon(icon, color: isSelected ? Colors.green : Colors.black54),
      onPressed: () => setState(() => _activeTool = tool),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(padding: EdgeInsets.zero, children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Colors.green[700]),
            child: SizedBox.shrink(),
          ),
          _drawerItem('Dashboard', '/'),
          _drawerItem('Layout Planning', '/map'),
          _drawerItem('Mapping', '/mapping'),
          _drawerItem('Task Manager', '/tasks'),
          _drawerItem('Add Task', '/add'),
          _drawerItem('Settings', '/settings'),
          _drawerItem('Notifications', '/notifications'),
          _drawerItem('Crop Database', '/cropdata'),
          _drawerItem('Calendar', '/calendar'),
          _drawerItem('Weather', '/weather'),
        ]),
      ),
      backgroundColor: const Color(0xFFF7F8F9),
      body: SafeArea(
        child: Column(
          children: [
            // Custom AppBar row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      icon: Icon(Icons.menu, size: 28, color: Colors.black),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  Spacer(),
                  Text('Layout Planning',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  IconButton(
                      icon: Icon(Icons.add), onPressed: _showAddDetailsOverlay),
                  SizedBox(width: 12),
                  CircleAvatar(
                    backgroundColor: Colors.grey[300],
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Map area
            Expanded(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  center: LatLng(-27.4698, 153.0251),
                  zoom: 16.0,
                  onTap: (_, latlng) => _onMapTap(latlng),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.farmapp',
                  ),
                  PolygonLayer(polygons: _plots),
                ],
              ),
            ),

            // Tool and crop controls
            Container(
              color: Colors.grey[100],
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Tools',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _toolButton(DrawTool.point, Icons.add_location_alt),
                      _toolButton(DrawTool.rectangle, Icons.crop_square),
                      _toolButton(DrawTool.circle, Icons.circle_outlined),
                      _toolButton(DrawTool.pan, Icons.open_with),
                      IconButton(
                          icon: Icon(Icons.clear, color: Colors.red),
                          onPressed: _clearPlots),
                    ],
                  ),
                  SizedBox(height: 24),
                  Text('My Crops',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        'orange',
                        'wheat',
                        'leafy',
                        'tree',
                        'lettuce',
                      ].map((crop) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child:
                              Image.asset('assets/crops/$crop.png', height: 40),
                        );
                      }).toList(),
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Spacing',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Planting Date',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        onTap: (i) {
          switch (i) {
            case 0:
              Navigator.pushNamed(context, '/');
              break;
            case 1:
              break;
            case 2:
              Navigator.pushNamed(context, '/mapping');
              break;
            case 3:
              Navigator.pushNamed(context, '/tasks');
              break;
            case 4:
              Navigator.pushNamed(context, '/calendar');
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: ''),
        ],
      ),
    );
  }
}
