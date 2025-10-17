import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keep this enum in sync with MapPage's TaskType
enum TaskType { watering, fertilising, weeding, inspection, harvest }

class LocalTask {
  String id;
  String plotId;
  String plotName;
  String? crop;
  TaskType type;
  String title;
  DateTime due;
  int? repeatEveryDays;
  bool done;

  LocalTask({
    required this.id,
    required this.plotId,
    required this.plotName,
    required this.type,
    required this.title,
    required this.due,
    this.crop,
    this.repeatEveryDays,
    this.done = false,
  });

  factory LocalTask.fromJson(Map<String, dynamic> m) => LocalTask(
        id: m['id'] as String,
        plotId: m['plotId'] as String,
        plotName: m['plotName'] as String,
        crop: m['crop'] as String?,
        type: TaskType.values.firstWhere((t) => t.name == (m['type'] as String)),
        title: m['title'] as String,
        due: DateTime.parse(m['due'] as String),
        repeatEveryDays: m['repeatEveryDays'] as int?,
        done: (m['done'] ?? false) as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'plotId': plotId,
        'plotName': plotName,
        'crop': crop,
        'type': type.name,
        'title': title,
        'due': due.toIso8601String(),
        'repeatEveryDays': repeatEveryDays,
        'done': done,
      };
}

class TaskPage extends StatefulWidget {
  const TaskPage({super.key});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  bool _loading = false;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<LocalTask> _monthTasks = [];   // tasks in current visible month
  List<LocalTask> _allTasks = [];     // full list from storage

  @override
  void initState() {
    super.initState();
    _loadMonth(_visibleMonth);
  }

  // ===== Storage =====

