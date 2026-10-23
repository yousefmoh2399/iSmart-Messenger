import 'package:flutter/material.dart';

class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'App Updates & Releases',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload new versions of the Windows or Android app to distribute them to all users automatically.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          _buildCard(
            title: 'Windows Desktop Client',
            icon: Icons.computer,
            version: 'v1.0.5',
            releaseDate: '2026-10-01',
          ),
          const SizedBox(height: 24),
          _buildCard(
            title: 'Android Mobile Client',
            icon: Icons.android,
            version: 'v1.0.2',
            releaseDate: '2026-09-28',
          ),
          const SizedBox(height: 24),
          _buildCard(
            title: 'iOS Mobile Client',
            icon: Icons.apple,
            version: 'v1.0.1',
            releaseDate: '2026-09-15',
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required String title, required IconData icon, required String version, required String releaseDate}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 40, color: Colors.blueGrey),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Current Release: $version (Published on $releaseDate)', style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.upload),
            label: const Text('Upload New Version'),
          ),
        ],
      ),
    );
  }
}
