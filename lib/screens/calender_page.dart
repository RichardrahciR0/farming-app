// lib/screens/calendar_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../services/jwt_helper.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  // ---- Config ----
  static const String _apiBase = "http://10.0.2.2:8000"; // Android emulator -> host
  static const int _baseYear = 2015; // calendar start
  static const int _endYear = 2035;  // calendar end

  late final PageController _pageController;
  late int _currentPage; // index across years*12

  bool _loading = false;
  List<dynamic> _tasks = []; // raw JSON from server

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentPage = (now.year - _baseYear) * 12 + (now.month - 1);
    _pageController = PageController(initialPage: _currentPage);
    _fetchEventsForMonth(DateTime(now.year, now.month));
  }

  // ======================================================
  // =============== Networking / API calls ===============
  // ======================================================

  Future<void> _fetchEventsForMonth(DateTime monthDate) async {
    setState(() => _loading = true);

    final headers = await JwtHelper.authHeaders();
    if (headers == null) {
      if (mounted) setState(() => _loading = false);
      debugPrint('⚠️ Not logged in / token refresh failed');
      return;
    }

    // Month boundaries in UTC
    final start =
        DateTime(monthDate.year, monthDate.month, 1).toUtc().toIso8601String();
    final end = DateTime(monthDate.year, monthDate.month + 1, 0)
        .toUtc()
        .toIso8601String();

    final url = Uri.parse("$_apiBase/api/events/?start=$start&end=$end");
    final resp = await http.get(url, headers: headers);

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      if (mounted) setState(() => _tasks = (data is List) ? data : []);
    } else {
      debugPrint("❌ Events fetch ${resp.statusCode}: ${resp.body}");
      if (mounted) setState(() => _tasks = []);
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String notes = "",
    bool allDay = false,
    String location = "",
  }) async {
    final headers = await JwtHelper.authHeaders();
    if (headers == null) return;

    final body = jsonEncode({
      "title": title,
      "notes": notes,
      "start_dt": start.toUtc().toIso8601String(),
      "end_dt": end.toUtc().toIso8601String(),
      "all_day": allDay,
      "location": location,
    });

    final resp = await http.post(
      Uri.parse("$_apiBase/api/events/"),
      headers: headers,
      body: body,
    );

    if (resp.statusCode != 201) {
      debugPrint("❌ Create failed ${resp.statusCode}: ${resp.body}");
    }
  }

  Future<bool> _deleteEvent(int id) async {
    final headers = await JwtHelper.authHeaders();
    if (headers == null) return false;

    final resp = await http.delete(
      Uri.parse("$_apiBase/api/events/$id/"),
      headers: headers,
    );

    // Our Django endpoint returns 204 on successful delete
    if (resp.statusCode == 204 || resp.statusCode == 200) {
      return true;
    }
    debugPrint("❌ Delete failed ${resp.statusCode}: ${resp.body}");
    return false;
  }

  // ======================================================
  // ===================== UI helpers =====================
  // ======================================================

  Future<void> _addTaskDialog() async {
    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime? selectedDate;
    TimeOfDay? startTime;
    TimeOfDay? endTime;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final dateLabel = selectedDate == null
              ? "No date"
              : DateFormat.yMMMd().format(selectedDate!);
          final startLabel =
              startTime == null ? "Start" : startTime!.format(ctx);
          final endLabel = endTime == null ? "End" : endTime!.format(ctx);

          return AlertDialog(
            title: const Text("Add Task"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: "Title"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    decoration:
                        const InputDecoration(labelText: "Notes (optional)"),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Text(dateLabel)),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(_baseYear),
                            lastDate: DateTime(_endYear, 12, 31),
                          );
                          if (picked != null) setLocal(() => selectedDate = picked);
                        },
                        child: const Text("Pick Date"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Text(startLabel)),
                      TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: const TimeOfDay(hour: 9, minute: 0),
                          );
                          if (t != null) setLocal(() => startTime = t);
                        },
                        child: const Text("Start Time"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Text(endLabel)),
                      TextButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: const TimeOfDay(hour: 10, minute: 0),
                          );
                          if (t != null) setLocal(() => endTime = t);
                        },
                        child: const Text("End Time"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (titleCtrl.text.trim().isEmpty || selectedDate == null) {
                    return;
                  }
                  final st = startTime ?? const TimeOfDay(hour: 9, minute: 0);
                  final et = endTime ?? const TimeOfDay(hour: 10, minute: 0);

                  final start = DateTime(
                    selectedDate!.year,
                    selectedDate!.month,
                    selectedDate!.day,
                    st.hour,
                    st.minute,
                  );
                  final end = DateTime(
                    selectedDate!.year,
                    selectedDate!.month,
                    selectedDate!.day,
                    et.hour,
                    et.minute,
                  );
                  if (end.isBefore(start)) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("End time must be after start time"),
                        ),
                      );
                    }
                    return;
                  }

                  await _createEvent(
                    title: titleCtrl.text.trim(),
                    start: start,
                    end: end,
                    notes: notesCtrl.text.trim(),
                  );
                  await _fetchEventsForMonth(DateTime(start.year, start.month));
                  if (context.mounted) Navigator.pop(ctx);
                },
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _confirmDeleteDialog(String title) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('This will permanently delete “$title”.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return res == true;
  }

  DateTime _monthForPage(int idx) {
    final year = _baseYear + idx ~/ 12;
    final month = (idx % 12) + 1;
    return DateTime(year, month);
  }

  // ======================================================
  // ======================== BUILD =======================
  // ======================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // App bar
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text('My Calendar', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addTaskDialog),
        ],
      ),
      backgroundColor: const Color(0xFFF7F8F9),

      // Body
      body: Column(
        children: [
          // Month scroller
          SizedBox(
            height: 340,
            child: PageView.builder(
              controller: _pageController,
              itemCount: (_endYear - _baseYear + 1) * 12,
              onPageChanged: (idx) {
                setState(() => _currentPage = idx);
                _fetchEventsForMonth(_monthForPage(idx));
              },
              itemBuilder: (ctx, idx) {
                return _buildMonthView(_monthForPage(idx));
              },
            ),
          ),

          const SizedBox(height: 12),

          // Task list title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Task List',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Task list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tasks.isEmpty
                    ? const Center(child: Text("No tasks for this month"))
                    : ListView.builder(
                        itemCount: _tasks.length,
                        itemBuilder: (ctx, i) {
                          final e = _tasks[i] as Map<String, dynamic>;
                          final id = (e["id"] ?? -1) as int;
                          final title = (e["title"] ?? "Untitled").toString();
                          final startStr = (e["start_dt"] ?? "").toString();
                          final endStr = (e["end_dt"] ?? "").toString();

                          DateTime? start;
                          DateTime? end;
                          try {
                            start = DateTime.parse(startStr).toLocal();
                          } catch (_) {}
                          try {
                            end = DateTime.parse(endStr).toLocal();
                          } catch (_) {}

                          final when = (start != null)
                              ? "${DateFormat.yMMMd().format(start)}  "
                                "${DateFormat.jm().format(start)}"
                                "${end != null ? " - ${DateFormat.jm().format(end)}" : ""}"
                              : (e["notes"] ?? "").toString();

                          return Dismissible(
                            key: ValueKey("event_$id"),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              color: Colors.red.shade400,
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            confirmDismiss: (_) async {
                              return await _confirmDeleteDialog(title);
                            },
                            onDismissed: (_) async {
                              final ok = await _deleteEvent(id);
                              if (!ok) {
                                // restore if failed
                                if (mounted) {
                                  setState(() => _tasks.insert(i, e));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Delete failed')),
                                  );
                                }
                              } else {
                                // optional re-fetch to stay in sync
                                await _fetchEventsForMonth(_monthForPage(_currentPage));
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Task deleted')),
                                  );
                                }
                              }
                            },
                            child: Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              child: ListTile(
                                leading: const Icon(Icons.event, color: Colors.green),
                                title: Text(title),
                                subtitle: Text(when),
                                trailing: IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () async {
                                    final sure = await _confirmDeleteDialog(title);
                                    if (!sure) return;
                                    final ok = await _deleteEvent(id);
                                    if (ok) {
                                      if (mounted) {
                                        setState(() => _tasks.removeAt(i));
                                        await _fetchEventsForMonth(_monthForPage(_currentPage));
                                      }
                                    } else {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Delete failed')),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),

      // Quick add FAB
      floatingActionButton: FloatingActionButton(
        onPressed: _addTaskDialog,
        backgroundColor: Colors.green,
        child: const Icon(Icons.add),
      ),

      // Bottom nav (placeholder)
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 4,
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
        onTap: (_) {},
      ),
    );
  }

  // ======================================================
  // ================ Calendar renderers ==================
  // ======================================================

  Widget _buildMonthView(DateTime monthDate) {
    final weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final firstWeekday =
        DateTime(monthDate.year, monthDate.month, 1).weekday; // Mon=1..Sun=7
    final leadingBlanks = firstWeekday - 1;
    final daysInMonth =
        DateUtils.getDaysInMonth(monthDate.year, monthDate.month);

    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++) _monthDayCell(monthDate, d),
    ];
    while (cells.length % 7 != 0) cells.add(const SizedBox.shrink());

    final rows = <TableRow>[
      TableRow(
        children: weekdays
            .map((d) => Center(
                  child: Text(
                    d,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                ))
            .toList(),
      ),
    ];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(TableRow(children: cells.sublist(i, i + 7)));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 4),
          Text(
            DateFormat.yMMMM().format(monthDate),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Table(
            defaultColumnWidth: const FlexColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: rows,
          ),
        ],
      ),
    );
  }

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
}