  Future<void> _loadAllFromStorage() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('tasks_v1');
    _allTasks = [];
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((e) => LocalTask.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _allTasks.addAll(list);
    }
  }

  Future<void> _saveAllToStorage() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      'tasks_v1',
      jsonEncode(_allTasks.map((t) => t.toJson()).toList()),
    );
  }

  // ===== Filtering/grouping =====

  DateTime _monthStart(DateTime m) => DateTime(m.year, m.month, 1);
  DateTime _monthEnd(DateTime m) => DateTime(m.year, m.month + 1, 0, 23, 59, 59);

  Future<void> _loadMonth(DateTime month) async {
    setState(() => _loading = true);
    await _loadAllFromStorage();

    final start = _monthStart(month);
    final end = _monthEnd(month);

    _monthTasks = _allTasks
        .where((t) =>
            (t.due.isAfter(start.subtract(const Duration(seconds: 1))) &&
             t.due.isBefore(end.add(const Duration(seconds: 1)))))
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));

    setState(() => _loading = false);
  }

  Map<DateTime, List<LocalTask>> _groupByDay(List<LocalTask> src) {
    final map = <DateTime, List<LocalTask>>{};
    for (final e in src) {
      final d = DateTime(e.due.year, e.due.month, e.due.day);
      map.putIfAbsent(d, () => []).add(e);
    }
    final keys = map.keys.toList()..sort();
    return {for (final k in keys) k: map[k]!};
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ===== Mutations =====

  Future<void> _toggleDone(LocalTask e, bool value) async {
    // Update in-memory
    final idx = _allTasks.indexWhere((x) => x.id == e.id);
    if (idx >= 0) {
      _allTasks[idx].done = value;
    }

    // If this task repeats and user completed it, create the next one
    if (value && e.repeatEveryDays != null && e.repeatEveryDays! > 0) {
      final nextDue = e.due.add(Duration(days: e.repeatEveryDays!));
      final next = LocalTask(
        id: 'rep_${e.id}_${DateTime.now().millisecondsSinceEpoch}',
        plotId: e.plotId,
        plotName: e.plotName,
        crop: e.crop,
        type: e.type,
        title: e.title,
        due: nextDue,
        repeatEveryDays: e.repeatEveryDays,
        done: false,
      );
      _allTasks.add(next);
    }

    await _saveAllToStorage();
    await _loadMonth(_visibleMonth);
  }

  Future<void> _deleteTask(LocalTask e) async {
    _allTasks.removeWhere((x) => x.id == e.id);
    await _saveAllToStorage();
    await _loadMonth(_visibleMonth);
  }

  // ===== NEW: manual add helpers =====

  String _newId() => 'local_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _addTask(LocalTask t) async {
    _allTasks.add(t);
    await _saveAllToStorage();
    await _loadMonth(_visibleMonth);
  }

  Future<void> _showAddTaskDialog() async {
    final titleCtrl = TextEditingController();
    DateTime? date;
    TimeOfDay? time;
    TaskType type = TaskType.inspection;
    final repeatCtrl = TextEditingController(); // days, optional
    final plotNameCtrl = TextEditingController(); // optional
    final cropCtrl = TextEditingController(); // optional

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add Task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(date == null ? 'Pick date' : DateFormat.yMMMd().format(date!))),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2015),
                          lastDate: DateTime(2035, 12, 31),
                        );
                        if (picked != null) setLocal(() => date = picked);
                      },
                      child: const Text('Date'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(time == null ? 'Pick time' : time!.format(ctx))),
                    TextButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                        if (t != null) setLocal(() => time = t);
                      },
                      child: const Text('Time'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<TaskType>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: TaskType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                  onChanged: (v) => setLocal(() => type = v ?? TaskType.inspection),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: repeatCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Repeat every N days (optional)'),
                ),
                const SizedBox(height: 8),
                TextField(controller: plotNameCtrl, decoration: const InputDecoration(labelText: 'Plot name (optional)')),
                const SizedBox(height: 8),
                TextField(controller: cropCtrl, decoration: const InputDecoration(labelText: 'Crop (optional)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty || date == null) return;
                final t = time ?? const TimeOfDay(hour: 9, minute: 0);
                final due = DateTime(date!.year, date!.month, date!.day, t.hour, t.minute);
                final repeat = int.tryParse(repeatCtrl.text.trim());
                final newTask = LocalTask(
                  id: _newId(),
                  plotId: '', // optional for manual
                  plotName: plotNameCtrl.text.trim().isEmpty ? 'General' : plotNameCtrl.text.trim(),
                  crop: cropCtrl.text.trim().isEmpty ? null : cropCtrl.text.trim(),
                  type: type,
                  title: titleCtrl.text.trim(),
                  due: due,
                  repeatEveryDays: repeat,
                  done: false,
                );
                await _addTask(newTask);
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDay(_monthTasks);

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
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadMonth(_visibleMonth),
          ),
        ],
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
                : grouped.isEmpty
                    ? const Center(child: Text('No tasks this month'))
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: grouped.entries.map((entry) {
                          final date = entry.key;
                          final items = entry.value;
                          return _daySection(date, items);
                        }).toList(),
                      ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        backgroundColor: Colors.green,
        child: const Icon(Icons.add),
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

  // --- Header / helpers ---

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

  Widget _daySection(DateTime date, List<LocalTask> items) {
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
          ...items.map((e) => Dismissible(
                key: ValueKey(e.id),
                background: Container(
                  decoration: BoxDecoration(
                    color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                secondaryBackground: Container(
                  decoration: BoxDecoration(
                    color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerRight,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => _deleteTask(e),
                child: Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: Checkbox(
                      value: e.done,
                      onChanged: (v) => _toggleDone(e, v ?? false),
                    ),
                    title: Text(
                      e.title,
                      style: TextStyle(
                        decoration: e.done ? TextDecoration.lineThrough : TextDecoration.none,
                        color: e.done ? Colors.grey : Colors.black,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(_timeLabel(e)),
                    trailing: _typeChip(e),
                  ),
                ),
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _timeLabel(LocalTask e) {
    final s = e.due.toLocal();
    return '${DateFormat.yMMMd().format(s)} • ${DateFormat.jm().format(s)}'
        '${e.repeatEveryDays != null ? ' • repeats every ${e.repeatEveryDays}d' : ''}';
  }

  Widget _typeChip(LocalTask e) {
    final (bg, label) = switch (e.type) {
      TaskType.watering   => (Colors.blue, 'Water'),
      TaskType.fertilising=> (Colors.deepOrange, 'Fertilise'),
      TaskType.weeding    => (Colors.teal, 'Weed'),
      TaskType.inspection => (Colors.indigo, 'Inspect'),
      TaskType.harvest    => (Colors.green, 'Harvest'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
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
