import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'add_task.dart';

class TaskPage extends StatefulWidget {
  @override
  _TaskPageState createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  // --- DATA ---
  List<Map<String, dynamic>> tasksToday = [
    {
      'title': 'Check Crop progression',
      'time': '10:00 – 12:30 am',
      'status': 'In Progress',
      'checked': false,
      'description':
          'Review the crop progress dashboard to assess real-time updates on crop health and growth stages.',
    },
    {
      'title': 'Prune Apple Trees Before Rain',
      'time': '10:00 – 12:30 am',
      'status': 'Completed',
      'checked': false,
      'description':
          'Trim the branches of the apple trees to ensure proper growth and avoid weather damage.',
    },
    {
      'title': 'Update Garden Map with New Beds',
      'time': '10:00 – 12:30 am',
      'status': 'Not started',
      'checked': false,
      'description':
          'Add newly prepared garden beds to the garden layout in the system map.',
    },
  ];

  final Map<String, List<Map<String, String>>> upcomingTasks = {
    'Wed 1st May': [
      {
        'title': 'Irrigation Setup for New Crop Area',
        'time': '12:00 – 13:30 pm'
      },
      {
        'title': 'Apply Fertilizer to Orchard Zone B',
        'time': '09:00 – 11:00 am'
      },
      {'title': 'Harvest Tomatoes', 'time': '12:00 – 13:30 pm'},
    ],
    'Fri 3rd May': [
      {'title': 'Course UI Design', 'time': '15:00 – 16:00 pm'},
      {'title': 'Log Planting Dates for New Herbs', 'time': '16:00 – 17:00 pm'},
    ],
  };

