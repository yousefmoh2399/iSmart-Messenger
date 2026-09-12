const fs = require("fs");
const path = require("path");

const filePath = path.join(__dirname, "../../desktop_app/lib/features/printers/presentation/printer_monitoring_screen.dart");

let content = fs.readFileSync(filePath, "utf8");

// 1. Fix Colors.white90 -> Colors.white70
content = content.replace(/Colors\.white90/g, "Colors.white70");

// 2. Fix prefer_adjacent_string_concatenation
content = content.replace(
  "'هذه الطابعة مزودة بمسح ضوئي متقدم (سكانر). لقد تم مسح ضوئي لـ ' +\n                        '\\${(printer.lifetimeCounters['scanPages'] ?? 0).toStringAsFixed(0)} ' +\n                        'صفحة إجمالاً، ومسح ' +\n                        '\\${(printer.counters['scanPages'] ?? 0).toStringAsFixed(0)} ' +\n                        'صفحة في الفترة الحالية عبر وحدة تغذية المستندات (ADF) أو لوحة المسح الزجاجية المسطحة.'",
  "'هذه الطابعة مزودة بمسح ضوئي متقدم (سكانر). لقد تم مسح ضوئي لـ '\n                        '\\${(printer.lifetimeCounters['scanPages'] ?? 0).toStringAsFixed(0)} '\n                        'صفحة إجمالاً، ومسح '\n                        '\\${(printer.counters['scanPages'] ?? 0).toStringAsFixed(0)} '\n                        'صفحة في الفترة الحالية عبر وحدة تغذية المستندات (ADF) أو لوحة المسح الزجاجية المسطحة.'"
);

// 3. Fix FontWeight.black -> FontWeight.w900
content = content.replace(/FontWeight\.black/g, "FontWeight.w900");

// 4. Fix withOpacity -> withValues(alpha: ...)
content = content.replace(/\.withOpacity\((.*?)\)/g, ".withValues(alpha: $1)");

// 5. Fix colors.divider -> theme.dividerColor or colors.outlineVariant
// We will replace specific lines or patterns:
content = content.replace(
  "border: Border.all(color: colors.divider.withValues(alpha: 0.15)),",
  "border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),"
);
content = content.replace(
  "color: colors.divider.withValues(alpha: 0.15),",
  "color: theme.dividerColor.withValues(alpha: 0.15),"
);
content = content.replace(
  "color: colors.divider.withValues(alpha: 0.1),",
  "color: theme.dividerColor.withValues(alpha: 0.1),"
);
content = content.replace(
  "border: Border.all(color: colors.divider.withValues(alpha: 0.3)),",
  "border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),"
);

// Let's write back the file
fs.writeFileSync(filePath, content, "utf8");
console.log("Successfully fixed UI compile errors!");
