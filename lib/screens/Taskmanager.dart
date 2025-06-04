import 'package:flutter/material.dart';

class TaskManagerToday extends StatelessWidget {
  final List<Map<String, String>> tasks = [
    {'title': 'Check Crop progression', 'status': 'In Progress'},
    {'title': 'Prune Apple Trees Before Rain', 'status': 'Completed'},
    {'title': 'Update Garden Map with New Beds', 'status': 'Not started'},
  ];

  final Map<String, Color> statusColors = {
    'In Progress': Colors.amber,
    'Completed': Colors.green,
    'Not started': Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Manager'),
        actions: const [
          Icon(Icons.notifications_none),
          SizedBox(width: 10),
          Icon(Icons.account_circle),
          SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          _buildDateSelector(),
          ToggleButtons(
            borderRadius: BorderRadius.circular(10),
            isSelected: [true, false],
            children: const [Text('Today'), Text('Upcoming')],
            onPressed: (_) {},
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                var task = tasks[index];
                return Card(
                  margin: const EdgeInsets.all(10),
                  child: ListTile(
                    title: Text(task['title']!),
                    subtitle: const Text("10:00 – 12:30 am"),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColors[task['status']]!.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        task['status']!,
                        style: TextStyle(
                          color: statusColors[task['status']],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(0),
    );
  }

  Widget _buildDateSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children:
          ['Thu 26', 'Fri 27', 'Sat 28', 'Sun 29', 'Mon 30', 'Tue 31', 'Wed 01']
              .map((date) => Column(
                    children: [
                      Text(date),
                      if (date.contains("Mon 30"))
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 30,
                          height: 4,
                          color: Colors.green,
                        ),
                    ],
                  ))
              .toList(),
    );
  }

  Widget _buildBottomNavBar(int selectedIndex) {
    return BottomNavigationBar(
      currentIndex: selectedIndex,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
        BottomNavigationBarItem(icon: Icon(Icons.map), label: ''),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: ''),
        BottomNavigationBarItem(icon: Icon(Icons.task_alt), label: ''),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: ''),
      ],
    );
  }
}

class TaskManagerUpcoming extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Manager'),
        actions: const [
          Icon(Icons.notifications_none),
          SizedBox(width: 10),
          Icon(Icons.account_circle),
          SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          ToggleButtons(
            borderRadius: BorderRadius.circular(10),
            isSelected: [false, true],
            children: const [Text('Today'), Text('Upcoming')],
            onPressed: (_) {},
          ),
          Expanded(
            child: ListView(
              children: upcomingTasks.entries.map((entry) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      color: Colors.green.shade800,
                      padding: const EdgeInsets.all(8),
                      child: Text(entry.key,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                    ...entry.value.map((task) => Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          child: ListTile(
                            title: Text(task['title']!),
                            subtitle: Text(task['time']!),
                          ),
                        )),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(3),
    );
  }

  Widget _buildBottomNavBar(int selectedIndex) {
    return BottomNavigationBar(
      currentIndex: selectedIndex,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
        BottomNavigationBarItem(icon: Icon(Icons.map), label: ''),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: ''),
        BottomNavigationBarItem(icon: Icon(Icons.task_alt), label: ''),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: ''),
      ],
    );
  }
}
