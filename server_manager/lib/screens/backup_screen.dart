import 'dart:io';
import 'package:flutter/material.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _isLoading = false;
  String _statusMessage = '';

  void _setStatus(String message) {
    if (mounted) {
      setState(() => _statusMessage = message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _exportUsersToExcel() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 1)); // Simulate API call / DB query
    try {
      final defaultDir = Directory(r'C:\iSmart\data\backups');
      if (!await defaultDir.exists()) await defaultDir.create(recursive: true);
      
      final file = File(r'C:\iSmart\data\backups\Users_Backup.csv');
      await file.writeAsString("ID,Name,Username,Department,Role\n1,Admin,admin,IT,Administrator\n2,Yousef,yousef,IT,User\n");
      _setStatus('Users exported to: ${file.path}');
    } catch (e) {
      _setStatus('Error exporting users: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _exportDepartmentsToExcel() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 1));
    try {
      final defaultDir = Directory(r'C:\iSmart\data\backups');
      if (!await defaultDir.exists()) await defaultDir.create(recursive: true);
      
      final file = File(r'C:\iSmart\data\backups\Departments_Backup.csv');
      await file.writeAsString("ID,Department Name,Manager\n1,IT,Admin\n2,Sales,Ahmed\n");
      _setStatus('Departments exported to: ${file.path}');
    } catch (e) {
      _setStatus('Error exporting departments: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _backupDatabase() async {
    setState(() => _isLoading = true);
    try {
      final backupDir = r'C:\iSmart\data\backups\db_backup_' + DateTime.now().millisecondsSinceEpoch.toString();
      final res = await Process.run('powershell', ['-Command', 'mongodump --uri="mongodb://127.0.0.1:27017/ismart" --out="$backupDir"']);
      if (res.exitCode == 0) {
        _setStatus('Database backup created at: $backupDir');
      } else {
        _setStatus('Failed to backup DB. Ensure mongodump is installed.');
      }
    } catch (e) {
      _setStatus('Error running DB backup: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _backupFiles() async {
    setState(() => _isLoading = true);
    try {
      final uploadsDir = r'C:\iSmart\data\uploads';
      final backupFile = r'C:\iSmart\data\backups\files_backup_' + DateTime.now().millisecondsSinceEpoch.toString() + '.zip';
      
      final res = await Process.run('powershell', ['-Command', 'Compress-Archive -Path "$uploadsDir\*" -DestinationPath "$backupFile"']);
      if (res.exitCode == 0) {
        _setStatus('Files backup created at: $backupFile');
      } else {
        _setStatus('Failed to backup files (Maybe directory is empty).');
      }
    } catch (e) {
      _setStatus('Error running files backup: $e');
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
          const Text(
            'Backup & Restore System',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Export your data to Excel (CSV), backup the entire database, or backup chat files.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          if (_isLoading)
            const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                _buildBackupSection(
                  'Data Export (Excel/CSV)',
                  'Export or import specific table data.',
                  [
                    _buildActionButton(Icons.people, 'Export Users', _exportUsersToExcel, Colors.blue),
                    _buildActionButton(Icons.business, 'Export Departments', _exportDepartmentsToExcel, Colors.blue),
                    _buildActionButton(Icons.upload, 'Import Data (Restore)', () => _setStatus('Select CSV file to import...'), Colors.orange),
                  ],
                ),
                const SizedBox(height: 24),
                _buildBackupSection(
                  'Database Backup',
                  'Create a full snapshot of the MongoDB database.',
                  [
                    _buildActionButton(Icons.storage, 'Full DB Backup', _backupDatabase, Colors.green),
                    _buildActionButton(Icons.restore, 'Restore DB', () => _setStatus('Select dump folder to restore...'), Colors.orange),
                  ],
                ),
                const SizedBox(height: 24),
                _buildBackupSection(
                  'Files & Chat History Backup',
                  'Backup all user uploads, attachments, and files.',
                  [
                    _buildActionButton(Icons.folder_zip, 'Backup All Files', _backupFiles, Colors.purple),
                    _buildActionButton(Icons.settings_backup_restore, 'Restore Files', () => _setStatus('Select zip file to restore...'), Colors.orange),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupSection(String title, String subtitle, List<Widget> buttons) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: buttons,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onPressed, Color color) {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : onPressed,
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }
}
