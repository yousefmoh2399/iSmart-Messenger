const fs = require("fs");
const path = require("path");

const filePath = path.join(__dirname, "../../desktop_app/lib/features/printers/presentation/printer_monitoring_screen.dart");

let content = fs.readFileSync(filePath, "utf8");

// Redesigned Block 1: PrinterDetailsScreen, _DetailSection, _StatusBadge, _TonerLine, _DetailDataTable, _StatsGrid, _BranchPanel, _PrinterTable
const newBlock1 = `class PrinterDetailsScreen extends ConsumerWidget {
  const PrinterDetailsScreen({super.key, required this.printer});

  final PrinterItem printer;

  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String done,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_fixText(done)),
        ));
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFDC2626),
            content: Text(error.toString()),
          ),
        );
    }
  }

  LinearGradient _printerStatusGradient(String status) {
    switch (status) {
      case 'online':
        return const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'warning':
        return const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFB45309)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'error':
        return const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'offline':
      default:
        return const LinearGradient(
          colors: [Color(0xFF64748B), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = _printerStatusColor(printer.status);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final extended = printer.extendedDetails;
    final product = _asMap(extended['product']);
    final usage = _asMap(extended['usage']);
    final supplies = _asListOfMaps(extended['supplies']);
    final media = _asListOfMaps(usage['media']);
    final events = _asListOfMaps(extended['events']);
    final jobs = _asListOfMaps(extended['jobs']);
    final rawKeyValues = _asListOfMaps(extended['rawKeyValues']);

    final hasColorToner = printer.tonerLevels['cyan'] != null ||
        printer.tonerLevels['magenta'] != null ||
        printer.tonerLevels['yellow'] != null;

    final hasScanner = (printer.lifetimeCounters['scanPages'] ?? 0) > 0 ||
        (printer.counters['scanPages'] ?? 0) > 0 ||
        printer.model.toLowerCase().contains('taskalfa') ||
        printer.model.toLowerCase().contains('mfp') ||
        printer.model.toLowerCase().contains('m479') ||
        printer.model.toLowerCase().contains('m227') ||
        printer.model.toLowerCase().contains('m428');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            elevation: 0,
            title: Text(
              printer.name.isEmpty ? printer.ipAddress : printer.name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => _runAction(
                  context,
                  ref,
                  () => ref
                      .read(printerControllerProvider.notifier)
                      .syncPrinter(printer.id),
                  'تمت مزامنة بيانات الطابعة وتحديث العدادات بنجاح.',
                ),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('مزامنة فورية'),
              ),
              TextButton.icon(
                onPressed: () => _runAction(
                  context,
                  ref,
                  () => ref
                      .read(printerRepositoryProvider)
                      .exportPrinterReport(printer.id),
                  'تم تصدير تقرير الطابعة بصيغة PDF بنجاح.',
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('تقرير PDF'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Beautiful gradient card at the top
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: _printerStatusGradient(printer.status),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.print_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            printer.name.isEmpty ? printer.ipAddress : printer.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.location_city_rounded, color: Colors.white70, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                printer.branchName,
                                style: const TextStyle(color: Colors.white90, fontSize: 14),
                              ),
                              const SizedBox(width: 16),
                              const Icon(Icons.settings_ethernet_rounded, color: Colors.white70, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                printer.ipAddress,
                                style: const TextStyle(color: Colors.white90, fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: Text(
                            _fixText(_printerStatus(printer.status)),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'الموديل: \${printer.model}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // TabBar navigation
              Container(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: colors.onPrimary,
                  unselectedLabelColor: colors.onSurfaceVariant,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  tabs: const [
                    Tab(text: 'العدادات والاستخدام'),
                    Tab(text: 'خراطيش الحبر والمستلزمات'),
                    Tab(text: 'تفاصيل الجهاز والشبكة'),
                    Tab(text: 'الصيانة وسجلات الأعطال'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tab content area
              SizedBox(
                height: 620,
                child: TabBarView(
                  children: [
                    // Tab 1: Usage
                    _buildUsageTab(context, hasScanner),
                    // Tab 2: Toner
                    _buildTonerTab(context, hasColorToner, supplies),
                    // Tab 3: Device Info
                    _buildDeviceInfoTab(context, product, usage),
                    // Tab 4: Maintenance & Jobs
                    _buildMaintenanceTab(context, events, jobs, rawKeyValues),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsageTab(BuildContext context, bool hasScanner) {
    return ListView(
      physics: const ClampingScrollPhysics(),
      children: [
        const Text(
          'عدادات صفحات عمر الطابعة الإجمالية والعداد الحالي للمراجعة:',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.2,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildMetricCard(
              context,
              title: 'إجمالي عدد الصفحات المطبوعة',
              value: printer.lifetimeCounters['totalPages'] ?? 0,
              subtitle: 'إجمالي صفحات العمر للجهاز',
              icon: Icons.description_rounded,
              iconColor: Colors.deepPurple,
            ),
            _buildMetricCard(
              context,
              title: 'العداد الحالي',
              value: printer.counters['totalPages'] ?? 0,
              subtitle: 'منذ آخر دورة صيانة أو تصفير',
              icon: Icons.onetwothree_rounded,
              iconColor: Colors.blue,
            ),
            _buildMetricCard(
              context,
              title: 'صفحات أحادية اللون (أسود)',
              value: printer.lifetimeCounters['monoPages'] ?? 0,
              subtitle: 'الصفحات المطبوعة باللون الأسود',
              icon: Icons.brightness_medium_rounded,
              iconColor: Colors.blueGrey,
            ),
            _buildMetricCard(
              context,
              title: 'صفحات ملونة (Color)',
              value: printer.lifetimeCounters['colorPages'] ?? 0,
              subtitle: 'الصفحات المطبوعة بالألوان كاملة',
              icon: Icons.color_lens_rounded,
              iconColor: Colors.orange,
            ),
            _buildMetricCard(
              context,
              title: 'طباعة على الوجهين (Duplex)',
              value: printer.lifetimeCounters['duplexPages'] ?? 0,
              subtitle: 'توفير الورق (وجهين تلقائياً)',
              icon: Icons.library_books_rounded,
              iconColor: Colors.indigo,
            ),
            _buildMetricCard(
              context,
              title: 'صفحات التصوير (Copy)',
              value: printer.lifetimeCounters['copyPages'] ?? 0,
              subtitle: 'المستندات المنسوخة عبر الماسح',
              icon: Icons.copy_rounded,
              iconColor: Colors.teal,
            ),
          ],
        ),
        const SizedBox(height: 20),
        
        // Scan Pages display block
        if (hasScanner) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.teal.withOpacity(0.25), width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.scanner_rounded, color: Colors.teal, size: 36),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إحصائيات الماسح الضوئي (Scanner)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'هذه الطابعة مزودة بمسح ضوئي متقدم (سكانر). لقد تم مسح ضوئي لـ ' +
                        '\${(printer.lifetimeCounters['scanPages'] ?? 0).toStringAsFixed(0)} ' +
                        'صفحة إجمالاً، ومسح ' +
                        '\${(printer.counters['scanPages'] ?? 0).toStringAsFixed(0)} ' +
                        'صفحة في الفترة الحالية عبر وحدة تغذية المستندات (ADF) أو لوحة المسح الزجاجية المسطحة.',
                        style: TextStyle(
                          color: Colors.teal.shade800,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.teal,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        (printer.lifetimeCounters['scanPages'] ?? 0).toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'عملية مسح',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.amber, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'هذا الجهاز مسجل كطابعة مستقلة ولا يحتوي على وحدة مسح ضوئي (سكانر) مدمجة.',
                    style: TextStyle(color: Colors.amber, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required num value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTonerTab(BuildContext context, bool hasColorToner, List<Map<String, dynamic>> supplies) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      physics: const ClampingScrollPhysics(),
      children: [
        const Text(
          'حالة خراطيش الحبر المتبقية ونسب الاستهلاك:',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 20),
        
        // CMYK cartridges container
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildTonerTube(
              context,
              colorName: 'أسود Black',
              colorCode: 'K',
              value: printer.tonerLevels['black'],
              fillColor: const Color(0xFF1E293B),
            ),
            if (hasColorToner) ...[
              _buildTonerTube(
                context,
                colorName: 'سماوي Cyan',
                colorCode: 'C',
                value: printer.tonerLevels['cyan'],
                fillColor: const Color(0xFF06B6D4),
              ),
              _buildTonerTube(
                context,
                colorName: 'أرجواني Magenta',
                colorCode: 'M',
                value: printer.tonerLevels['magenta'],
                fillColor: const Color(0xFFEC4899),
              ),
              _buildTonerTube(
                context,
                colorName: 'أصفر Yellow',
                colorCode: 'Y',
                value: printer.tonerLevels['yellow'],
                fillColor: const Color(0xFFEAB308),
              ),
            ] else ...[
              // Label for mono printers
              Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(colors.divider.withOpacity(0.15)),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.opacity_rounded, size: 48, color: Colors.blueGrey),
                    SizedBox(height: 12),
                    Text(
                      'طابعة أحادية اللون (Monochrome)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'هذا الطراز يدعم خرطوشة حبر سوداء واحدة فقط. خراطيش الألوان (سماوي، أرجواني، أصفر) غير مدعومة في الماكينة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),
        
        if (supplies.isNotEmpty) ...[
          const Divider(height: 32),
          const Text(
            'تفاصيل الخراطيش والمستلزمات المسترجعة من الطابعة:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 12),
          _DetailDataTable(
            columns: const [
              'الخرطوشة',
              'الحالة الحالية',
              'الرقم التسلسلي للقطعة',
              'النوع',
              'تاريخ التركيب أول مرة',
              'الصفحات المطبوعة',
            ],
            rows: supplies
                .take(15)
                .map(
                  (item) => [
                    _text(item['color']),
                    _text(item['status']),
                    _text(item['serialNumber']),
                    _text(item['type']),
                    _text(item['firstInstallDate']),
                    _text(item['pagesPrinted']),
                  ],
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildTonerTube(
    BuildContext context, {
    required String colorName,
    required String colorCode,
    required Object? value,
    required Color fillColor,
  }) {
    num? number;
    if (value is num) {
      number = value;
    } else {
      number = num.tryParse(value?.toString() ?? '');
    }

    final double level = number == null ? 0 : (number.clamp(0, 100) / 100).toDouble();
    final isLow = number != null && number < 15;
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLow ? Colors.red.withOpacity(0.5) : colors.divider.withOpacity(0.15),
          width: isLow ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            colorName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 16),
          // Cylinder visual representation
          Container(
            width: 50,
            height: 160,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.15),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.grey.shade400, width: 2),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Filled amount
                FractionallySizedBox(
                  heightFactor: level,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.only(
                        bottomLeft: const Radius.circular(23),
                        bottomRight: const Radius.circular(23),
                        topLeft: Radius.circular(level > 0.9 ? 23 : 0),
                        topRight: Radius.circular(level > 0.9 ? 23 : 0),
                      ),
                    ),
                  ),
                ),
                // Indicator Text
                Positioned(
                  top: 20,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: fillColor, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        colorCode,
                        style: TextStyle(
                          color: fillColor,
                          fontWeight: FontWeight.black,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            number == null ? 'غير متوفر' : '\${number.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isLow ? Colors.red : colors.onSurface,
            ),
          ),
          if (isLow && number != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'الحبر منخفض جداً',
                    style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceInfoTab(BuildContext context, Map<String, dynamic> product, Map<String, dynamic> usage) {
    return ListView(
      physics: const ClampingScrollPhysics(),
      children: [
        _DetailSection(
          title: 'معلومات تعريف الجهاز الأساسية:',
          children: [
            _InfoLine(label: 'اسم المنتج والماكينة', value: printer.model),
            _InfoLine(label: 'الرقم التسلسلي للمصنع', value: printer.serialNumber),
            _InfoLine(label: 'عنوان الشبكة IP Address', value: printer.ipAddress),
            _InfoLine(label: 'اسم المضيف Hostname', value: printer.hostname),
            _InfoLine(label: 'الشركة المصنعة (Vendor)', value: printer.vendor),
            _InfoLine(label: 'تاريخ ووقت المزامنة الأخيرة', value: _dateText(printer.lastSyncAt)),
          ],
        ),
        const SizedBox(height: 20),
        if (product.isNotEmpty) ...[
          _DetailSection(
            title: 'تفاصيل اللوحة والبرامج المثبتة (من صفحة الويب):',
            children: [
              ..._mapLines(product, const {
                'productName': 'اسم المنتج البديل',
                'productNumber': 'رقم الموديل الداخلي',
                'serviceId': 'معرف الصيانة الخاص',
                'firmwareVersion': 'إصدار نظام التشغيل الأساسي (Firmware)',
                'engineFirmware': 'البرنامج الثابت لمحرك الطباعة',
                'region': 'الدولة والمنطقة المعتمدة',
                'memoryTotalKb': 'إجمالي الذاكرة العشوائية المتاحة (KB)',
                'installedPersonalities': 'اللغات ولغات الوظائف المثبتة',
              }),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMaintenanceTab(
    BuildContext context,
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> jobs,
    List<Map<String, dynamic>> rawKeyValues,
  ) {
    return ListView(
      physics: const ClampingScrollPhysics(),
      children: [
        _DetailSection(
          title: 'حالة الصيانة الحالية ومعدلات الأخطاء:',
          children: [
            _DynamicLine(
              label: 'إجمالي انحشارات الورق (Paper Jams)',
              values: printer.maintenance,
              keyName: 'paperJams',
            ),
            _DynamicLine(
              label: 'رسائل الخطأ النشطة',
              values: printer.maintenance,
              keyName: 'errorMessages',
            ),
            _DynamicLine(
              label: 'التحذيرات النشطة',
              values: printer.maintenance,
              keyName: 'warnings',
            ),
          ],
        ),
        
        if (events.isNotEmpty) ...[
          const SizedBox(height: 20),
          _DetailSection(
            title: 'سجل الأحداث البرمجية والتحذيرات:',
            children: [
              _DetailDataTable(
                columns: const ['الكود المالي', 'النوع', 'التاريخ/الوقت', 'الدورات المطبوعة', 'الوصف والتفسير'],
                rows: events
                    .take(15)
                    .map(
                      (item) => [
                        _text(item['code']),
                        _text(item['type']),
                        _text(item['dateTime']),
                        _text(item['cycles']),
                        _text(item['description']),
                      ],
                    )
                    .toList(),
              ),
            ],
          ),
        ],

        if (jobs.isNotEmpty) ...[
          const SizedBox(height: 20),
          _DetailSection(
            title: 'آخر الوظائف التي قامت بها الطابعة:',
            children: [
              _DetailDataTable(
                columns: const ['اسم الوظيفة', 'اسم المستخدم المرسل', 'حالة الوظيفة', 'تاريخ الاستقبال'],
                rows: jobs
                    .take(15)
                    .map(
                      (item) => [
                        _text(item['name']),
                        _text(item['user']),
                        _text(item['status']),
                        _text(item['dateTime']),
                      ],
                    )
                    .toList(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.divider.withOpacity(0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _fixText(title),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _printerStatusColor(status);
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(
          _fixText(_printerStatus(status)),
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ),
    );
  }
}

class _TonerLine extends StatelessWidget {
  const _TonerLine({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    num? number;
    final raw = value;
    if (raw is num) {
      number = raw;
    } else {
      number = num.tryParse(raw?.toString() ?? '');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(_fixText(label))),
          Expanded(
            child: LinearProgressIndicator(
              value: number == null ? 0 : (number.clamp(0, 100) / 100),
              minHeight: 8,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            child: Text(number == null ? '-' : '\${number.toStringAsFixed(0)}%'),
          ),
        ],
      ),
    );
  }
}

class _DetailDataTable extends StatelessWidget {
  const _DetailDataTable({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text('-', style: TextStyle(color: Colors.grey)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(theme.colorScheme.surfaceContainerHighest.withOpacity(0.3)),
          headingRowHeight: 44,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 72,
          columns: [
            for (final column in columns)
              DataColumn(
                label: Text(
                  column,
                  style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.primary, fontSize: 13),
                ),
              ),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [
                  for (var index = 0; index < columns.length; index += 1)
                    DataCell(
                      SizedBox(
                        width: columns.length <= 2 ? 380 : 160,
                        child: Text(
                          index < row.length && row[index].trim().isNotEmpty
                              ? row[index]
                              : '-',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.totals});

  final Map<String, num> totals;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('الفروع النشطة', totals['branches'] ?? 0, Icons.account_tree_rounded, Colors.indigo),
      ('إجمالي الطابعات', totals['printers'] ?? 0, Icons.print_rounded, Colors.blue),
      ('طابعات متصلة', totals['onlinePrinters'] ?? 0, Icons.wifi_rounded, Colors.green),
      ('طابعات غير متصلة', totals['offlinePrinters'] ?? 0, Icons.wifi_off_rounded, Colors.red),
      ('إجمالي الصفحات المطبوعة', totals['totalPages'] ?? 0, Icons.description_rounded, Colors.purple),
      ('الصفحات التالفة (الهالك)', totals['wastePages'] ?? 0, Icons.delete_sweep_rounded, Colors.blueGrey),
      ('استخدام الشهر الحالي', totals['monthlyUsage'] ?? 0, Icons.calendar_month_rounded, Colors.teal),
      ('تنبيهات انخفاض الحبر', totals['tonerAlerts'] ?? 0, Icons.opacity_rounded, Colors.orange),
    ];
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 90,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final colors = Theme.of(context).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colors.divider.withOpacity(0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: item.$4.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.$3, color: item.$4, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$2.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BranchPanel extends StatelessWidget {
  const _BranchPanel({
    required this.branches,
    required this.selectedBranchId,
    required this.onSelected,
    required this.onDiscover,
    required this.onEditBranch,
  });

  final List<PrinterBranchItem> branches;
  final String? selectedBranchId;
  final ValueChanged<String?> onSelected;
  final ValueChanged<String>? onDiscover;
  final ValueChanged<PrinterBranchItem>? onEditBranch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Panel(
      title: 'فروع الشركة والمواقع',
      child: ListView(
        children: [
          _buildBranchItem(
            title: 'كل فروع الشركة',
            subtitle: 'جميع الطابعات المتوفرة (\${branches.length} فرع)',
            selected: selectedBranchId == null,
            onTap: () => onSelected(null),
            icon: Icons.business_rounded,
          ),
          for (final branch in branches)
            _buildBranchItem(
              title: branch.name,
              subtitle: '\${branch.code} | \${branch.networkRange}',
              selected: selectedBranchId == branch.id,
              onTap: () => onSelected(branch.id),
              icon: Icons.location_on_rounded,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onEditBranch != null)
                    IconButton(
                      iconSize: 18,
                      tooltip: 'تعديل بيانات الفرع',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => onEditBranch!(branch),
                    ),
                  if (onDiscover != null)
                    IconButton(
                      iconSize: 18,
                      tooltip: 'البحث عن أجهزة بالفرع (SNMP Scan)',
                      icon: const Icon(Icons.radar_rounded, color: Colors.teal),
                      onPressed: () => onDiscover!(branch.id),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBranchItem({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    required IconData icon,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? Colors.blue.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? Colors.blue.withOpacity(0.3) : Colors.transparent,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selected: selected,
        leading: Icon(icon, color: selected ? Colors.blue : Colors.grey),
        title: Text(
          _fixText(title),
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
        subtitle: Text(
          _fixText(subtitle),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

class _PrinterTable extends StatelessWidget {
  const _PrinterTable({
    required this.printers,
    required this.selectedPrinterId,
    required this.onSelected,
    required this.onSyncPrinter,
    required this.onDeletePrinter,
  });

  final List<PrinterItem> printers;
  final String? selectedPrinterId;
  final ValueChanged<PrinterItem> onSelected;
  final ValueChanged<String>? onSyncPrinter;
  final ValueChanged<String>? onDeletePrinter;

  Widget _buildMiniTonerStatus(Map<String, dynamic> toner) {
    final List<Widget> dots = [];
    
    void addDot(String key, Color color) {
      final val = toner[key];
      if (val != null) {
        num? number;
        if (val is num) number = val;
        else number = num.tryParse(val.toString());

        if (number != null) {
          final isLow = number < 15;
          dots.add(
            Tooltip(
              message: '\${key.toUpperCase()}: \${number.toStringAsFixed(0)}%',
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color.withOpacity(isLow ? 0.2 : 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isLow ? Colors.red : color,
                    width: isLow ? 2 : 1,
                  ),
                ),
                child: isLow
                    ? const Center(
                        child: Text(
                          '!',
                          style: TextStyle(color: Colors.red, fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      )
                    : null,
              ),
            ),
          );
        }
      }
    }

    addDot('black', const Color(0xFF1E293B));
    addDot('cyan', const Color(0xFF06B6D4));
    addDot('magenta', const Color(0xFFEC4899));
    addDot('yellow', const Color(0xFFEAB308));

    if (dots.isEmpty) {
      return const Text('لا تتوفر بيانات حبر', style: TextStyle(color: Colors.grey, fontSize: 10));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: dots,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (printers.isEmpty) {
      return const _Panel(
        title: 'قائمة الطابعات المسجلة',
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'لا توجد أي طابعات مسجلة في الفرع المحدد حالياً. يرجى الضغط على زر (اكتشاف الطابعات) من الفروع لبدء فحص الشبكة التلقائي وإدخال الأجهزة المتاحة بنظام SNMP.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, height: 1.5),
            ),
          ),
        ),
      );
    }
    return _Panel(
      title: 'قائمة الطابعات المسجلة',
      child: ListView.separated(
        itemCount: printers.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: colors.divider.withOpacity(0.1)),
        itemBuilder: (context, index) {
          final printer = printers[index];
          final statusColor = _printerStatusColor(printer.status);
          final isSelected = selectedPrinterId == printer.id;
          
          return Container(
            color: isSelected ? colors.primaryContainer.withOpacity(0.15) : null,
            child: ListTile(
              selected: isSelected,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.print_rounded, color: statusColor, size: 24),
              ),
              title: Text(
                printer.name.isEmpty ? printer.ipAddress : printer.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  '\${printer.branchName} • \${printer.model} • S/N: \${printer.serialNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              trailing: Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // CMYK Toner preview dots
                  _buildMiniTonerStatus(printer.tonerLevels),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'إجمالي: \${(printer.lifetimeCounters['totalPages'] ?? 0).toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      if ((printer.lifetimeCounters['scanPages'] ?? 0) > 0)
                        Text(
                          'مسح: \${(printer.lifetimeCounters['scanPages'] ?? 0).toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.teal, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                  if (onSyncPrinter != null)
                    IconButton(
                      iconSize: 20,
                      tooltip: 'تحديث فوري للعدادات والاتصال',
                      icon: const Icon(Icons.sync_rounded),
                      onPressed: () => onSyncPrinter!(printer.id),
                    ),
                  if (onDeletePrinter != null)
                    IconButton(
                      iconSize: 20,
                      tooltip: 'حذف الطابعة نهائياً',
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      onPressed: () => onDeletePrinter!(printer.id),
                    ),
                ],
              ),
              onTap: () => onSelected(printer),
            ),
          );
        },
      ),
    );
  }
}`;

