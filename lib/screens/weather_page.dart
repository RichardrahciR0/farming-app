// lib/screens/weather_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:intl/intl.dart';

// Read your Gemini API key at runtime (don't hardcode!)
const String kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

// ⚠️ DEV-ONLY fallback (used only in debug/profile via `assert`).
// Replace with your own key locally. Do NOT commit to a public repo.
const String _DEV_FALLBACK_KEY = 'YOUR_LOCAL_DEV_KEY_HERE';

// Returns runtime key, or dev fallback in debug/profile builds.
// In release, the assert is stripped so only --dart-define works.
String _getGeminiKey() {
  var key = kGeminiApiKey;
  assert(() {
    if (key.isEmpty) key = _DEV_FALLBACK_KEY;
    return true;
  }());
  return key;
}

class WeatherPage extends StatefulWidget {
  @override
  _WeatherPageState createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  int _currentIndex = 5;

  bool _loading = true;
  String? _error;

  // Location
  double? _lat;
  double? _lon;
  String _placeLabel = "Locating…";

  // Current
  double? _currentTemp;
  int? _currentCode;
  String? _currentSummary;

  // Hourly [{time:'1pm', temp:24.0, code: 61}]
  final List<Map<String, dynamic>> _hourly = [];

  // Daily [{date:DateTime, min: 18.2, max: 27.9, code: 1, pop: 40}]
  final List<Map<String, dynamic>> _daily = [];

  // --- Planting advice: local (rule-based) + AI (Gemini) ---
  List<String> _plantingAdvice = [];
  bool _adviceExpanded = false;
  bool _aiBusy = false;
  String? _aiError;
  List<String>? _aiAdvice;

  @override
  void initState() {
    super.initState();
    _initWeather();
  }

