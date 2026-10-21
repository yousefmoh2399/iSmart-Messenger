class ReportColumn {
  const ReportColumn({
    required this.key,
    required this.label,
    this.enabled = true,
    this.order = 0,
    this.width = 100,
    this.align = 'center',
    this.description = '',
  });

  final String key;
  final String label;
  final bool enabled;
  final int order;
  final int width;
  final String align;
  final String description;

  ReportColumn copyWith({
    String? key,
    String? label,
    bool? enabled,
    int? order,
    int? width,
    String? align,
    String? description,
  }) {
    return ReportColumn(
      key: key ?? this.key,
      label: label ?? this.label,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      width: width ?? this.width,
      align: align ?? this.align,
      description: description ?? this.description,
    );
  }

  factory ReportColumn.fromMap(Map<String, dynamic> map) {
    return ReportColumn(
      key: map['key']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      enabled: map['enabled'] != false,
      order: (map['order'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 100,
      align: map['align']?.toString() ?? 'center',
      description: map['description']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'label': label,
      'enabled': enabled,
      'order': order,
      'width': width,
      'align': align,
      if (description.isNotEmpty) 'description': description,
    };
  }
}

class ReportHeaderConfig {
  const ReportHeaderConfig({
    this.line1 = 'جمعية رجال الأعمال والمستثمرين بالدقهلية',
    this.line2 = 'مشروع تنمية المنشآت الصغيرة والحرفية',
    this.line3 = 'رقم الإشهار: 777 لسنة 1995 - رقم الترخيص: 1031',
    this.titleFormat = '',
    this.showLogo1 = true,
    this.showLogo2 = true,
    this.footerNote = 'يعتمد، إدارة تكنولوجيا المعلومات',
    this.preparedByLabel = 'إعداد: ',
  });

  final String line1;
  final String line2;
  final String line3;
  final String titleFormat;
  final bool showLogo1;
  final bool showLogo2;
  final String footerNote;
  final String preparedByLabel;

  ReportHeaderConfig copyWith({
    String? line1,
    String? line2,
    String? line3,
    String? titleFormat,
    bool? showLogo1,
    bool? showLogo2,
    String? footerNote,
    String? preparedByLabel,
  }) {
    return ReportHeaderConfig(
      line1: line1 ?? this.line1,
      line2: line2 ?? this.line2,
      line3: line3 ?? this.line3,
      titleFormat: titleFormat ?? this.titleFormat,
      showLogo1: showLogo1 ?? this.showLogo1,
      showLogo2: showLogo2 ?? this.showLogo2,
      footerNote: footerNote ?? this.footerNote,
      preparedByLabel: preparedByLabel ?? this.preparedByLabel,
    );
  }

  factory ReportHeaderConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ReportHeaderConfig();
    return ReportHeaderConfig(
      line1: map['line1']?.toString() ?? 'جمعية رجال الأعمال والمستثمرين بالدقهلية',
      line2: map['line2']?.toString() ?? 'مشروع تنمية المنشآت الصغيرة والحرفية',
      line3: map['line3']?.toString() ?? 'رقم الإشهار: 777 لسنة 1995 - رقم الترخيص: 1031',
      titleFormat: map['titleFormat']?.toString() ?? '',
      showLogo1: map['showLogo1'] != false,
      showLogo2: map['showLogo2'] != false,
      footerNote: map['footerNote']?.toString() ?? 'يعتمد، إدارة تكنولوجيا المعلومات',
      preparedByLabel: map['preparedByLabel']?.toString() ?? 'إعداد: ',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'line1': line1,
      'line2': line2,
      'line3': line3,
      'titleFormat': titleFormat,
      'showLogo1': showLogo1,
      'showLogo2': showLogo2,
      'footerNote': footerNote,
      'preparedByLabel': preparedByLabel,
    };
  }
}

class ReportOptions {
  const ReportOptions({
    this.orientation = 'landscape',
    this.includeSummaryRow = true,
    this.fontSize = 12,
    this.rowHeight = 50,
    this.exportFormatDefault = 'xlsx',
  });

  final String orientation;
  final bool includeSummaryRow;
  final int fontSize;
  final int rowHeight;
  final String exportFormatDefault;

  ReportOptions copyWith({
    String? orientation,
    bool? includeSummaryRow,
    int? fontSize,
    int? rowHeight,
    String? exportFormatDefault,
  }) {
    return ReportOptions(
      orientation: orientation ?? this.orientation,
      includeSummaryRow: includeSummaryRow ?? this.includeSummaryRow,
      fontSize: fontSize ?? this.fontSize,
      rowHeight: rowHeight ?? this.rowHeight,
      exportFormatDefault: exportFormatDefault ?? this.exportFormatDefault,
    );
  }

  factory ReportOptions.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ReportOptions();
    return ReportOptions(
      orientation: map['orientation']?.toString() ?? 'landscape',
      includeSummaryRow: map['includeSummaryRow'] != false,
      fontSize: (map['fontSize'] as num?)?.toInt() ?? 12,
      rowHeight: (map['rowHeight'] as num?)?.toInt() ?? 50,
      exportFormatDefault: map['exportFormatDefault']?.toString() ?? 'xlsx',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'orientation': orientation,
      'includeSummaryRow': includeSummaryRow,
      'fontSize': fontSize,
      'rowHeight': rowHeight,
      'exportFormatDefault': exportFormatDefault,
    };
  }
}

class ReportTemplate {
  const ReportTemplate({
    required this.id,
    required this.name,
    required this.reportType,
    this.description = '',
    this.isDefault = false,
    this.headerConfig = const ReportHeaderConfig(),
    this.columns = const [],
    this.options = const ReportOptions(),
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String reportType;
  final String description;
  final bool isDefault;
  final ReportHeaderConfig headerConfig;
  final List<ReportColumn> columns;
  final ReportOptions options;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ReportTemplate copyWith({
    String? id,
    String? name,
    String? reportType,
    String? description,
    bool? isDefault,
    ReportHeaderConfig? headerConfig,
    List<ReportColumn>? columns,
    ReportOptions? options,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReportTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      reportType: reportType ?? this.reportType,
      description: description ?? this.description,
      isDefault: isDefault ?? this.isDefault,
      headerConfig: headerConfig ?? this.headerConfig,
      columns: columns ?? this.columns,
      options: options ?? this.options,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ReportTemplate.fromMap(Map<String, dynamic> map) {
    return ReportTemplate(
      id: map['_id']?.toString() ?? map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'قالب بدون اسم',
      reportType: map['reportType']?.toString() ?? 'printer_consumption',
      description: map['description']?.toString() ?? '',
      isDefault: map['isDefault'] == true,
      headerConfig: ReportHeaderConfig.fromMap(
        map['headerConfig'] as Map<String, dynamic>?,
      ),
      columns: (map['columns'] as List<dynamic>?)
              ?.map((c) => ReportColumn.fromMap(c as Map<String, dynamic>))
              .toList() ??
          const [],
      options: ReportOptions.fromMap(map['options'] as Map<String, dynamic>?),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString())
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'reportType': reportType,
      'description': description,
      'isDefault': isDefault,
      'headerConfig': headerConfig.toMap(),
      'columns': columns.map((c) => c.toMap()).toList(),
      'options': options.toMap(),
    };
  }
}
