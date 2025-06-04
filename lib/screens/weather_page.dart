// lib/screens/weather_page.dart

import 'package:flutter/material.dart';
import 'home_page.dart';
import 'map_page.dart';
import 'mapping.dart';
import 'task_page.dart';
import 'add_task.dart';
import 'settings_page.dart';
import 'notifications_page.dart';
import 'cropdata.dart';
import 'calender_page.dart';

class WeatherPage extends StatefulWidget {
  @override
  _WeatherPageState createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  int _currentIndex = 4; // Calendar is index 4 in nav

  final List<Map<String, dynamic>> hourly = [
    {'temp': '22°C', 'icon': Icons.wb_sunny_outlined, 'time': '13.00'},
    {'temp': '29°C', 'icon': Icons.wb_sunny_outlined, 'time': '14.00'},
    {'temp': '26°C', 'icon': Icons.wb_sunny_outlined, 'time': '15.00'},
    {'temp': '24°C', 'icon': Icons.cloud_outlined, 'time': '17.00'},
    {'temp': '23°C', 'icon': Icons.nights_stay, 'time': '18.00'},
    {'temp': '22°C', 'icon': Icons.nights_stay, 'time': '19.00'},
  ];

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
      // Side‐drawer with blank green header
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.green[700]),
              child: SizedBox.shrink(),
            ),
            _drawerItem(context, 'Dashboard', '/'),
            _drawerItem(context, 'Layout Planning', '/map'),
            _drawerItem(context, 'Mapping', '/mapping'),
            _drawerItem(context, 'Task Manager', '/tasks'),
            _drawerItem(context, 'Add Task', '/add'),
            _drawerItem(context, 'Settings', '/settings'),
            _drawerItem(context, 'Notifications', '/notifications'),
            _drawerItem(context, 'Crop Database', '/cropdata'),
            _drawerItem(context, 'Calendar', '/calendar'),
            _drawerItem(context, 'Weather', '/weather'),
          ],
        ),
      ),

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: Text('Weather', style: TextStyle(color: Colors.black)),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu, color: Colors.black),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_outlined, color: Colors.black),
            onPressed: () => Navigator.pushNamed(context, '/notifications'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(backgroundColor: Colors.grey[300]),
          ),
        ],
      ),

      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Today',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ),
          SizedBox(height: 16),
          Center(
            child:
                Icon(Icons.cloud_outlined, size: 100, color: Colors.blue[100]),
          ),
          SizedBox(height: 8),
          Center(
            child: Text('24°C',
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
          ),
          SizedBox(height: 4),
          Center(
            child: Text('Partly Cloudy',
                style: TextStyle(fontSize: 16, color: Colors.blueGrey)),
          ),
          SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Text('Planting Suggestions',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: Icon(Icons.smart_toy_outlined),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text('Apply Suggestion'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 16),
          Container(
            height: 120,
            color: Colors.green[600],
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: hourly.length,
              itemBuilder: (_, i) {
                final h = hourly[i];
                final selected = i == 3;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(h['temp'],
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Icon(h['icon'], color: Colors.white),
                      SizedBox(height: 8),
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: selected
                            ? BoxDecoration(
                                border: Border.all(color: Colors.white70),
                                borderRadius: BorderRadius.circular(8),
                              )
                            : null,
                        child: Text(h['time'],
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        currentIndex: _currentIndex,
        selectedItemColor: Colors.green[700],
        unselectedItemColor: Colors.grey,
        onTap: (i) {
          setState(() => _currentIndex = i);
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
            case 5:
              Navigator.pushNamed(context, '/weather');
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.cloud_outlined), label: ''),
        ],
      ),
    );
  }
}
