import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'screens/home_page.dart' show HomePage;
import 'screens/map_page.dart' show MapPage;
import 'screens/task_page.dart' show TaskPage;
import 'screens/add_task.dart' show AddTaskPage;
import 'screens/settings_page.dart' show SettingsPage;
import 'screens/notifications_page.dart' show NotificationsPage;
import 'screens/cropdata.dart' show CropDataPage;
import 'screens/calender_page.dart' show CalendarPage; // <-- If your class is CalenderPage, change this line to: show CalenderPage;
import 'screens/weather_page.dart' show WeatherPage;
import 'screens/mapping.dart' show MappingPage;
import 'screens/login_page.dart' show LoginScreen;
import 'screens/signup_page.dart' show SignUpScreen;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = FlutterSecureStorage();
  final token = await storage.read(key: 'access');
  final initialRoute = token != null ? '/' : '/login';
  runApp(OrefoxApp(initialRoute: initialRoute));
}

class OrefoxApp extends StatelessWidget {
  final String initialRoute;
  const OrefoxApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orefox Farm Planting App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: const Color(0xFFF7F8F9),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0.5,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 14, color: Colors.black87),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      initialRoute: initialRoute,
      routes: {
        '/': (ctx) => HomePage(),
        '/login': (ctx) => const LoginScreen(),
        '/signup': (ctx) => const SignUpScreen(),
        '/map': (ctx) => MapPage(),
        '/mapping': (ctx) => MappingPage(),
        '/tasks': (ctx) => TaskPage(),
        '/add': (ctx) => AddTaskPage(),
        '/settings': (ctx) => SettingsPage(),
        '/notifications': (ctx) => NotificationsPage(),
        '/cropdata': (ctx) => CropDataPage(),
        '/calendar': (ctx) => CalendarPage(), // <-- if your class is CalenderPage, change to CalenderPage()
        '/weather': (ctx) => WeatherPage(),
      },
    );
  }
}