  Future<void> _initWeather() async {
    setState(() {
      _loading = true;
      _error = null;
      _hourly.clear();
      _daily.clear();
      _aiAdvice = null; // clear old AI advice on refresh
      _aiError = null;
    });

    try {
      final hasPermission = await _ensureLocationPermission();
      if (!hasPermission) {
        // Fallback if GPS denied/off (Brisbane CBD)
        _lat = -27.4698;
        _lon = 153.0251;
      } else {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        _lat = pos.latitude;
        _lon = pos.longitude;
      }

      await Future.wait([
        _fetchPlaceLabel(), // suburb / locality
        _fetchOpenMeteo(),  // current + hourly + daily
      ]);

      // quick local suggestions (instant; AI remains optional)
      _plantingAdvice = _computePlantingAdvice();

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = "Failed to load weather: $e";
        _loading = false;
      });
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      return false;
    }
    return true;
  }

  // Resolve suburb/locality; prefer on-device geocoder, then Open-Meteo fallback
  Future<void> _fetchPlaceLabel() async {
    if (_lat == null || _lon == null) return;

    // Try device geocoder first
    try {
      final placemarks = await geo.placemarkFromCoordinates(
        _lat!, _lon!,
        localeIdentifier: 'en',
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;

        final pieces = <String>[
          if ((p.subLocality ?? '').trim().isNotEmpty) p.subLocality!.trim(),
          if ((p.locality ?? '').trim().isNotEmpty &&
              (p.locality ?? '') != (p.subLocality ?? ''))
            p.locality!.trim(),
        ];

        if (pieces.isNotEmpty) {
          _placeLabel = pieces.join(', ');
          return;
        }

        _placeLabel =
            p.locality?.trim().isNotEmpty == true ? p.locality!.trim()
          : p.administrativeArea?.trim().isNotEmpty == true ? p.administrativeArea!.trim()
          : p.country?.trim().isNotEmpty == true ? p.country!.trim()
          : "Your location";
        return;
      }
    } catch (_) {
      // ignore; fall through to network reverse-geocoding
    }

    // Fallback: Open-Meteo reverse geocoding
    try {
      final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/reverse'
        '?latitude=$_lat&longitude=$_lon&language=en&format=json',
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final results = (data['results'] as List?) ?? [];
        if (results.isNotEmpty) {
          final r = results.first as Map<String, dynamic>;
          final name = (r['name'] ?? '') as String;
          final admin2 = (r['admin2'] ?? '') as String; // city/LGA
          _placeLabel = (admin2.isNotEmpty && admin2 != name)
              ? '$name, $admin2'
              : (name.isNotEmpty ? name : "Your location");
          return;
        }
      }
    } catch (_) {}

    _placeLabel = "Your location"; // last resort
  }

  Future<void> _fetchOpenMeteo() async {
    if (_lat == null || _lon == null) return;

    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$_lat&longitude=$_lon'
      '&current=temperature_2m,weather_code,is_day'
      '&hourly=temperature_2m,weather_code,precipitation_probability'
      '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum'
      '&timezone=auto',
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;

    // Current
    final current = data['current'] as Map<String, dynamic>?;
    if (current != null) {
      _currentTemp = (current['temperature_2m'] as num?)?.toDouble();
      _currentCode = (current['weather_code'] as num?)?.toInt();
      _currentSummary = _codeToText(_currentCode ?? 0);
    }

    // Hourly
    _hourly.clear();
    final hourly = data['hourly'] as Map<String, dynamic>?;
    if (hourly != null) {
      final times = (hourly['time'] as List?) ?? [];
      final temps = (hourly['temperature_2m'] as List?) ?? [];
      final codes = (hourly['weather_code'] as List?) ?? [];
      for (int i = 0; i < times.length; i++) {
        final dt = DateTime.tryParse(times[i] as String);
        final label =
            dt != null ? DateFormat('ha').format(dt).toLowerCase() : '--';
        _hourly.add({
          'time': label,
          'temp': i < temps.length ? (temps[i] as num).toDouble() : null,
          'code': i < codes.length ? (codes[i] as num).toInt() : 0,
        });
      }
    }

    // Daily
    _daily.clear();
    final daily = data['daily'] as Map<String, dynamic>?;
    if (daily != null) {
      final dates = (daily['time'] as List?) ?? [];
      final tmax = (daily['temperature_2m_max'] as List?) ?? [];
      final tmin = (daily['temperature_2m_min'] as List?) ?? [];
      final dcode = (daily['weather_code'] as List?) ?? [];
      final popMax = (daily['precipitation_probability_max'] as List?) ?? [];
      for (int i = 0; i < dates.length; i++) {
        _daily.add({
          'date': DateTime.tryParse(dates[i] as String),
          'max': i < tmax.length ? (tmax[i] as num).toDouble() : null,
          'min': i < tmin.length ? (tmin[i] as num).toDouble() : null,
          'code': i < dcode.length ? (dcode[i] as num).toInt() : 0,
          'pop': i < popMax.length ? (popMax[i] as num?)?.toInt() : null,
        });
      }
    }
  }

  String _codeToText(int code) {
    if ([0].contains(code)) return 'Clear';
    if ([1, 2, 3].contains(code)) return 'Partly Cloudy';
    if ([45, 48].contains(code)) return 'Fog';
    if ([51, 53, 55].contains(code)) return 'Drizzle';
    if ([56, 57].contains(code)) return 'Freezing Drizzle';
    if ([61, 63, 65].contains(code)) return 'Rain';
    if ([66, 67].contains(code)) return 'Freezing Rain';
    if ([71, 73, 75, 77].contains(code)) return 'Snow';
    if ([80, 81, 82].contains(code)) return 'Showers';
    if ([85, 86].contains(code)) return 'Snow Showers';
    if ([95].contains(code)) return 'Thunderstorm';
    if ([96, 99].contains(code)) return 'Thunderstorm & Hail';
    return 'Unknown';
  }

  IconData _codeToIcon(int code) {
    if ([0].contains(code)) return Icons.wb_sunny_outlined;
    if ([1, 2, 3].contains(code)) return Icons.cloud_queue;
    if ([45, 48].contains(code)) return Icons.dehaze;
    if ([51, 53, 55].contains(code)) return Icons.grain;
    if ([61, 63, 65, 80, 81, 82].contains(code)) return Icons.water_drop;
    if ([66, 67].contains(code)) return Icons.ac_unit;
    if ([71, 73, 75, 77, 85, 86].contains(code)) return Icons.ac_unit;
    if ([95, 96, 99].contains(code)) return Icons.thunderstorm;
    return Icons.cloud_outlined;
  }

  // ---------- Local (rule-based) planting suggestions ----------
  List<String> _computePlantingAdvice() {
    if (_daily.isEmpty) return ["Not enough forecast data yet. Tap Refresh."];

    final today = _daily.first;
    final tMaxW = _daily.map((d) => (d['max'] as double?) ?? double.nan).where((v) => v == v).toList();
    final tMinW = _daily.map((d) => (d['min'] as double?) ?? double.nan).where((v) => v == v).toList();
    final weekMax = tMaxW.isEmpty ? null : tMaxW.reduce((a, b) => a > b ? a : b);
    final weekMin = tMinW.isEmpty ? null : tMinW.reduce((a, b) => a < b ? a : b);

    final double cur = (_currentTemp ?? (today['max'] ?? 20.0)).toDouble();
    final int popToday = (today['pop'] as int?) ?? 0;

    final month = DateTime.now().month;
    final southHemisphere = (_lat ?? 0) < 0;
    final seasonIdx = southHemisphere ? ((month + 6 - 1) ~/ 3) % 4 : ((month - 1) ~/ 3) % 4;
    final season = const ['Winter','Spring','Summer','Autumn'][seasonIdx];

    String band(double t) {
      if (t < 5) return 'frost';
      if (t < 12) return 'cool';
      if (t < 18) return 'mild';
      if (t < 26) return 'warm';
      return 'hot';
    }

    const crops = {
      'cool': ['spinach', 'lettuce', 'silverbeet', 'peas'],
      'mild': ['carrot', 'beetroot', 'broccoli', 'cauliflower'],
      'warm': ['tomato', 'capsicum', 'basil', 'zucchini', 'cucumber'],
      'hot' : ['sweet corn', 'eggplant', 'chilli', 'okra'],
    };

    final bandWeekMin = band((weekMin ?? cur));
    final bandWeekMax = band((weekMax ?? cur));

    final advice = <String>[];
    advice.add("This week looks **$bandWeekMin → $bandWeekMax** (min ${weekMin?.round()}° / max ${weekMax?.round()}°).");

    List<String> picks;
    if (bandWeekMax == 'hot') {
      picks = crops['hot']!;
    } else if (bandWeekMax == 'warm') {
      picks = crops['warm']!;
    } else if (bandWeekMax == 'mild') {
      picks = crops['mild']!;
    } else {
      picks = crops['cool']!;
    }
    advice.add("Good to plant: **${picks.take(4).join(', ')}**.");

    if (popToday >= 60) {
      advice.add("**Rain likely today (${popToday}%)** — sow/transplant then skip heavy watering.");
    } else if (popToday >= 30) {
      advice.add("Some rain chance (${popToday}%). Light irrigation if soil dries.");
    } else {
      advice.add("Low rain chance (${popToday}%). **Water in** new plantings and mulch.");
    }

    if ((weekMin ?? 99) < 3) advice.add("Possible **frost**. Cover seedlings at night or use cloches.");
    if ((weekMax ?? -99) > 32) advice.add("**Heat stress** risk. Provide shade cloth and water early morning.");

    advice.add("Season: **$season** — choose suitable varieties (heat-tolerant in summer, frost-tolerant in winter).");

    if (bandWeekMin == 'cool' || bandWeekMin == 'frost') {
      advice.add("Avoid **tomato/capsicum/basil** outdoors unless protected.");
    } else if (bandWeekMax == 'hot') {
      advice.add("Avoid **lettuce/peas** in full sun — likely to bolt; provide shade.");
    }

    return advice;
  }

  // ---------- Gemini model discovery + REST calls ----------

  // List models for a given API version ('v1' or 'v1beta').
  Future<List<String>> _listModels(String apiKey, {required String version}) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/$version/models?key=$apiKey',
    );
    final r = await http.get(uri);
    if (r.statusCode != 200) {
      throw Exception('listModels $version HTTP ${r.statusCode}: ${r.body}');
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final models = (data['models'] as List?) ?? const [];
    return models
        .map((m) => (m as Map<String, dynamic>)['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .map((n) => n.startsWith('models/') ? n.substring(7) : n)
        .toList();
  }

  // Pick the best available model from a list of IDs.
  String _pickBestModel(List<String> ids) {
    const candidates = [
      'gemini-1.5-flash',
      'gemini-1.5-flash-latest',
      'gemini-1.5-flash-002',
      'gemini-1.5-flash-001',
      'gemini-1.5-pro',
      'gemini-1.5-pro-latest',
      'gemini-1.5-pro-002',
      'gemini-1.5-pro-001',
      'gemini-1.0-pro',
      'gemini-1.0-pro-001',
      'gemini-pro', // legacy on v1beta
    ];
    for (final c in candidates) {
      if (ids.contains(c)) return c;
      final pref = ids.firstWhere(
        (m) => m == c || m.startsWith('$c-'),
        orElse: () => '',
      );
      if (pref.isNotEmpty) return pref;
    }
    return ids.firstWhere((m) => m.contains('gemini'), orElse: () => '');
  }

  // Generic generateContent over REST for v1/v1beta.
  Future<String> _geminiGenerate({
    required String apiKey,
    required String version, // 'v1' or 'v1beta'
    required String model,   // e.g., 'gemini-1.5-flash-001'
    required String prompt,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/$version/models/$model:generateContent?key=$apiKey',
    );
    final body = jsonEncode({
      "contents": [
        {
          "role": "user",
          "parts": [{"text": prompt}]
        }
      ]
    });

    final res = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: body,
    );

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = (data["candidates"] as List?) ?? const [];
    if (candidates.isEmpty) return "No advice generated.";
    final content = candidates.first["content"] as Map<String, dynamic>?;
    final parts = (content?["parts"] as List?) ?? const [];
    final text = (parts.isNotEmpty ? parts.first["text"] : "") as String? ?? "";
    return text.trim().isEmpty ? "No advice generated." : text.trim();
  }

  // ---------- Ask Google AI (Gemini) for richer suggestions ----------
  Future<void> _askGoogleAi() async {
    final apiKey = _getGeminiKey();
    if (apiKey.isEmpty) {
      setState(() => _aiError = 'Missing GEMINI_API_KEY. Run with: --dart-define=GEMINI_API_KEY=YOUR_KEY');
      return;
    }
    if (_daily.isEmpty) {
      setState(() => _aiError = 'No forecast loaded yet. Tap Refresh.');
      return;
    }

    setState(() {
      _aiBusy = true;
      _aiError = null;
      _aiAdvice = null;
    });

    try {
      String fmtDay(Map<String, dynamic> d, int i) {
        final dt = (d['date'] as DateTime?);
        final lab = i == 0 ? 'Today' : (dt != null ? DateFormat('EEE').format(dt) : 'Day ${i + 1}');
        final mn = (d['min'] as double?)?.round();
        final mx = (d['max'] as double?)?.round();
        final pop = (d['pop'] as int?) ?? 0;
        return '$lab: $mn–$mx°C, POP $pop%';
      }

      final week = _daily.asMap().entries.take(7).map((e) => fmtDay(e.value, e.key)).join('\n');
      final cur = _currentTemp?.round();
      final here = _placeLabel;
      final popToday = (_daily.first['pop'] as int?) ?? 0;

      final prompt = '''
You are an agronomy assistant. Using the weather summary, give practical planting advice for small-plot veggie gardeners near "$here".

Constraints:
- 5–8 concise bullet points.
- Recommend crop types suited to conditions (cool/mild/warm/hot).
- Call out frost/heat risks and protective actions.
- Irrigation/mulching guidance based on rain chance.
- If marginal conditions, suggest trays/indoors.
- Keep it local to this week's forecast.

Current: ${cur ?? '-'}°C, POP today $popToday%
7-day:
$week
''';

      // 1) Try v1 first
      String? bestModel;
      try {
        final v1 = await _listModels(apiKey, version: 'v1');
        bestModel = _pickBestModel(v1);
        if (bestModel != null && bestModel.isNotEmpty) {
          final text = await _geminiGenerate(
            apiKey: apiKey,
            version: 'v1',
            model: bestModel,
            prompt: prompt,
          );
          final lines = text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          final bullets = <String>[];
          for (final s in lines) {
            final m = RegExp(r'^[-•*]?\s*(.+)$').firstMatch(s);
            if (m != null) bullets.add(m.group(1)!.trim());
          }
          setState(() {
            _aiAdvice = bullets.isNotEmpty ? bullets : lines;
            _aiBusy = false;
            _adviceExpanded = true;
          });
          return; // done on v1
        }
      } catch (_) {
        // ignore and try v1beta
      }

      // 2) Fall back to v1beta
      final v1b = await _listModels(apiKey, version: 'v1beta');
      bestModel = _pickBestModel(v1b);
      if (bestModel == null || bestModel.isEmpty) {
        throw Exception('No compatible Gemini models available to this API key.');
      }

      final text = await _geminiGenerate(
        apiKey: apiKey,
        version: 'v1beta',
        model: bestModel,
        prompt: prompt,
      );

      final lines = text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final bullets = <String>[];
      for (final s in lines) {
        final m = RegExp(r'^[-•*]?\s*(.+)$').firstMatch(s);
        if (m != null) bullets.add(m.group(1)!.trim());
      }

      setState(() {
        _aiAdvice = bullets.isNotEmpty ? bullets : lines;
        _aiBusy = false;
        _adviceExpanded = true;
      });
    } catch (e) {
      setState(() {
        _aiBusy = false;
        _aiError = 'AI error: $e';
      });
    }
  }

  Widget _drawerItem(BuildContext context, String title, String route) {
    return ListTile(
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        Navigator.pushNamed(context, route);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleColor = Colors.black;

    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.green[700]),
              child: const SizedBox.shrink(),
            ),
            _drawerItem(context, 'Dashboard', '/'),
            _drawerItem(context, 'Layout Planning', '/map'),
            _drawerItem(context, 'Mapping', '/mapping'),
            _drawerItem(context, 'Task Manager', '/tasks'),
            _drawerItem(context, 'Add Task', '/add'),
            _drawerItem(context, 'Settings', '/settings'),
            _drawerItem(context, 'Notifications', '/notifications'),
            _drawerItem(context, 'Crop Database', '/cropdata'),
            _drawerItem(context, 'Calendar', '/calendar'),
            _drawerItem(context, 'Weather', '/weather'),
          ],
        ),
      ),

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: Text('Weather', style: TextStyle(color: titleColor)),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu, color: titleColor),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(icon: Icon(Icons.refresh, color: titleColor), onPressed: _initWeather),
          IconButton(icon: Icon(Icons.my_location_outlined, color: titleColor), onPressed: _initWeather),
          Padding(padding: const EdgeInsets.only(right: 12), child: CircleAvatar(backgroundColor: Colors.grey[300])),
        ],
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _initWeather)
              : _AppleLikeBody(
                  placeLabel: _placeLabel,
                  currentTemp: _currentTemp,
                  currentSummary: _currentSummary,
                  hourly: _hourly,
                  daily: _daily,
                  codeToIcon: _codeToIcon,
                  // pass advice & AI controls to the body
                  localAdvice: _plantingAdvice,
                  aiAdvice: _aiAdvice,
                  aiBusy: _aiBusy,
                  aiError: _aiError,
                  expanded: _adviceExpanded,
                  onToggleAdvice: () => setState(() => _adviceExpanded = !_adviceExpanded),
                  onAskAi: _askGoogleAi,
                ),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        currentIndex: _currentIndex,
        selectedItemColor: Colors.green[700],
        unselectedItemColor: Colors.grey,
        onTap: (i) {
          setState(() => _currentIndex = i);
          switch (i) {
            case 0: Navigator.pushNamed(context, '/'); break;
            case 1: Navigator.pushNamed(context, '/map'); break;
            case 2: Navigator.pushNamed(context, '/tasks'); break;
            case 3: Navigator.pushNamed(context, '/settings'); break;
            case 4: Navigator.pushNamed(context, '/calendar'); break;
            case 5: Navigator.pushNamed(context, '/weather'); break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.cloud_outlined), label: ''),
        ],
      ),
    );
  }
}

