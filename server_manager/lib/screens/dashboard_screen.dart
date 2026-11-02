import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double _cpuUsage = 0.0;
  double _ramUsageMB = 0.0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startSimulatedMetrics(); // Replace with actual metrics API when ready
  }

  void _startSimulatedMetrics() {
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _cpuUsage = 2.0 + (DateTime.now().millisecond % 5);
          _ramUsageMB = 120.0 + (DateTime.now().millisecond % 15);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Server Dashboard',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Live monitoring and analytics for your iSmart Backend.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              _buildStatCard('Active Users (Online)', '42', Icons.people, Colors.blue),
              const SizedBox(width: 16),
              _buildStatCard('Messages Today', '1,248', Icons.message, Colors.purple),
              const SizedBox(width: 16),
              _buildStatCard('Database Size', '1.4 GB', Icons.storage, Colors.orange),
              const SizedBox(width: 16),
              _buildStatCard('Files & Uploads', '12.8 GB', Icons.folder, Colors.green),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'System Resources',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildResourceMeter('CPU Usage', '$_cpuUsage %', _cpuUsage / 100)),
              const SizedBox(width: 32),
              Expanded(child: _buildResourceMeter('Memory (RAM)', '${_ramUsageMB.toStringAsFixed(1)} MB', _ramUsageMB / 1024)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 16),
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceMeter(String label, String value, double percentage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: percentage.clamp(0.0, 1.0),
          backgroundColor: Colors.grey.shade200,
          color: percentage > 0.8 ? Colors.red : Colors.blue,
          minHeight: 8,
        ),
      ],
    );
  }
}