// Redesigned Block 2: _PrinterDetailsPanel
const newBlock2 = `class _PrinterDetailsPanel extends StatelessWidget {
  const _PrinterDetailsPanel({required this.printer});

  final PrinterItem printer;

  Widget _buildMiniProgressBar(BuildContext context, String label, Object? val, Color barColor) {
    num? number;
    if (val is num) number = val;
    else number = num.tryParse(val?.toString() ?? '');

    final double pct = number == null ? 0 : (number.clamp(0, 100) / 100).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: const TextStyle(fontSize: 11))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                color: barColor,
                backgroundColor: Colors.grey.withOpacity(0.12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text(
              number == null ? '-' : '\${number.toStringAsFixed(0)}%',
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: number != null && number < 15 ? Colors.red : null),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _printerStatusColor(printer.status);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasColor = printer.tonerLevels['cyan'] != null;

    return _Panel(
      title: 'تفاصيل الطابعة السريعة',
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Icon(Icons.print_rounded, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  printer.name.isEmpty ? printer.ipAddress : printer.name,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _StatusBadge(status: printer.status),
            ],
          ),
          const SizedBox(height: 12),
          _InfoLine(label: 'الفرع والموقع', value: printer.branchName),
          _InfoLine(label: 'عنوان IP', value: printer.ipAddress),
          _InfoLine(label: 'الموديل', value: printer.model),
          _InfoLine(label: 'الرقم التسلسلي', value: printer.serialNumber),
          _InfoLine(label: 'آخر مزامنة', value: _dateText(printer.lastSyncAt)),
          const Divider(height: 20),
          const Text(
            'قراءة العدادات الحالية',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey),
          ),
          const SizedBox(height: 6),
          _CounterLine(label: 'إجمالي العداد صفحات', values: printer.lifetimeCounters, keyName: 'totalPages'),
          _CounterLine(label: 'صفحات أحادية', values: printer.lifetimeCounters, keyName: 'monoPages'),
          _CounterLine(label: 'صفحات ملونة', values: printer.lifetimeCounters, keyName: 'colorPages'),
          _CounterLine(label: 'طباعة مزدوجة (Duplex)', values: printer.lifetimeCounters, keyName: 'duplexPages'),
          _CounterLine(label: 'نسخ مستندات (Copy)', values: printer.lifetimeCounters, keyName: 'copyPages'),
          _CounterLine(label: 'مسح ضوئي (Scan)', values: printer.lifetimeCounters, keyName: 'scanPages'),
          const Divider(height: 20),
          const Text(
            'حالة خراطيش الحبر المتبقية',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey),
          ),
          const SizedBox(height: 6),
          _buildMiniProgressBar(context, 'أسود Black', printer.tonerLevels['black'], const Color(0xFF1E293B)),
          if (hasColor) ...[
            _buildMiniProgressBar(context, 'سماوي Cyan', printer.tonerLevels['cyan'], const Color(0xFF06B6D4)),
            _buildMiniProgressBar(context, 'أرجواني Mag', printer.tonerLevels['magenta'], const Color(0xFFEC4899)),
            _buildMiniProgressBar(context, 'أصفر Yel', printer.tonerLevels['yellow'], const Color(0xFFEAB308)),
          ],
          const Divider(height: 20),
          const Text(
            'الصيانة والأعطال',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey),
          ),
          const SizedBox(height: 6),
          _DynamicLine(label: 'مرات انحشار الورق', values: printer.maintenance, keyName: 'paperJams'),
          _DynamicLine(label: 'أخطاء مسجلة', values: printer.maintenance, keyName: 'errorMessages'),
        ],
      ),
    );
  }
}`;

