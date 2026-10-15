import 'package:flutter/material.dart';

class PoliciesScreen extends StatelessWidget {
  const PoliciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'App Policies & Settings',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          _buildCard(
            title: 'File Sharing Limits',
            icon: Icons.folder,
            children: [
              SwitchListTile(
                title: const Text('Enable File Sharing'),
                subtitle: const Text('Allow users to upload and share files.'),
                value: true,
                onChanged: (v) {},
              ),
              const SizedBox(height: 16),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Max File Size (MB)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildCard(
            title: 'Data Retention Policy',
            icon: Icons.delete_sweep,
            children: [
              SwitchListTile(
                title: const Text('Auto-delete old messages'),
                subtitle: const Text('Automatically remove messages older than specified days.'),
                value: false,
                onChanged: (v) {},
              ),
              const SizedBox(height: 16),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Retention Period (Days)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildCard(
            title: 'Mobile Push Notifications',
            icon: Icons.notifications_active,
            children: [
              const Text('Upload your Firebase Service Account JSON to enable push notifications on mobile devices.'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.upload),
                label: const Text('Upload firebase-adminsdk.json'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(height: 32),
          ...children,
        ],
      ),
    );
  }
}
