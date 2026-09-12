const fs = require("fs");
const path = require("path");

const filePath = path.join(__dirname, "../../desktop_app/lib/features/printers/presentation/printer_monitoring_screen.dart");

let content = fs.readFileSync(filePath, "utf8");

// 1. Fix unused colors in _buildMetricCard
content = content.replace(
  `  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required num value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;`,
  `  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required num value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    final theme = Theme.of(context);`
);

// 2. Fix redundant null comparison in _buildTonerTube
content = content.replace(
  "if (isLow && number != null) ...[",
  "if (isLow) ...["
);

// 3. Fix unused colors in _StatsGrid
content = content.replace(
  `      itemBuilder: (context, index) {
        final item = items[index];
        final theme = Theme.of(context);
        final colors = theme.colorScheme;`,
  `      itemBuilder: (context, index) {
        final item = items[index];
        final theme = Theme.of(context);`
);

// 4. Fix unused colors in _BranchPanel
content = content.replace(
  `  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Panel(`,
  `  @override
  Widget build(BuildContext context) {
    return _Panel(`
);

fs.writeFileSync(filePath, content, "utf8");
console.log("Successfully fixed UI warnings!");