  // --- STATE ---
  bool showToday = true;
  int selectedDayIndex = DateTime.now().weekday - 1; // Mon=0…Sun=6
  final weekDates = List.generate(
      7, (i) => DateTime.now().add(Duration(days: i))); // next 7 days

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ── SIDE MENU ──────────────────────────────────────────────────────────
      drawer: Drawer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 100, color: Colors.green),
            _drawerItem(context, 'Dashboard', '/'),
            _drawerItem(context, 'Layout Planning', '/map'),
            _drawerItem(context, 'Mapping', '/mapping'),
            _drawerItem(context, 'Task Manager', '/tasks'),
            _drawerItem(context, 'Settings', '/settings'),
            _drawerItem(context, 'Notifications', '/notifications'),
            _drawerItem(context, 'Crop Database', '/cropdata'),
            _drawerItem(context, 'Calendar', '/calendar'),
          ],
        ),
      ),

      // ── APP BAR ───────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: Text('Task Manager', style: TextStyle(color: Colors.black)),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu, color: Colors.black),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: Colors.black),
            onPressed: () async {
              final newTask = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddTaskPage(),
                  ));
              if (newTask != null) {
                setState(() => tasksToday.add(newTask));
              }
            },
          ),
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, color: Colors.white)),
          ),
        ],
      ),

      backgroundColor: Color(0xFFF7F8F9),
      body: Column(
        children: [
          _buildDateSelector(),
          SizedBox(height: 8),
          _buildSegmentToggle(),
          Expanded(
              child: showToday ? _buildTodayTasks() : _buildUpcomingTasks()),
        ],
      ),

      // ── BOTTOM NAV ─────────────────────────────────────────────────────────
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Color(0xFFF7F8F9),
        elevation: 0,
        currentIndex: 2,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        onTap: (i) {
          switch (i) {
            case 0:
              Navigator.pushNamed(context, '/');
              break;
            case 1:
              Navigator.pushNamed(context, '/map');
              break;
            case 2:
              break; // here
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

  // ── DATE SELECTOR ────────────────────────────────────────────────────────
  Widget _buildDateSelector() {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12),
        itemCount: weekDates.length,
        itemBuilder: (_, i) {
          final d = weekDates[i];
          final selected = i == selectedDayIndex;
          return GestureDetector(
            onTap: () => setState(() => selectedDayIndex = i),
            child: Container(
              width: 60,
              margin: EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: selected ? Colors.green[700] : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat.E().format(d),
                      style: TextStyle(
                          color: selected ? Colors.white : Colors.black)),
                  Text(DateFormat.d().format(d),
                      style: TextStyle(
                          color: selected ? Colors.white : Colors.black)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── TODAY / UPCOMING PILL TOGGLE ─────────────────────────────────────────
  Widget _buildSegmentToggle() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => showToday = true),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: showToday ? Colors.green : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Today',
                    style: TextStyle(
                        color: showToday ? Colors.white : Colors.black)),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => showToday = false),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: !showToday ? Colors.green : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Upcoming',
                    style: TextStyle(
                        color: !showToday ? Colors.white : Colors.black)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── TODAY TASKS LIST ─────────────────────────────────────────────────────
  Widget _buildTodayTasks() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: tasksToday.length,
      itemBuilder: (_, idx) {
        final t = tasksToday[idx];
        return GestureDetector(
          onTap: () => _showTaskDetails(t),
          child: Container(
            margin: EdgeInsets.only(bottom: 16),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: t['checked'] ? Colors.green[50] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Row(
              children: [
                // Title + Time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['title'],
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              decoration: t['checked']
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              color:
                                  t['checked'] ? Colors.grey : Colors.black)),
                      SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.access_time, size: 16),
                        SizedBox(width: 4),
                        Text(t['time']),
                      ]),
                    ],
                  ),
                ),

                // Checkbox
                Checkbox(
                    value: t['checked'],
                    onChanged: (_) =>
                        setState(() => t['checked'] = !t['checked'])),

                // Status badge
                GestureDetector(
                  onTap: () => _showStatusDialog(idx),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(t['status']),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(t['status'],
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── UPCOMING TASKS LIST ──────────────────────────────────────────────────
  Widget _buildUpcomingTasks() {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: upcomingTasks.entries.expand((entry) {
        return [
          // Date header
          Container(
            width: double.infinity,
            color: Colors.green,
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Text(entry.key,
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          SizedBox(height: 8),

          // Tasks under that date
          ...entry.value.map((t) {
            return Container(
              margin: EdgeInsets.only(bottom: 16),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['title']!,
                        style: TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 16)),
                    SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.access_time, size: 16),
                      SizedBox(width: 4),
                      Text(t['time']!, style: TextStyle(fontSize: 14)),
                    ]),
                  ]),
            );
          }).toList(),
        ];
      }).toList(),
    );
  }

  // ── DETAILS OVERLAY ───────────────────────────────────────────────────────
  void _showTaskDetails(Map<String, dynamic> task) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(task['title'],
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black)),
            SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(task['time'], style: TextStyle(color: Colors.grey[700])),
              Text("Due in: 1 hr",
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ]),
            Divider(height: 24),
            Align(
                alignment: Alignment.centerLeft,
                child: Text("Description",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            SizedBox(height: 8),
            Text(task['description'],
                style: TextStyle(fontSize: 16, color: Colors.black87)),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 40),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              child: Text("Done",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            )
          ]),
        ),
      ),
    );
  }

  // ── STATUS CHANGE DIALOG ────────────────────────────────────────────────
  void _showStatusDialog(int idx) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[200],
        title: Text('Change To:', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var status in ['Not started', 'In Progress', 'Completed'])
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: ElevatedButton(
                onPressed: () {
                  setState(() => tasksToday[idx]['status'] = status);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _statusColor(status),
                  shape: StadiumBorder(),
                ),
                child: Text(status),
              ),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text('Cancel')),
        ]),
      ),
    );
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────
  Color _statusColor(String status) {
    switch (status) {
      case 'In Progress':
        return Colors.amber;
      case 'Completed':
        return Colors.green;
      case 'Not started':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  Widget _drawerItem(BuildContext c, String title, String route) {
    return ListTile(
      title: Text(title),
      onTap: () {
        Navigator.pop(c);
        Navigator.pushNamed(c, route);
      },
    );
  }
}
