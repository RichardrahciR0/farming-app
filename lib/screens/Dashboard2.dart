import 'package:flutter/material.dart';
// adjust the path

void main() => runApp(const OreFoxApp());

class OreFoxApp extends StatelessWidget {
  const OreFoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OreFox Dashboard',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const DashboardPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Icon(Icons.menu, color: Colors.black),
        actions: [
          Icon(Icons.notifications_none, color: Colors.black),
          const SizedBox(width: 16),
          CircleAvatar(backgroundColor: Colors.grey[300]),
          const SizedBox(width: 16),
        ],
        centerTitle: true,
        title: Image.asset(
          'assets/logo.png',
          height: 40,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Dashboard',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 20),

            // My Plot section
            const Text("My Plot",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset("assets/plot_map.png", height: 180),
            ),

            const SizedBox(height: 20),

            // Crop Growth section
            const Text("Crop Growth",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset("assets/crop_chart.png", height: 200),
            ),

            const SizedBox(height: 20),

            // Growth Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatCard(
                    "Overall Growth", "8.2", "20%", "This Week(11–18 Jan)"),
                _buildStatCard(
                    "Yield Projection", "7.3", "30%", "Last Week(3–10 Jan)"),
              ],
            ),

            const SizedBox(height: 20),

            // Pending Tasks
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("Pending Tasks",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: Colors.deepPurple),
                      SizedBox(width: 10),
                      Text("Check crop progression"),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: Colors.deepPurple),
                      SizedBox(width: 10),
                      Text("Update garden with new beds"),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.black54,
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

  Widget _buildStatCard(
      String title, String value, String percent, String period) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$title  ↑ $percent",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 5),
            Text(value,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text(period,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
