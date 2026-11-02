import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const ServerManagerApp());
}

class ServerManagerApp extends StatelessWidget {
  const ServerManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iSmart Server Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Segoe UI',
        useMaterial3: false,
      ),
      home: const LoginScreen(),
    );
  }
}

