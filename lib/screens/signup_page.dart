import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  bool _isLoading = false;

  Future<void> _register() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final rePassword = confirmPasswordController.text.trim();

    if (email.isEmpty || password.isEmpty || rePassword.isEmpty) {
      _showDialog("All fields are required.");
      return;
    }

    if (password != rePassword) {
      _showDialog("Passwords do not match.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('http://192.168.1.101:8000/api/auth/users/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          're_password': rePassword,
        }),
      ).timeout(const Duration(seconds: 10));

      setState(() => _isLoading = false);

      if (response.statusCode == 201) {
        _showDialog("Registration successful! You can now log in.", redirect: true);
      } else {
        final errorData = jsonDecode(response.body);
        _showDialog("Error (${response.statusCode}): ${errorData.toString()}");
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showDialog("Connection failed. Please check your server and try again.");
    }
  }

  void _showDialog(String message, {bool redirect = false}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Sign Up"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (redirect) Navigator.pop(context); // Go back to login
            },
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Create an Account', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: emailController, decoration: const InputDecoration(hintText: 'Email')),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Password'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Confirm Password'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _register,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Register'),
            )
          ],
        ),
      ),
    );
  }
}
