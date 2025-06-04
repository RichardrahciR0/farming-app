import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../globals.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _logout(BuildContext context) async {
    final storage = FlutterSecureStorage();

    await storage.delete(key: 'access');
    await storage.delete(key: 'refresh');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Logged out successfully")),
    );

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login',
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.green[700],
        title: const Text('Profile'),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        children: [
          Container(
            color: Colors.green[700],
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.black12,
                  child: Icon(Icons.person, size: 60),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    // TODO: Implement Edit Profile functionality
                  },
                  child: const Text("Edit Profile"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          _buildSection("Mimi Headline", [
            _buildListItem(context, "Popular"),
            _buildListItem(context, "Trending"),
            _buildListItem(context, "Today"),
          ]),

          _buildSection("Content", [
            _buildListItem(context, "Favourite", icon: Icons.favorite_border),
            _buildListItem(context, "Download", icon: Icons.download),
          ]),

          _buildSection("Preferences", [
            _buildListItem(context, "Language", icon: Icons.language),

            ValueListenableBuilder<bool>(
              valueListenable: isDarkMode,
              builder: (context, value, _) {
                return SwitchListTile(
                  title: const Text("Dark Mode"),
                  secondary: const Icon(Icons.dark_mode),
                  value: value,
                  onChanged: (val) {
                    isDarkMode.value = val;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(val ? "Dark Mode On" : "Dark Mode Off")),
                    );
                  },
                );
              },
            ),

            _buildListItem(context, "Only Download via Wifi", icon: Icons.wifi),

            ValueListenableBuilder<bool>(
              valueListenable: isOfflineMode,
              builder: (context, value, _) {
                return SwitchListTile(
                  title: const Text("Force Offline Mode"),
                  secondary: const Icon(Icons.wifi_off),
                  value: value,
                  onChanged: (val) {
                    isOfflineMode.value = val;
                    final status = val ? "Offline" : "Online";
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Switched to $status Mode")),
                    );
                  },
                );
              },
            ),
          ]),

          const SizedBox(height: 16),

          /// ✅ Secure Log Out Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 100.0),
            child: ElevatedButton(
              onPressed: () => _logout(context),
              child: const Text("Log out"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[400],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Changes saved!")),
                );
              },
              child: const Text("Save"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: Colors.grey[200],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildListItem(BuildContext context, String text, {IconData? icon}) {
    return ListTile(
      leading: icon != null ? Icon(icon) : null,
      title: Text(text),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Tapped on $text")),
        );
      },
    );
  }
}
