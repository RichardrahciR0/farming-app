import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dashboard_service.dart'; // 👈 adjust path if your folders differ

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Default layout
  List<Map<String, dynamic>> widgetsList = [
    {'name': 'My Plot', 'visible': true},
    {'name': 'Crop Growth', 'visible': true},
    {'name': 'Overall Growth', 'visible': true},
    {'name': 'Yield Projection', 'visible': true},
    {'name': 'Pending Tasks', 'visible': true},
    {'name': 'Bushfire Alert', 'visible': true},
  ];

  final Map<String, IconData> widgetIcons = const {
    'My Plot': Icons.terrain,
    'Crop Growth': Icons.eco,
    'Overall Growth': Icons.grass,
    'Yield Projection': Icons.analytics,
    'Pending Tasks': Icons.pending_actions,
    'Bushfire Alert': Icons.warning,
  };

  final List<String> availableWidgets = const [
    'My Plot',
    'Crop Growth',
    'Overall Growth',
    'Yield Projection',
    'Pending Tasks',
    'Bushfire Alert',
  ];

  bool isEditMode = false;
  bool _loading = true;

  final _dash = DashboardService(); // 👈 backend service

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 1) Load from local cache fast
    await _loadLocal();

    // 2) Try to load from server and overwrite local if found
    final remote = await _dash.loadLayout();
    if (remote.isNotEmpty) {
      setState(() => widgetsList = _sanitize(remote));
      await _saveLocal(); // keep cache fresh
    }

    if (mounted) setState(() => _loading = false);
  }

  // ---- Local cache helpers ----
  List<Map<String, dynamic>> _sanitize(List<Map<String, dynamic>> raw) {
    // Ensure every item has 'name' and 'visible' as bool
    return raw.map<Map<String, dynamic>>((w) {
      final m = Map<String, dynamic>.from(w);
      m['name'] = m['name']?.toString() ?? 'Widget';
      m['visible'] = (m['visible'] is bool) ? m['visible'] : true;
      return m;
    }).toList();
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dashboard_widgets', jsonEncode(widgetsList));
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('dashboard_widgets');
    if (data != null) {
      final loaded = List<Map<String, dynamic>>.from(jsonDecode(data));
      setState(() => widgetsList = _sanitize(loaded));
    }
  }

  // ---- Server save wrapper ----
  Future<void> _saveServerWithToast() async {
    final ok = await _dash.saveLayout(widgetsList);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Dashboard saved to your account' : 'Couldn’t save to server')),
      );
    }
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.green[700]),
              child: Center(child: Image.asset('assets/logo.png', height: 60)),
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
      backgroundColor: const Color(0xFFF7F8F9),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(160),
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu, size: 32),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.notifications_none, size: 28),
                    onPressed: () => Navigator.pushNamed(context, '/notifications'),
                  ),
                ]),
                Image.asset('assets/logo.png', height: 160, width: 160, fit: BoxFit.contain),
                Row(children: [
                  IconButton(
                    icon: Icon(isEditMode ? Icons.check : Icons.edit),
                    onPressed: () async {
                      setState(() => isEditMode = !isEditMode);
                      if (!isEditMode) {
                        await _saveLocal();
                        await _saveServerWithToast();
                      }
                    },
                  ),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey[300],
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main dashboard area (drag target + reorderable list)
                    Expanded(
                      flex: 4,
                      child: DashboardArea(
                        widgetsList: widgetsList,
                        widgetIcons: widgetIcons,
                        isEditMode: isEditMode,
                        onToggleVisibility: (index, val) {
                          setState(() => widgetsList[index]['visible'] = val);
                        },
                        onAcceptWidget: (receivedName) {
                          final index = widgetsList.indexWhere((w) => w['name'] == receivedName);
                          setState(() {
                            if (index != -1) {
                              widgetsList[index]['visible'] = true;
                            } else {
                              widgetsList.add({'name': receivedName, 'visible': true});
                            }
                          });
                        },
                        onReorderVisible: (oldVisibleIndex, newVisibleIndex) {
                          if (!isEditMode) return;
                          setState(() {
                            _moveInMasterListByVisibleIndex(oldVisibleIndex, newVisibleIndex);
                          });
                        },
                      ),
                    ),

                    // Right overlay panel with draggable widget chips (only in edit mode)
                    if (isEditMode)
                      SizedBox(
                        width: 180,
                        child: Container(
                          height: MediaQuery.of(context).size.height,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(-2, 0))],
                          ),
                          child: Column(
                            children: [
                              const SizedBox(height: 16),
                              const Text("Widgets", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Scrollbar(
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                    child: Column(
                                      children: availableWidgets.map((name) {
                                        return Draggable<String>(
                                          data: name,
                                          feedback: _widgetPreview(name),
                                          childWhenDragging: Opacity(opacity: 0.5, child: _widgetPreview(name)),
                                          child: _widgetPreview(name),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                // Save button (only in edit mode)
                if (isEditMode)
                  Positioned(
                    bottom: 12,
                    right: 20,
                    child: ElevatedButton(
                      onPressed: () async {
                        await _saveLocal();
                        await _saveServerWithToast();
                        if (mounted) setState(() => isEditMode = false);
                      },
                      child: const Text('Save'),
                    ),
                  ),
              ],
            ),
      // NOTE: not const (you saw a compile error before when it was const)
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

  // Render a preview chip for the right-side panel
  Widget _widgetPreview(String name) {
    return Container(
      height: 70,
      width: 120,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widgetIcons[name], color: Colors.white, size: 20),
          const SizedBox(height: 4),
          Text(
            name,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  ListTile _drawerItem(BuildContext context, String title, String route) {
    return ListTile(
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        if (route != '/') Navigator.pushNamed(context, route);
      },
    );
  }

  /// Reorders the underlying master list using indices from the *visible-only* list.
  void _moveInMasterListByVisibleIndex(int oldVisibleIndex, int newVisibleIndex) {
    final visible = <Map<String, dynamic>>[];
    final mapping = <int>[]; // visibleIndex -> masterIndex
    for (int i = 0; i < widgetsList.length; i++) {
      if (widgetsList[i]['visible'] == true) {
        visible.add(widgetsList[i]);
        mapping.add(i);
      }
    }

    // normalize newVisibleIndex same way ReorderableListView does
    if (newVisibleIndex > oldVisibleIndex) newVisibleIndex--;

    if (oldVisibleIndex < 0 ||
        oldVisibleIndex >= mapping.length ||
        newVisibleIndex < 0 ||
        newVisibleIndex >= mapping.length) return;

    final fromMaster = mapping[oldVisibleIndex];
    final toMaster = mapping[newVisibleIndex];

    final item = widgetsList.removeAt(fromMaster);

    // If we removed an item before the target index, the target shifts left by 1.
    final adjustedTarget = (fromMaster < toMaster) ? toMaster - 1 : toMaster;
    widgetsList.insert(adjustedTarget, item);
  }
}

class DashboardArea extends StatefulWidget {
  final List<Map<String, dynamic>> widgetsList;
  final Map<String, IconData> widgetIcons;
  final bool isEditMode;
  final void Function(int index, bool value) onToggleVisibility;
  final void Function(String name) onAcceptWidget;
  final void Function(int oldVisibleIndex, int newVisibleIndex) onReorderVisible;

  const DashboardArea({
    super.key,
    required this.widgetsList,
    required this.widgetIcons,
    required this.isEditMode,
    required this.onToggleVisibility,
    required this.onAcceptWidget,
    required this.onReorderVisible,
  });

  @override
  State<DashboardArea> createState() => _DashboardAreaState();
}

class _DashboardAreaState extends State<DashboardArea> {
  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAccept: (data) => widget.isEditMode,
      onAccept: (receivedName) {
        HapticFeedback.lightImpact();
        widget.onAcceptWidget(receivedName);
      },
      builder: (context, candidateData, rejectedData) {
        final visibleItems = widget.widgetsList.where((w) => (w['visible'] as bool)).toList();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: candidateData.isNotEmpty ? Border.all(color: Colors.green, width: 3) : null,
          ),
          child: Column(
            children: [
              const SizedBox(height: 4),
              const Text(
                "Dashboard",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2E4E3F)),
              ),
              const SizedBox(height: 12),
              if (candidateData.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text("Drop to add widget",
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ),

              // Reorderable visible list only (we map indices back to master list)
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ReorderableListView.builder(
                    padding: EdgeInsets.zero,
                    itemBuilder: (context, i) {
                      final item = visibleItems[i];
                      return _DashboardCardRow(
                        key: ValueKey(item['name']),
                        title: item['name'],
                        icon: widget.widgetIcons[item['name']] ?? Icons.widgets,
                        isEditMode: widget.isEditMode,
                        visible: true,
                        onVisibilityChanged: (val) {
                          final idx = widget.widgetsList.indexWhere((w) => w['name'] == item['name']);
                          if (idx != -1) widget.onToggleVisibility(idx, val);
                        },
                      );
                    },
                    itemCount: visibleItems.length,
                    onReorder: widget.onReorderVisible,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardCardRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isEditMode;
  final bool visible;
  final ValueChanged<bool> onVisibilityChanged;

  const _DashboardCardRow({
    super.key,
    required this.title,
    required this.icon,
    required this.isEditMode,
    required this.visible,
    required this.onVisibilityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(icon, size: 26, color: Colors.green),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    if (!isEditMode) return card;

    return Row(
      children: [
        Checkbox(value: visible, onChanged: (v) => onVisibilityChanged(v ?? true)),
        Expanded(child: card),
      ],
    );
  }
}
