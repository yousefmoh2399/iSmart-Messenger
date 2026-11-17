import 'package:flutter/material.dart';

class DepartmentsScreen extends StatelessWidget {
  const DepartmentsScreen({super.key});

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
                'Departments Management',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Add Department'),
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
                      DataColumn(label: Text('ID', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Department Name', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Manager', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Members', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: [
                      _buildMockRow('1', 'IT Department', 'Admin', '12', context),
                      _buildMockRow('2', 'Human Resources', 'Sarah', '4', context),
                      _buildMockRow('3', 'Sales', 'Ahmed', '8', context),
                      _buildMockRow('4', 'Marketing', 'Mona', '5', context),
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

  DataRow _buildMockRow(String id, String name, String manager, String members, BuildContext context) {
    return DataRow(
      cells: [
        DataCell(Text(id)),
        DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w500))),
        DataCell(Text(manager)),
        DataCell(Text(members)),
        DataCell(Row(
          children: [
            IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () {}),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () {}),
          ],
        )),
      ],
    );
  }
}
