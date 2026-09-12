const fs = require("fs");
const path = require("path");

const filePath = path.join(__dirname, "../../desktop_app/lib/features/printers/presentation/printer_monitoring_screen.dart");

let content = fs.readFileSync(filePath, "utf8");

// 1. Fix _DetailSection theme
content = content.replace(
  `  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.15),
        ),`,
  `  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.15),
        ),`
);

// 2. Fix _buildMetricCard theme
content = content.replace(
  `  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required num value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    final colors = Theme.of(context).colorScheme;`,
  `  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required num value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;`
);

// 3. Fix _buildTonerTube theme
content = content.replace(
  `  Widget _buildTonerTube(
    BuildContext context, {
    required String colorName,
    required String colorCode,
    required Object? value,
    required Color fillColor,
  }) {
    num? number;`,
  `  Widget _buildTonerTube(
    BuildContext context, {
    required String colorName,
    required String colorCode,
    required Object? value,
    required Color fillColor,
  }) {
    final theme = Theme.of(context);
    num? number;`
);

// 4. Fix _StatsGrid itemBuilder theme
content = content.replace(
  `      itemBuilder: (context, index) {
        final item = items[index];
        final colors = Theme.of(context).colorScheme;`,
  `      itemBuilder: (context, index) {
        final item = items[index];
        final theme = Theme.of(context);
        final colors = theme.colorScheme;`
);

// 5. Fix unused colors variable in _PrinterDetailsPanel
content = content.replace(
  `  @override
  Widget build(BuildContext context) {
    final statusColor = _printerStatusColor(printer.status);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasColor = printer.tonerLevels['cyan'] != null;`,
  `  @override
  Widget build(BuildContext context) {
    final statusColor = _printerStatusColor(printer.status);
    final theme = Theme.of(context);
    final hasColor = printer.tonerLevels['cyan'] != null;`
);

// 6. Fix String concatenation with '+'
content = content.replace(
  `'هذه الطابعة مزودة بمسح ضوئي متقدم (سكانر). لقد تم مسح ضوئي لـ ' +
                        '\${(printer.lifetimeCounters['scanPages'] ?? 0).toStringAsFixed(0)} ' +
                        'صفحة إجمالاً، ومسح ' +
                        '\${(printer.counters['scanPages'] ?? 0).toStringAsFixed(0)} ' +
                        'صفحة في الفترة الحالية عبر وحدة تغذية المستندات (ADF) أو لوحة المسح الزجاجية المسطحة.',`,
  `'هذه الطابعة مزودة بمسح ضوئي متقدم (سكانر). لقد تم مسح ضوئي لـ '
                        '\${(printer.lifetimeCounters['scanPages'] ?? 0).toStringAsFixed(0)} '
                        'صفحة إجمالاً، ومسح '
                        '\${(printer.counters['scanPages'] ?? 0).toStringAsFixed(0)} '
                        'صفحة في الفترة الحالية عبر وحدة تغذية المستندات (ADF) أو لوحة المسح الزجاجية المسطحة.',`
);

fs.writeFileSync(filePath, content, "utf8");
console.log("Successfully ran final error fixes on printer_monitoring_screen.dart!");
