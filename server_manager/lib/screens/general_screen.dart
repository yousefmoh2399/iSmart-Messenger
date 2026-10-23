import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class GeneralScreen extends StatefulWidget {
  const GeneralScreen({super.key});

  @override
  State<GeneralScreen> createState() => _GeneralScreenState();
}

class _GeneralScreenState extends State<GeneralScreen> {
  final TextEditingController _portController = TextEditingController(text: '7070');
  final TextEditingController _corsController = TextEditingController(text: '*');
  final TextEditingController _mongoUriController = TextEditingController(text: 'mongodb://127.0.0.1:27017/ismart');
  final TextEditingController _redisHostController = TextEditingController(text: '127.0.0.1');

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<File?> _getConfigFile() async {
    final possiblePaths = [
      r'C:\ProgramData\iSmart\config.json',
      r'C:\iSmart\data\config.json',
      r'D:\iSmart\data\config.json',
    ];
    for (final path in possiblePaths) {
      final f = File(path);
      if (await f.exists()) return f;
    }
    return null;
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final file = await _getConfigFile();
      if (file != null) {
        final content = await file.readAsString();
        final json = jsonDecode(content);
        
        setState(() {
          _portController.text = json['PORT']?.toString() ?? '7070';
          _corsController.text = json['CORS_ORIGIN'] ?? '*';
          _mongoUriController.text = json['MONGODB_URI'] ?? 'mongodb://127.0.0.1:27017/ismart';
          _redisHostController.text = json['REDIS_HOST'] ?? '127.0.0.1';
        });
      }
    } catch (e) {
      // Ignore for now
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveConfig() async {
    setState(() => _isLoading = true);
    try {
      final file = await _getConfigFile();
      if (file == null) {
        throw Exception('Config file not found in any standard location.');
      }
      Map<String, dynamic> json = {};
      json = jsonDecode(await file.readAsString());
      
      json['PORT'] = _portController.text;
      json['CORS_ORIGIN'] = _corsController.text;
      json['MONGODB_URI'] = _mongoUriController.text;
      json['REDIS_HOST'] = _redisHostController.text;

      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving config: $e')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveAndRestart() async {
    await _saveConfig();
    try {
      await Process.run('powershell', ['-Command', 'Restart-Service', 'iSmartBackend']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service Restarted Successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to restart service: $e\nMake sure to run as Administrator.')),
        );
      }
    }
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
          _buildSectionHeader('Server Configuration'),
          _buildTextField('API Port', _portController),
          _buildTextField('CORS Origin', _corsController),
          
          const SizedBox(height: 32),
          _buildSectionHeader('Database & Cache'),
          _buildTextField('MongoDB URI', _mongoUriController),
          _buildTextField('Redis Host', _redisHostController),

          const SizedBox(height: 48),
          Row(
            children: [
              ElevatedButton(
                onPressed: _saveConfig,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
                child: const Text('Save'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _saveAndRestart,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  backgroundColor: Colors.blue.shade700,
                ),
                child: const Text('Save & Restart Server'),
              ),
            ],
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

  Widget _buildTextField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            flex: 2,
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
