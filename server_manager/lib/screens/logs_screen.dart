import 'dart:io';
import 'package:flutter/material.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _logs = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true);
    try {
      final logFile = File(r'C:\iSmart\data\logs\stdout.log');
      if (await logFile.exists()) {
        final lines = await logFile.readAsLines();
        // Get last 100 lines
        final recentLines = lines.length > 100 ? lines.sublist(lines.length - 100) : lines;
        setState(() {
          _logs = recentLines.join('\n');
        });
      } else {
        setState(() {
          _logs = 'Log file not found at ${logFile.path}';
        });
      }
    } catch (e) {
      setState(() {
        _logs = 'Error reading logs: $e';
      });
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Server Logs (Diagnostics)',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: _fetchLogs,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Logs'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF333333)),
              )
            ],
          ),
          const SizedBox(height: 32),
          if (_isLoading) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _logs.isEmpty ? 'No logs available.' : _logs,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    color: Colors.greenAccent,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
