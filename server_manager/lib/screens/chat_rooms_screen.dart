import 'package:flutter/material.dart';

class ChatRoomsScreen extends StatelessWidget {
  const ChatRoomsScreen({super.key});

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
                'Chat Rooms Management',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add_comment),
                label: const Text('Create Global Room'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF333333)),
              )
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView(
                children: [
                  DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                    columns: const [
                      DataColumn(label: Text('Room Name', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Creator', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Members', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: [
                      _buildMockRow('General Announcements', 'Admin', 'Public', 'All Users', true),
                      _buildMockRow('IT Support', 'Admin', 'Private', '12', false),
                      _buildMockRow('Sales Updates', 'Ahmed', 'Private', '8', false),
                    ],
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  DataRow _buildMockRow(String name, String creator, String type, String members, bool isGlobal) {
    return DataRow(
      cells: [
        DataCell(Row(
          children: [
            Icon(isGlobal ? Icons.public : Icons.lock, size: 16, color: Colors.blueGrey),
            const SizedBox(width: 8),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        )),
        DataCell(Text(creator)),
        DataCell(Text(type)),
        DataCell(Text(members)),
        DataCell(Row(
          children: [
            IconButton(icon: const Icon(Icons.group_add, color: Colors.blue, size: 20), onPressed: () {}, tooltip: 'Manage Members'),
            IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20), onPressed: () {}, tooltip: 'Delete Room'),
          ],
        )),
      ],
    );
  }
}
