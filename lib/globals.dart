import 'package:flutter/material.dart';

/// Global theme toggle
final ValueNotifier<bool> isDarkMode = ValueNotifier(false);

/// Global Wi-Fi only / offline mode toggle
final ValueNotifier<bool> isOfflineMode = ValueNotifier(false);
