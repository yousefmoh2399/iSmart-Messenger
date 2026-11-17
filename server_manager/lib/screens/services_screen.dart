import 'dart:io';
import 'package:flutter/material.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  bool _mongoRunning = false;
  bool _redisRunning = false;
  bool _dockerRunning = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkServices();
  }

  Future<void> _checkServices() async {
    setState(() => _isLoading = true);
    
    // Check Mongo
    try {
      final mongoRes = await Process.run('powershell', ['-Command', 'Get-Service MongoDB -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status']);
      _mongoRunning = mongoRes.stdout.toString().trim() == 'Running';
    } catch (_) {
      _mongoRunning = false;
    }

    // Check Redis
    try {
      final redisRes = await Process.run('powershell', ['-Command', 'Get-Service Redis -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status']);
      _redisRunning = redisRes.stdout.toString().trim() == 'Running';
    } catch (_) {
      _redisRunning = false;
    }

    // Check Docker
    try {
      final dockerRes = await Process.run('docker', ['info']);
      _dockerRunning = dockerRes.exitCode == 0;
    } catch (_) {
      _dockerRunning = false;
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Backend Dependencies'),
          _buildServiceRow(
            'MongoDB Database',
            _mongoRunning,
            onStart: () => _runServiceCommand('Start-Service MongoDB'),
            onStop: () => _runServiceCommand('Stop-Service MongoDB'),
          ),
          _buildServiceRow(
            'Redis Cache',
            _redisRunning,
            onStart: () => _runServiceCommand('Start-Service Redis'),
            onStop: () => _runServiceCommand('Stop-Service Redis'),
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('Container Services'),
          _buildServiceRow(
            'Docker Desktop Engine',
            _dockerRunning,
            onStart: null, // Docker requires manual GUI start typically
            onStop: null,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: Colors.black87),
        ),
        const Divider(height: 20, thickness: 1),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildServiceRow(String name, bool isRunning, {VoidCallback? onStart, VoidCallback? onStop}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: isRunning ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            isRunning ? 'Running' : 'Stopped',
            style: TextStyle(
              color: isRunning ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 24),
          if (onStart != null && onStop != null) ...[
            OutlinedButton(
              onPressed: isRunning ? null : onStart,
              child: const Text('Start'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: !isRunning ? null : onStop,
              child: const Text('Stop'),
            ),
          ] else ...[
            const Text('(Managed Externally)', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
          ]
        ],
      ),
    );
  }

  Future<void> _runServiceCommand(String command) async {
    setState(() => _isLoading = true);
    try {
      final res = await Process.run('powershell', ['-Command', command]);
      if (res.exitCode != 0) {
        throw Exception(res.stderr);
      }
      await Future.delayed(const Duration(seconds: 1));
      await _checkServices();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e\nRun application as Administrator.')),
        );
      }
    }
  }
}
