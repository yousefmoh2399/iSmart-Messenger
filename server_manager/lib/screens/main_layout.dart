import 'dart:io';
import 'package:flutter/material.dart';
import 'general_screen.dart';
import 'services_screen.dart';
import 'departments_screen.dart';
import 'users_screen.dart';
import 'backup_screen.dart';
import 'logs_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  bool _isBackendRunning = false;
  bool _isChecking = false;

  final List<Widget> _screens = [
    const GeneralScreen(),
    const ServicesScreen(),
    const DepartmentsScreen(),
    const UsersScreen(),
    const BackupScreen(),
    const LogsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _checkBackendStatus();
  }

  Future<void> _checkBackendStatus() async {
    setState(() => _isChecking = true);
    try {
      final res = await Process.run('powershell', [
        '-Command',
        'Get-Service iSmartBackend -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status'
      ]);
      final status = res.stdout.toString().trim();
      setState(() {
        _isBackendRunning = (status == 'Running');
      });
    } catch (_) {
      setState(() => _isBackendRunning = false);
    }
    setState(() => _isChecking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: Row(
          children: [
            TextButton.icon(
              icon: _isChecking 
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              label: const Text("Refresh Status"),
              style: TextButton.styleFrom(foregroundColor: Colors.black87),
              onPressed: _checkBackendStatus,
            ),
            const VerticalDivider(width: 20, thickness: 1),
            Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: _isBackendRunning ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isBackendRunning ? "Server Status: Running" : "Server Status: Stopped",
                  style: TextStyle(fontSize: 14, color: _isBackendRunning ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade300, height: 1.0),
        ),
      ),
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 90,
            color: const Color(0xFF333333),
            child: ListView(
              children: [
                _buildNavItem(0, Icons.settings, 'General'),
                _buildNavItem(1, Icons.computer, 'Services'),
                _buildNavItem(2, Icons.business, 'Departments'),
                _buildNavItem(3, Icons.people, 'Users'),
                _buildNavItem(4, Icons.backup, 'Backup'),
                _buildNavItem(5, Icons.terminal, 'Logs'),
              ],
            ),
          ),
          // Main Area
          Expanded(
            child: Container(
              color: Colors.grey.shade50,
              child: _screens[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        color: isSelected ? Colors.grey.shade800 : Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