/* ---------- Apple-style stacked UI ---------- */

class _AppleLikeBody extends StatelessWidget {
  final String placeLabel;
  final double? currentTemp;
  final String? currentSummary;
  final List<Map<String, dynamic>> hourly;
  final List<Map<String, dynamic>> daily;
  final IconData Function(int) codeToIcon;

  // Advice + AI
  final List<String> localAdvice;
  final List<String>? aiAdvice;
  final bool aiBusy;
  final String? aiError;
  final bool expanded;
  final VoidCallback onToggleAdvice;
  final VoidCallback onAskAi;

  const _AppleLikeBody({
    required this.placeLabel,
    required this.currentTemp,
    required this.currentSummary,
    required this.hourly,
    required this.daily,
    required this.codeToIcon,
    required this.localAdvice,
    required this.aiAdvice,
    required this.aiBusy,
    required this.aiError,
    required this.expanded,
    required this.onToggleAdvice,
    required this.onAskAi,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Colors.black87;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Location + big temp + summary
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
            child: Text(placeLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Text(
              currentTemp != null ? '${currentTemp!.round()}°' : '--',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w200),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Text(
              currentSummary ?? '—',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: textColor),
            ),
          ),

          // --- Planting Suggestions (local + AI) ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _PlantingAdviceCard(
              localLines: localAdvice,
              aiLines: aiAdvice,
              aiBusy: aiBusy,
              aiError: aiError,
              expanded: expanded,
              onToggle: onToggleAdvice,
              onAskAi: onAskAi,
            ),
          ),
          const SizedBox(height: 12),

          // Hourly strip (next 24h)
          _HourlyStrip(hourly: hourly, codeToIcon: codeToIcon),

          const SizedBox(height: 8),

          // 7-day forecast card (min/max bar + icon + precip)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _DailyList(daily: daily, codeToIcon: codeToIcon),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _HourlyStrip extends StatelessWidget {
  final List<Map<String, dynamic>> hourly;
  final IconData Function(int) codeToIcon;
  const _HourlyStrip({required this.hourly, required this.codeToIcon});

  @override
  Widget build(BuildContext context) {
    final nowHour = DateTime.now().hour;
    final count = hourly.length.clamp(0, 24);
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final h = hourly[i];
          final label = (h['time'] as String?) ?? '';
          final temp = (h['temp'] as double?)?.round();
          final code = (h['code'] as int?) ?? 0;
          final isNow = _hourToInt(label) == nowHour;

          return Container(
            width: 64,
            decoration: BoxDecoration(
              color: isNow ? Colors.blue.withOpacity(0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isNow ? FontWeight.w600 : FontWeight.w400,
                    )),
                Icon(codeToIcon(code)),
                Text(temp != null ? '$temp°' : '--',
                    style: const TextStyle(fontSize: 16)),
              ],
            ),
          );
        },
      ),
    );
  }

  int? _hourToInt(String label) {
    try {
      final dt = DateFormat('ha').parse(label.toUpperCase());
      return dt.hour;
    } catch (_) {
      return null;
    }
  }
}