// Find Block 1 start and end
const startKeyword1 = "class PrinterDetailsScreen extends ConsumerWidget {";
const endKeyword1 = "class _SidePanel extends StatelessWidget {";

const startIndex1 = content.indexOf(startKeyword1);
const endIndex1 = content.indexOf(endKeyword1);

if (startIndex1 === -1 || endIndex1 === -1) {
  console.error("Could not find start/end keywords for Block 1!");
  process.exit(1);
}

// Replace Block 1
content = content.substring(0, startIndex1) + newBlock1 + "\n\n" + content.substring(endIndex1);

// Find Block 2 start and end
const startKeyword2 = "class _PrinterDetailsPanel extends StatelessWidget {";
const endKeyword2 = "class _InfoLine extends StatelessWidget {";

const startIndex2 = content.indexOf(startKeyword2);
const endIndex2 = content.indexOf(endKeyword2);

if (startIndex2 === -1 || endIndex2 === -1) {
  console.error("Could not find start/end keywords for Block 2!");
  process.exit(1);
}

// Replace Block 2
content = content.substring(0, startIndex2) + newBlock2 + "\n\n" + content.substring(endIndex2);

fs.writeFileSync(filePath, content, "utf8");
console.log("Successfully replaced UI blocks in printer_monitoring_screen.dart!");
