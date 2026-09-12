const fs = require("fs");
const path = require("path");

const filePath = path.join(__dirname, "../../desktop_app/lib/features/printers/presentation/printer_monitoring_screen.dart");

let content = fs.readFileSync(filePath, "utf8");

// 1. Delete unused variable media
content = content.replace("    final media = _asListOfMaps(usage['media']);\n", "");

// 2. Fix colors.divider in _buildTonerTube
content = content.replace(
  "color: isLow ? Colors.red.withValues(alpha: 0.5) : colors.divider.withValues(alpha: 0.15),",
  "color: isLow ? Colors.red.withValues(alpha: 0.5) : theme.dividerColor.withValues(alpha: 0.15),"
);

// 3. Fix colors.divider in mono label border
content = content.replace(
  "border: Border.all(colors.divider.withValues(alpha: 0.15)),",
  "border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),"
);

// 4. Fix colors.divider in _StatsGrid
content = content.replace(
  "            border: Border.all(\n              color: colors.divider.withValues(alpha: 0.15),\n            ),",
  "            border: Border.all(\n              color: theme.dividerColor.withValues(alpha: 0.15),\n            ),"
);

// 5. Fix colors.divider in _PrinterTable separator
content = content.replace(
  "separatorBuilder: (_, __) => Divider(height: 1, color: colors.divider.withValues(alpha: 0.1)),",
  "separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.1)),"
);

// 6. Fix unused theme variable in _PrinterDetailsPanel
// We will replace:
//     final statusColor = _printerStatusColor(printer.status);
//     final theme = Theme.of(context);
//     final hasColor = printer.tonerLevels['cyan'] != null;
// with:
//     final statusColor = _printerStatusColor(printer.status);
//     final hasColor = printer.tonerLevels['cyan'] != null;
content = content.replace(
  `    final statusColor = _printerStatusColor(printer.status);
    final theme = Theme.of(context);
    final hasColor = printer.tonerLevels['cyan'] != null;`,
  `    final statusColor = _printerStatusColor(printer.status);
    final hasColor = printer.tonerLevels['cyan'] != null;`
);

fs.writeFileSync(filePath, content, "utf8");
console.log("Successfully ran second round of error fixes!");
