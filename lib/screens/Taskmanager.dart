import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/event_service.dart'; // uses EventService + EventItem

class TaskManagerPage extends StatefulWidget {
  const TaskManagerPage({super.key});

  @override
  State<TaskManagerPage> createState() => _TaskManagerPageState();
}

class _TaskManagerPageState extends State<TaskManagerPage> {
  final _svc = EventService();

  // day strip
  DateTime _anchor = _today(); // first chip = today
  int _selectedOffset = 0;      // 0..6 within week strip

  // tab
  bool _showToday = true;

  // cache
  bool _loading = false;
  List<EventItem> _items = [];

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _selectedDay => _anchor.add(Duration(days: _selectedOffset));

  @override
  void initState() {
    super.initState();
    _loadForSelectedDay();
  }

  Future<void> _loadForSelectedDay() async {
    setState(() => _loading = true);
    final day = _selectedDay;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final list = await _svc.listEvents(start: start, end: end);
    setState(() {
      _items = list..sort((a, b) => a.start.compareTo(b.start));
      _loading = false;
    });
  }

  Future<void> _loadUpcoming() async {
    setState(() => _loading = true);
    final start = _today();
    final end = start.add(const Duration(days: 14));
    final list = await _svc.listEvents(start: start, end: end);
    setState(() {
      _items = list..sort((a, b) => a.start.compareTo(b.start));
      _loading = false;
    });
  }

  Future<void> _toggleDone(EventItem e, bool done) async {
    // optimistic UI
    final old = e.status;
    e.status = done ? 'completed' : 'not_started';
    setState(() {});

    final ok = await _svc.updateEventStatus(e.id, e.status!);
    if (!ok) {
      // revert on failure
      e.status = old;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update status')),
        );
      }
      setState(() {});
    }
  }

  // UI ------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Manager'),
        actions: const [
          Icon(Icons.add),
          SizedBox(width: 12),
          Icon(Icons.account_circle),
          SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // date chips (week strip)
          if (_showToday) _DayStrip(
            anchor: _anchor,
            selectedOffset: _selectedOffset,
            onSelect: (i) {
              setState(() => _selectedOffset = i);
              _loadForSelectedDay();
            },
          ),

          // tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                _tab('Today', _showToday, () {
                  setState(() => _showToday = true);
                  _loadForSelectedDay();
                }),
                const SizedBox(width: 8),
                _tab('Upcoming', !_showToday, () {
                  setState(() => _showToday = false);
                  _loadUpcoming();
                }),
              ],
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          _showToday
                              ? 'No tasks for ${DateFormat('EEE, d MMM').format(_selectedDay)}'
                              : 'No upcoming tasks',
                        ),
                      )
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, i) => _TaskCard(
                          item: _items[i],
                          onToggle: (v) => _toggleDone(_items[i], v),
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.task_alt), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: ''),
        ],
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: active ? Colors.green : const Color(0xFFE7E7E7),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// --- Day strip ----------------------------------------------------------------

class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.anchor,
    required this.selectedOffset,
    required this.onSelect,
  });

  final DateTime anchor;
  final int selectedOffset;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final days = List<DateTime>.generate(7, (i) => anchor.add(Duration(days: i)));
    return SizedBox(
      height: 86,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final d = days[i];
          final sel = i == selectedOffset;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              width: 72,
              decoration: BoxDecoration(
                color: sel ? Colors.green.shade700 : Colors.green.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('EEE').format(d),
                      style: TextStyle(
                        color: sel ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 6),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: sel ? Colors.green : Colors.white,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${d.day}',
                      style: TextStyle(
                        color: sel ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- Task card ----------------------------------------------------------------

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.item,
    required this.onToggle,
  });

  final EventItem item;
  final ValueChanged<bool> onToggle;

  Color _statusColor(String s) {
    switch (s) {
      case 'completed':
        return Colors.green;
      case 'in_progress':
        return Colors.amber;
      default:
        return Colors.red;
    }
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'completed':
        return 'Completed';
      case 'in_progress':
        return 'In Progress';
      default:
        return 'Not started';
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = item.start.toLocal();
    final end = (item.end ?? item.start).toLocal();
    final time =
        '${DateFormat('hh:mm a').format(start)} – ${DateFormat('hh:mm a').format(end)}';

    final status = item.status ?? 'not_started';
    final statusColor = _statusColor(status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.schedule, color: Colors.black54),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(time, style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            Checkbox(
              value: status == 'completed',
              onChanged: (v) => onToggle(v ?? false),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _statusLabel(status),
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
