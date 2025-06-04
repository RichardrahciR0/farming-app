import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.green[700]),
              child: Center(
                child: Image.asset('assets/logo.png', height: 60),
              ),
            ),
            _drawerItem(context, "Edit Dashboard", "/"),
            _drawerItem(context, "Account Settings", "/settings"),
            _drawerItem(context, "Layout Planning", "/map"),
            _drawerItem(context, "Task Manager", "/tasks"),
            _drawerItem(context, "Mapping", "/mapping"),
            _drawerItem(context, "Data Visualized", "/data"),
            _drawerItem(context, "Weather", "/weather"),
            _drawerItem(context, "Calendar", "/calendar"),
            _drawerItem(context, "Crop Database", "/cropdata"),
          ],
        ),
      ),
      backgroundColor: Color(0xFFF7F8F9),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(160),
        child: SafeArea(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        icon: Icon(Icons.menu, size: 32),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                    SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.notifications_none, size: 28),
                      onPressed: () {
                        Navigator.pushNamed(context, '/notifications');
                      },
                    ),
                  ],
                ),
                Image.asset(
                  'assets/logo.png',
                  height: 160,
                  width: 160,
                  fit: BoxFit.contain,
                ),

                /// ✅ Updated profile icon to go to /settings
                IconButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/settings');
                  },
                  icon: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey[300],
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                "Dashboard",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2E4E3F),
                ),
              ),
            ),
            SizedBox(height: 24),
            Text("My Plot",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/map'),
              child: Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  image: DecorationImage(
                    image: AssetImage('assets/plot_map.jpg'),
                    fit: BoxFit.cover,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    )
                  ],
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    color: Colors.black.withOpacity(0.4),
                    child: Text(
                      "Tap to view your plots",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 24),
            Text("Crop Growth",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            SizedBox(height: 12),
            _placeholderRounded(
                height: 180, label: "Crop Growth: Add your details"),
            SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                    child: _placeholderRounded(
                        height: 100,
                        label: "Overall Growth: Add your details")),
                SizedBox(width: 16),
                Expanded(
                    child: _placeholderRounded(
                        height: 100,
                        label: "Yield Projection: Add your details")),
              ],
            ),
            SizedBox(height: 24),
            Text("Pending Tasks",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/tasks'),
              child: Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    )
                  ],
                ),
                child: Center(
                  child: Text(
                    "Pending Tasks: Tap to manage",
                    style: TextStyle(
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[700],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
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

  Widget _drawerItem(BuildContext context, String title, String route) {
    return ListTile(
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        if (route != '/') Navigator.pushNamed(context, route);
      },
    );
  }

  Widget _placeholderRounded({required double height, String? label}) {
    return Container(
      height: height,
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Center(
        child: Text(
          label ?? '',
          style: TextStyle(
            fontSize: 16,
            fontStyle: FontStyle.italic,
            color: Colors.grey[700],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
