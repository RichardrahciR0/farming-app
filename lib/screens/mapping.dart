import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MappingPage extends StatefulWidget {
  @override
  _MappingPageState createState() => _MappingPageState();
}

class _MappingPageState extends State<MappingPage> {
  final MapController _mapController = MapController();
  final List<Polygon> _plots = [];
  final List<LatLng> _currentPoints = [];

  List<bool> _layers = [true, false, false, false];
  int _activeTool = 2;
  int _navIndex = 1;

  void _addPoint(LatLng pt) {
    if (_activeTool != 0) return;
    setState(() {
      _currentPoints.add(pt);
      if (_currentPoints.length == 4) {
        _plots.add(
          Polygon(
            points: List.from(_currentPoints),
            borderColor: Colors.green,
            borderStrokeWidth: 2,
            color: Colors.green.withOpacity(0.4),
          ),
        );
        _currentPoints.clear();
      }
    });
  }

  void _undo() {
    if (_currentPoints.isNotEmpty) {
      setState(() => _currentPoints.removeLast());
    }
  }

  void _toggleLayer(int idx) {
    setState(() {
      for (int i = 0; i < _layers.length; i++) {
        _layers[i] = i == idx;
      }
    });
  }

  void _selectTool(int idx) {
    setState(() => _activeTool = idx);
  }

  void _showAddDetailsOverlay() {
    final nameCtrl = TextEditingController();
    final spacingCtrl = TextEditingController();
    final dateCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          top: 24,
          left: 24,
          right: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                hintText: 'Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: spacingCtrl,
              decoration: InputDecoration(
                hintText: 'Spacing',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: dateCtrl,
              readOnly: true,
              decoration: InputDecoration(
                hintText: 'Planting Date',
                suffixIcon: Icon(Icons.calendar_today),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                  dateCtrl.text = picked.toLocal().toIso8601String().split('T').first;
                }
              },
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Save', style: TextStyle(fontSize: 16)),
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(BuildContext context, String title, String route) {
    return ListTile(
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        Navigator.pushNamed(context, route);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.green[700]),
              child: Center(child: Image.asset('assets/logo.png', height: 60)),
            ),
            _drawerItem(context, 'Dashboard', '/'),
            _drawerItem(context, 'Account Settings', '/settings'),
            _drawerItem(context, 'Layout Planning', '/map'),
            _drawerItem(context, 'Task Manager', '/tasks'),
            _drawerItem(context, 'Mapping', '/mapping'),
            _drawerItem(context, 'Data Visualized', '/data'),
            _drawerItem(context, 'Weather', '/weather'),
            _drawerItem(context, 'Calendar', '/calendar'),
            _drawerItem(context, 'Crop Database', '/cropdata'),
          ],
        ),
      ),
      appBar: AppBar(
        title: Text('Mapping', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu, color: Colors.black),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: Colors.black),
            onPressed: _showAddDetailsOverlay,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: LatLng(-27.4698, 153.0251),
              zoom: 16.0,
              onTap: (_, latlng) => _addPoint(latlng),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.farmapp',
              ),
              if (_layers[0]) PolygonLayer(polygons: _plots),
            ],
          ),
          if (_layers[1]) Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          if (_layers[2]) Positioned.fill(child: Container(color: Colors.red.withOpacity(0.2))),
          if (_layers[3])
            Positioned.fill(
              child: Center(
                child: Icon(Icons.warning, size: 100, color: Colors.red.withOpacity(0.6)),
              ),
            ),
          Positioned(
            right: 12,
            top: 100,
            child: Column(
              children: [
                _toolButton(Icons.edit, 0),
                SizedBox(height: 12),
                _toolButton(Icons.add_location_alt, 1),
                SizedBox(height: 12),
                _toolButton(Icons.open_with, 2),
                SizedBox(height: 12),
                _toolButton(Icons.undo, 3),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 80,
            child: Center(
              child: ToggleButtons(
                isSelected: _layers,
                onPressed: _toggleLayer,
                borderRadius: BorderRadius.circular(8),
                selectedColor: Colors.white,
                fillColor: Colors.green,
                color: Colors.black,
                selectedBorderColor: Colors.black,
                borderColor: Colors.grey,
                borderWidth: 1.5,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(
                      'Plots',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _layers[0] ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(
                      'Grid',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _layers[1] ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(
                      'Heatmap',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _layers[2] ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(
                      'Alerts',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _layers[3] ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _navIndex,
        onTap: (i) {
          setState(() => _navIndex = i);
          switch (i) {
            case 0:
              Navigator.pushNamed(context, '/');
              break;
            case 1:
              Navigator.pushNamed(context, '/map');
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
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: ''),
        ],
      ),
    );
  }

  Widget _toolButton(IconData icon, int idx) {
    final selected = _activeTool == idx;
    return Container(
      decoration: BoxDecoration(
        color: selected ? Colors.green : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black54),
      ),
      child: IconButton(
        icon: Icon(icon, color: selected ? Colors.white : Colors.black),
        onPressed: () => idx == 3 ? _undo() : _selectTool(idx),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