class _DailyList extends StatelessWidget {
  final List<Map<String, dynamic>> daily;
  final IconData Function(int) codeToIcon;
  const _DailyList({required this.daily, required this.codeToIcon});

  @override
  Widget build(BuildContext context) {
    final temps = daily
        .expand((d) => [d['min'] as double?, d['max'] as double?])
        .whereType<double>()
        .toList();
    final overallMin = temps.isEmpty ? 0.0 : temps.reduce((a, b) => a < b ? a : b);
    final overallMax = temps.isEmpty ? 0.0 : temps.reduce((a, b) => a > b ? a : b);
    final span = (overallMax - overallMin).clamp(1, 999).toDouble();

    final rows = daily.take(7).toList();
    return Column(
      children: rows.map((d) {
        final date = d['date'] as DateTime?;
        final idx = rows.indexOf(d);
        final dayLabel = date != null
            ? (idx == 0 ? 'Today' : DateFormat('EEE').format(date))
            : '';
        final code = (d['code'] as int?) ?? 0;
        final tMin = (d['min'] as double?)?.round();
        final tMax = (d['max'] as double?)?.round();
        final pop = (d['pop'] as int?); // %
        final minD = (d['min'] as double?) ?? overallMin;
        final maxD = (d['max'] as double?) ?? overallMax;

        final start = ((minD - overallMin) / span);
        final width = ((maxD - minD) / span);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              SizedBox(width: 64, child: Text(dayLabel)),
              SizedBox(width: 28, child: Icon(codeToIcon(code), size: 20)),
              if (pop != null)
                SizedBox(
                  width: 38,
                  child: Text('${pop}%', textAlign: TextAlign.right,
                      style: TextStyle(
                        color: pop >= 50 ? Colors.blue[700] : Colors.grey[700],
                        fontSize: 12,
                      )),
                )
              else
                const SizedBox(width: 38),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, c) => Stack(
                    children: [
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Positioned(
                        left: c.maxWidth * start,
                        width: c.maxWidth * width,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.orange[400],
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 40, child: Text(tMin != null ? '$tMin°' : '--', textAlign: TextAlign.right)),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  tMax != null ? '$tMax°' : '--',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ---------- Planting card (local + AI) ----------
class _PlantingAdviceCard extends StatelessWidget {
  final List<String> localLines;
  final List<String>? aiLines;
  final bool aiBusy;
  final String? aiError;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAskAi;

  const _PlantingAdviceCard({
    required this.localLines,
    required this.aiLines,
    required this.aiBusy,
    required this.aiError,
    required this.expanded,
    required this.onToggle,
    required this.onAskAi,
  });

  @override
  Widget build(BuildContext context) {
    final lines = aiLines ?? localLines;
    final title = aiLines == null ? 'Planting Suggestions' : 'Google AI Suggestions';
    final subtitle = aiLines == null ? 'Based on this week’s forecast' : 'Personalized by Gemini';

    final visible = expanded ? lines.length : (lines.isEmpty ? 0 : 2);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.agriculture, color: Colors.green),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(onPressed: onToggle, child: Text(expanded ? 'Hide' : 'More')),
              ],
            ),
            Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 8),

            if (aiBusy) ...[
              const SizedBox(height: 4),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Asking Google AI…'),
            ] else if (aiError != null) ...[
              Text(aiError!, style: TextStyle(color: Colors.red[700])),
            ] else if (lines.isEmpty) ...[
              const Text('No advice available yet.'),
            ] else ...[
              ...List.generate(visible, (i) => _bullet(lines[i])),
              if (!expanded && lines.length > visible)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 8, top: 2),
                  child: Text('+ ${lines.length - visible} more',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ),
            ],

            const SizedBox(height: 6),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: aiBusy ? null : onAskAi,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Ask Google AI'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onToggle,
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(expanded ? 'Show less' : 'Show more'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  '),
            Expanded(child: Text(s)),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
