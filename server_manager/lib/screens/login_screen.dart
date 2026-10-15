import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'main_layout.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    String expectedUser = 'admin';
    String expectedPass = 'admin';

    try {
      final possiblePaths = [
        r'C:\ProgramData\iSmart\config.json',
        r'C:\iSmart\data\config.json',
        r'D:\iSmart\data\config.json',
      ];
      
      File? configFile;
      for (final path in possiblePaths) {
        final f = File(path);
        if (await f.exists()) {
          configFile = f;
          break;
        }
      }

      if (configFile != null) {
        final content = await configFile.readAsString();
        final json = jsonDecode(content);
        if (json['BOOTSTRAP_ADMIN_USERNAME'] != null && json['BOOTSTRAP_ADMIN_USERNAME'].toString().isNotEmpty) {
          expectedUser = json['BOOTSTRAP_ADMIN_USERNAME'];
        }
        if (json['BOOTSTRAP_ADMIN_PASSWORD'] != null && json['BOOTSTRAP_ADMIN_PASSWORD'].toString().isNotEmpty) {
          expectedPass = json['BOOTSTRAP_ADMIN_PASSWORD'];
        }
      }
    } catch (e) {
      // Ignore and use default
    }

    if (_usernameController.text == expectedUser && _passwordController.text == expectedPass) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainLayout()),
        );
      }
    } else {
      setState(() {
        _errorMessage = 'Invalid username or password';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(40.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security, size: 48, color: Color(0xFF333333)),
              const SizedBox(height: 16),
              const Text(
                'iSmart Server Manager',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to manage the backend server',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF333333),
                  ),
                  child: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
