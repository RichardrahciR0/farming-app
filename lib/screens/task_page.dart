import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/event_service.dart'; // <-- uses your EventService
// If your path differs, adjust the import accordingly.

class TaskPage extends StatefulWidget {
  const TaskPage({super.key});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final _svc = EventService();

  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = false;
  List<EventItem> _events = [];

  @override
  void initState() {
    super.initState();
    _loadMonth(_visibleMonth);
  }

  // ---- Data loading ---------------------------------------------------------

  DateTime _monthStart(DateTime m) => DateTime(m.year, m.month, 1);
  DateTime _monthEnd(DateTime m) => DateTime(m.year, m.month + 1, 0, 23, 59, 59);

  Future<void> _loadMonth(DateTime month) async {
    setState(() => _loading = true);
    final start = _monthStart(month);
    final end = _monthEnd(month);
    final items = await _svc.listEvents(start: start, end: end);
    items.sort((a, b) => a.start.compareTo(b.start));
    setState(() {
      _events = items;
      _loading = false;
    });
  }

  // ---- Group events by day --------------------------------------------------

  Map<DateTime, List<EventItem>> _groupByDay(List<EventItem> src) {
    final map = <DateTime, List<EventItem>>{};
    for (final e in src) {
      final d = DateTime(e.start.year, e.start.month, e.start.day);
      map.putIfAbsent(d, () => []).add(e);
    }
    final keys = map.keys.toList()..sort();
    return {for (final k in keys) k: map[k]!};
  }

  // ---- Mutations ------------------------------------------------------------

  Future<void> _toggleCompleted(EventItem e, bool value) async {
    final ok = await _svc.updateCompleted(id: e.id, completed: value);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update task')),
      );
      return;
    }
    await _loadMonth(_visibleMonth);
  }

  Future<void> _changeStatus(EventItem e, String status) async {
    final ok = await _svc.updateStatus(id: e.id, status: status);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to change status')),
      );
      return;
    }
    await _loadMonth(_visibleMonth);
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final byDay = _groupByDay(_events);

    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
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

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: const Text('Task Manager', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),

      backgroundColor: const Color(0xFFF7F8F9),
      body: Column(
        children: [
          const SizedBox(height: 8),
          _monthHeader(),
          const SizedBox(height: 8),
          _weekDayStrip(),
          const Divider(height: 16),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : byDay.isEmpty
                    ? const Center(child: Text('No tasks this month'))
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: byDay.entries.map((entry) {
                          final date = entry.key;
                          final items = entry.value;
                          return _daySection(date, items);
                        }).toList(),
                      ),
          ),
        ],
      ),

      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFFF7F8F9),
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

  Widget _monthHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () async {
              final next = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
              setState(() => _visibleMonth = DateTime(next.year, next.month));
              await _loadMonth(_visibleMonth);
            },
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat.yMMMM().format(_visibleMonth),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () async {
              final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
              setState(() => _visibleMonth = DateTime(next.year, next.month));
              await _loadMonth(_visibleMonth);
            },
          ),
        ],
      ),
    );
  }

  Widget _weekDayStrip() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: days
            .map((d) => Expanded(
                  child: Center(
                    child: Text(d,
                        style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600)),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _daySection(DateTime date, List<EventItem> items) {
    final isToday = _isSameDay(date, DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: BoxDecoration(
              color: isToday ? Colors.green[700] : Colors.green[800],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${DateFormat.EEEE().format(date)}, ${DateFormat.yMMMd().format(date)}'
              '${isToday ? "  (Today)" : ""}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),

          // Items
          ...items.map((e) => _taskTile(e)).toList(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _taskTile(EventItem e) {
    final subtitle = _timeRange(e);
    final checked = e.completed;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Checkbox(
          value: checked,
          onChanged: (v) => _toggleCompleted(e, v ?? false),
        ),
        title: Text(
          e.title,
          style: TextStyle(
            decoration: checked ? TextDecoration.lineThrough : TextDecoration.none,
            color: checked ? Colors.grey : Colors.black,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: _statusChip(e),
        onTap: () => _showTaskDetails(e),
      ),
    );
  }

  String _timeRange(EventItem e) {
    final s = e.start.toLocal();
    final startStr = DateFormat.jm().format(s);
    if (e.end == null) {
      return '${DateFormat.yMMMd().format(s)} • $startStr';
    }
    final endStr = DateFormat.jm().format(e.end!.toLocal());
    return '${DateFormat.yMMMd().format(s)} • $startStr – $endStr';
    }

  Widget _statusChip(EventItem e) {
    final (bg, label) = _statusStyle(e.status, e.completed);
    return InkWell(
      onTap: () => _selectStatus(e),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }

  (Color, String) _statusStyle(String status, bool completed) {
    if (completed || status == 'completed') {
      return (Colors.green, 'Completed');
    }
    switch (status) {
      case 'in_progress':
        return (Colors.amber, 'In Progress');
      case 'not_started':
      default:
        return (Colors.redAccent, 'Not started');
    }
  }

  Future<void> _selectStatus(EventItem e) async {
    final options = const [
      ('not_started', 'Not started'),
      ('in_progress', 'In Progress'),
      ('completed', 'Completed'),
    ];

    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Change status'),
        children: options
            .map((opt) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, opt.$1),
                  child: Text(opt.$2),
                ))
            .toList()
          ..add(SimpleDialogOption(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          )),
      ),
    );

    if (chosen != null) {
      // If user chose "completed", also set completed=true on server
      if (chosen == 'completed') {
        await _toggleCompleted(e, true);
      } else {
        await _changeStatus(e, chosen);
      }
    }
  }

  void _showTaskDetails(EventItem e) {
    final subtitle = _timeRange(e);
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(e.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(subtitle, style: TextStyle(color: Colors.grey[700])),
                Text(
                  e.completed ? "Done" : "",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Notes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                (e.notes ?? '').isEmpty ? '—' : e.notes!,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(backgroundColor: Colors.green[700]),
              child: const Text('Close'),
            ),
          ]),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
