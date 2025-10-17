import 'package:flutter/material.dart';
import '../services/notification_service.dart'; // adjust path if needed
import 'package:intl/intl.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  String _fmt(DateTime d) => DateFormat('yyyy-MM-dd HH:mm').format(d);

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await NotificationService.I.getLogs();
    // newest first
    list.sort((a, b) => (b['when'] as String).compareTo(a['when'] as String));
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final empty = !_loading && _items.isEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text('Notifications',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          TextButton(
            onPressed: () async {
              await NotificationService.I.seedDemo();
              if (mounted) await _load();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Seeded demo notifications')),
                );
              }
            },
            child: const Text('Seed demo'),
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await NotificationService.I.clearLogs();
              if (mounted) await _load();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cleared notification log (does not cancel scheduled ones)')),
                );
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : empty
              ? Center(
                  child: Text('There is no notification',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (_, i) {
                    final m = _items[i];
                    final when = DateTime.parse(m['when'] as String);
                    final kind = (m['kind'] as String?) ?? 'scheduled';
                    return ListTile(
                      leading: Icon(
                        kind == 'now' ? Icons.notifications_active : Icons.schedule,
                        color: kind == 'now' ? Colors.green : Colors.blueGrey,
                      ),
                      title: Text(m['title'] as String? ?? '(no title)',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${m['body'] ?? ''}\n${_fmt(when)}  •  $kind'),
                      isThreeLine: true,
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: _items.length,
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // one more instant “proof” button
          await NotificationService.I.showNow(
            id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
            title: 'Instant proof',
            body: 'Tapped the FAB.',
          );
          await _load();
        },
        icon: const Icon(Icons.notification_important),
        label: const Text('Show now'),
      ),
    );
  }
}
