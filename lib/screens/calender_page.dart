import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CalendarPage extends StatefulWidget {
  @override
  _CalendarPageState createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final PageController _pageController =
      PageController(initialPage: DateTime.now().month - 1);
  int _currentPage = DateTime.now().month - 1;
  final int year = 2025; // fixed to 2025 as requested

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // --- your existing drawer ---
      drawer: Drawer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 100, color: Colors.green),
            _drawerItem(context, 'Dashboard', '/'),
            _drawerItem(context, 'Account Settings', '/settings'),
            _drawerItem(context, 'Layout Planning', '/map'),
            _drawerItem(context, 'Mapping', '/mapping'),
            _drawerItem(context, 'Task Manager', '/tasks'),
            _drawerItem(context, 'Mapping', '/map'),
            _drawerItem(context, 'Data Visualized', '/data'),
            _drawerItem(context, 'Weather', '/weather'),
            _drawerItem(context, 'Calendar', '/calendar'),
            _drawerItem(context, 'Crop Database', '/cropdata'),
          ],
        ),
      ),

      // --- app bar with menu, bell, avatar ----
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu, color: Colors.black),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text('My Calendar', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_outlined, color: Colors.black),
            onPressed: () {},
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              backgroundColor: Colors.grey,
              child: Icon(Icons.person, color: Colors.white),
            ),
          ),
        ],
      ),

      backgroundColor: const Color(0xFFF7F8F9),
      body: Column(
        children: [
          // --- swipeable months ---
          SizedBox(
            height: 320,
            child: PageView.builder(
              controller: _pageController,
              itemCount: 12,
              onPageChanged: (idx) => setState(() => _currentPage = idx),
              itemBuilder: (ctx, idx) {
                final monthDate = DateTime(year, idx + 1);
                return _buildMonthView(monthDate);
              },
            ),
          ),

          const SizedBox(height: 16),

          // --- Task Manager button ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/tasks'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'Task Manager',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // --- Placeholder task list ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Task List',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Text(
                'Your tasks go here…',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ),
        ],
      ),

      // --- bottom navigation ---
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 4, // calendar
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        onTap: (_) {}, // handle as needed
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

  /// Renders a single month as a neat 7-column table of dates.
  Widget _buildMonthView(DateTime monthDate) {
    // Weekday headers
    final weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

    // How many blank slots before 1st
    final firstWeekday = DateTime(monthDate.year, monthDate.month, 1).weekday;
    final blanks = firstWeekday - 1; // Monday=1 → 0 blanks

    // Days in month
    final daysInMonth =
        DateUtils.getDaysInMonth(monthDate.year, monthDate.month);

    // Build list of all cells (blanks then day numbers)
    final cells = <Widget>[
      for (var i = 0; i < blanks; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++) _monthDayCell(monthDate, d),
    ];

    // Pad trailing blanks so total %7==0
    while (cells.length % 7 != 0) cells.add(const SizedBox.shrink());

    // Chunk into rows of 7
    final rows = <TableRow>[];
    // header
    rows.add(TableRow(
      children: weekdays
          .map((d) => Center(
                child: Text(d,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey[700])),
              ))
          .toList(),
    ));
    // date rows
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(TableRow(
        children: cells.sublist(i, i + 7),
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Month + year
          Text(
            DateFormat.yMMMM().format(monthDate),
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black),
          ),
          const SizedBox(height: 12),
          Table(
            defaultColumnWidth: FlexColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: rows,
          ),
        ],
      ),
    );
  }

  /// A single day cell: centers the day number and highlights “today.”
  Widget _monthDayCell(DateTime monthDate, int day) {
    final today = DateTime.now();
    final isToday = (today.year == monthDate.year &&
        today.month == monthDate.month &&
        today.day == day);

    final weekday = DateTime(monthDate.year, monthDate.month, day).weekday;
    final isWeekend =
        (weekday == DateTime.saturday || weekday == DateTime.sunday);

    final textColor =
        isToday ? Colors.white : (isWeekend ? Colors.blue : Colors.black87);

    return Center(
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isToday ? Colors.green[700] : Colors.transparent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          '$day',
          style: TextStyle(
            color: textColor,
            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _drawerItem(BuildContext context, String title, String route) {
    return ListTile(
      title: Text(title),
      onTap: () => Navigator.pushNamed(context, route),
    );
  }
}
