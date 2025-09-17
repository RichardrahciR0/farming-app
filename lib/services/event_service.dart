import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'jwt_helper.dart';

class EventItem {
  final int id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final String? notes;
  final String status; // 'not_started' | 'in_progress' | 'completed'
  final bool completed;

  EventItem({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    required this.allDay,
    this.notes,
    required this.status,
    required this.completed,
  });

  factory EventItem.fromJson(Map<String, dynamic> j) => EventItem(
        id: j['id'] as int,
        title: (j['title'] ?? '').toString(),
        start: DateTime.parse(j['start_dt']).toLocal(),
        end: j['end_dt'] != null ? DateTime.parse(j['end_dt']).toLocal() : null,
        allDay: (j['all_day'] ?? false) as bool,
        notes: j['notes']?.toString(),
        status: (j['status'] ?? 'not_started') as String,
        completed: (j['completed'] ?? false) as bool,
      );
}

class EventService {
  EventService({AuthService? auth}) : _auth = auth ?? AuthService();

  final AuthService _auth;

  List<String> get _bases {
    final pref = _auth.getBaseUrl(); // legacy compat from AuthService
    final defaults = <String>[
      'http://10.0.2.2:8000',  // Android emulator -> host machine
      'http://127.0.0.1:8000', // iOS simulator / desktop
      'http://192.168.1.101:8000',
      'http://192.168.1.103:8000',
    ];
    return <String>{ if (pref != null) pref, ...defaults }.toList(growable: false);
  }

  void _log(String m) {
    if (kDebugMode) print('[EVENTS] $m');
  }

  Future<http.Response?> _withAnyBase(
    Future<http.Response> Function(String) builder,
  ) async {
    final headers = await JwtHelper.authHeaders();
    if (headers == null) {
      _log('No auth headers (not logged in or refresh failed).');
      return null;
    }
    for (final b in _bases) {
      try {
        final r = await builder(b);
        _log('[$b] -> ${r.statusCode}');
        return r;
      } catch (e) {
        _log('[$b] error: $e');
      }
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // READ
  // --------------------------------------------------------------------------
  Future<List<EventItem>> listEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    final headers = await JwtHelper.authHeaders();
    if (headers == null) return [];
    final qs = '?start=${start.toUtc().toIso8601String()}&end=${end.toUtc().toIso8601String()}';

    http.Response? resp;
    for (final b in _bases) {
      try {
        resp = await http.get(Uri.parse('$b/api/events/$qs'), headers: headers);
        _log('[$b] -> ${resp.statusCode}');
        break;
      } catch (e) {
        _log('[$b] error: $e');
      }
    }
    if (resp == null || resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => EventItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --------------------------------------------------------------------------
  // CREATE
  // --------------------------------------------------------------------------
  Future<bool> createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    bool allDay = false,
    String? notes,
    String? location,
  }) async {
    final headers = await JwtHelper.authHeaders();
    if (headers == null) return false;

    final Map<String, dynamic> body = {
      'title': title,
      'start_dt': start.toUtc().toIso8601String(),
      'end_dt': end.toUtc().toIso8601String(),
      'all_day': allDay,
      'status': 'not_started',
      'completed': false,
    };
    if (notes != null && notes.isNotEmpty) body['notes'] = notes;
    if (location != null && location.isNotEmpty) body['location'] = location;

    http.Response? resp;
    for (final b in _bases) {
      try {
        resp = await http.post(
          Uri.parse('$b/api/events/'),
          headers: headers,
          body: jsonEncode(body),
        );
        _log('[$b] -> ${resp.statusCode}');
        break;
      } catch (e) {
        _log('[$b] error: $e');
      }
    }
    return resp != null && (resp.statusCode == 201 || resp.statusCode == 200);
  }

  // --------------------------------------------------------------------------
  // UPDATE (checkbox & status)
  // --------------------------------------------------------------------------

  /// Mark an event as completed/in progress (updates both fields server-side).
  Future<bool> updateCompleted({
    required int id,
    required bool completed,
  }) async {
    final headers = await JwtHelper.authHeaders();
    if (headers == null) return false;
    http.Response? resp;
    for (final b in _bases) {
      try {
        resp = await http.patch(
          Uri.parse('$b/api/events/$id/'),
          headers: headers,
          body: jsonEncode({
            'completed': completed,
            'status': completed ? 'completed' : 'in_progress',
          }),
        );
        _log('[$b] -> ${resp.statusCode}');
        break;
      } catch (e) {
        _log('[$b] error: $e');
      }
    }
    return resp != null && resp.statusCode == 200;
  }

  /// Set a specific status (kept separate so you can drive the colored pill).
  Future<bool> updateStatus({
    required int id,
    required String status,
  }) async {
    final headers = await JwtHelper.authHeaders();
    if (headers == null) return false;
    http.Response? resp;
    for (final b in _bases) {
      try {
        resp = await http.patch(
          Uri.parse('$b/api/events/$id/'),
          headers: headers,
          body: jsonEncode({'status': status}),
        );
        _log('[$b] -> ${resp.statusCode}');
        break;
      } catch (e) {
        _log('[$b] error: $e');
      }
    }
    return resp != null && resp.statusCode == 200;
  }

  /// Convenience alias used by the Task Manager code.
  Future<bool> updateEventStatus(int id, String status) =>
      updateStatus(id: id, status: status);
}
