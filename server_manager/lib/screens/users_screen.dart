import 'package:flutter/material.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

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
                'Users Management',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import from AD / LDAP'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add User'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF333333)),
                  ),
                ],
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
                      DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Username', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Department', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: [
                      _buildMockRow('Admin User', 'admin', 'IT Department', 'Administrator', true),
                      _buildMockRow('Yousef', 'yousef', 'IT Department', 'User', true),
                      _buildMockRow('Ahmed Ali', 'ahmed', 'Sales', 'User', true),
                      _buildMockRow('Mona', 'mona', 'Marketing', 'User', false),
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

  DataRow _buildMockRow(String name, String username, String dept, String role, bool isActive) {
    return DataRow(
      cells: [
        DataCell(Row(
          children: [
            const CircleAvatar(radius: 12, backgroundColor: Colors.blue, child: Icon(Icons.person, size: 16, color: Colors.white)),
            const SizedBox(width: 12),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        )),
        DataCell(Text(username)),
        DataCell(Text(dept)),
        DataCell(Text(role)),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? Colors.green.shade100 : Colors.red.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            isActive ? 'Active' : 'Disabled',
            style: TextStyle(color: isActive ? Colors.green.shade700 : Colors.red.shade700, fontSize: 12),
          ),
        )),
        DataCell(Row(
          children: [
            IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () {}),
            IconButton(icon: const Icon(Icons.block, color: Colors.orange, size: 20), onPressed: () {}),
          ],
        )),
      ],
    );
  }
}
