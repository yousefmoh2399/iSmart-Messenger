import 'package:uuid/uuid.dart';

enum WorkspaceBlockType {
  heading1,
  heading2,
  heading3,
  text,
  todo,
  bullet,
  numbered,
  callout,
  quote,
  code,
  toggle,
  table,
  divider,
}

class WorkspaceBlock {
  WorkspaceBlock({
    String? id,
    required this.type,
    required this.content,
    this.subContent = '',
    this.colorHex = 'blue',
    this.isChecked = false,
    this.calloutIcon = '💡',
    this.isExpanded = true,
    List<List<String>>? tableData,
  })  : id = id ?? const Uuid().v4(),
        tableData = (tableData ??
                [
                  ['البند', 'الحالة', 'ملاحظات'],
                  ['', '', ''],
                  ['', '', ''],
                ])
            .map((row) => List<String>.from(row, growable: true))
            .toList(growable: true);

  final String id;
  WorkspaceBlockType type;
  String content;
  String subContent;
  String colorHex;
  bool isChecked;
  String calloutIcon;
  bool isExpanded;
  List<List<String>> tableData;

  WorkspaceBlock copyWith({
    String? id,
    WorkspaceBlockType? type,
    String? content,
    String? subContent,
    String? colorHex,
    bool? isChecked,
    String? calloutIcon,
    bool? isExpanded,
    List<List<String>>? tableData,
  }) {
    return WorkspaceBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      subContent: subContent ?? this.subContent,
      colorHex: colorHex ?? this.colorHex,
      isChecked: isChecked ?? this.isChecked,
      calloutIcon: calloutIcon ?? this.calloutIcon,
      isExpanded: isExpanded ?? this.isExpanded,
      tableData: tableData ??
          this.tableData.map((row) => List<String>.from(row)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'content': content,
      'subContent': subContent,
      'colorHex': colorHex,
      'isChecked': isChecked,
      'calloutIcon': calloutIcon,
      'isExpanded': isExpanded,
      'tableData': tableData,
    };
  }

  factory WorkspaceBlock.fromJson(Map<String, dynamic> json) {
    final rawTable = json['tableData'] as List<dynamic>?;
    List<List<String>>? parsedTable;
    if (rawTable != null && rawTable.isNotEmpty) {
      parsedTable = rawTable
          .map((row) => (row as List<dynamic>).map((c) => c.toString()).toList())
          .toList();
    }
    return WorkspaceBlock(
      id: json['id'] as String? ?? const Uuid().v4(),
      type: WorkspaceBlockType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => WorkspaceBlockType.text,
      ),
      content: json['content'] as String? ?? '',
      subContent: json['subContent'] as String? ?? '',
      colorHex: json['colorHex'] as String? ?? 'blue',
      isChecked: json['isChecked'] as bool? ?? false,
      calloutIcon: json['calloutIcon'] as String? ?? '💡',
      isExpanded: json['isExpanded'] as bool? ?? true,
      tableData: parsedTable,
    );
  }
}

class WorkspaceDoc {
  WorkspaceDoc({
    String? id,
    required this.userId,
    required this.title,
    this.icon = '📝',
    this.coverColor = '0xFFE0F2FE',
    this.category = 'عام',
    this.isPinned = false,
    this.isFavorite = false,
    List<WorkspaceBlock>? blocks,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        blocks = blocks ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String userId;
  String title;
  String icon;
  String coverColor;
  String category;
  bool isPinned;
  bool isFavorite;
  List<WorkspaceBlock> blocks;
  final DateTime createdAt;
  DateTime updatedAt;

  int get todoCount =>
      blocks.where((b) => b.type == WorkspaceBlockType.todo).length;

  int get completedTodoCount => blocks
      .where((b) => b.type == WorkspaceBlockType.todo && b.isChecked)
      .length;

  int get wordCount {
    int count = 0;
    for (final b in blocks) {
      final trimmed = '${b.content} ${b.subContent}'.trim();
      if (trimmed.isNotEmpty) {
        count += trimmed.split(RegExp(r'\s+')).length;
      }
    }
    return count;
  }

  int get characterCount {
    int count = 0;
    for (final b in blocks) {
      count += b.content.length + b.subContent.length;
    }
    return count;
  }

  String get previewText {
    for (final b in blocks) {
      if (b.content.trim().isNotEmpty && b.type != WorkspaceBlockType.divider) {
        return b.content.trim();
      }
    }
    return 'صفحة فارغة — اضغط للبدء بالكتابة...';
  }

  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('# $icon $title\n');
    int numIndex = 1;
    for (final b in blocks) {
      switch (b.type) {
        case WorkspaceBlockType.heading1:
          buffer.writeln('\n# ${b.content}\n');
          numIndex = 1;
          break;
        case WorkspaceBlockType.heading2:
          buffer.writeln('\n## ${b.content}\n');
          numIndex = 1;
          break;
        case WorkspaceBlockType.heading3:
          buffer.writeln('\n### ${b.content}\n');
          numIndex = 1;
          break;
        case WorkspaceBlockType.todo:
          buffer.writeln('${b.isChecked ? '[x]' : '[ ]'} ${b.content}');
          numIndex = 1;
          break;
        case WorkspaceBlockType.bullet:
          buffer.writeln('• ${b.content}');
          numIndex = 1;
          break;
        case WorkspaceBlockType.numbered:
          buffer.writeln('$numIndex. ${b.content}');
          numIndex++;
          break;
        case WorkspaceBlockType.callout:
          buffer.writeln('> ${b.calloutIcon} ${b.content}');
          numIndex = 1;
          break;
        case WorkspaceBlockType.quote:
          buffer.writeln('> ${b.content}');
          numIndex = 1;
          break;
        case WorkspaceBlockType.code:
          buffer.writeln('```\n${b.content}\n```');
          numIndex = 1;
          break;
        case WorkspaceBlockType.toggle:
          buffer.writeln('▶ ${b.content}');
          if (b.subContent.trim().isNotEmpty) {
            buffer.writeln('  ${b.subContent}');
          }
          numIndex = 1;
          break;
        case WorkspaceBlockType.table:
          if (b.tableData.isNotEmpty) {
            for (var r = 0; r < b.tableData.length; r++) {
              buffer.writeln('| ${b.tableData[r].join(' | ')} |');
              if (r == 0) {
                buffer.writeln(
                    '| ${b.tableData[r].map((_) => '---').join(' | ')} |');
              }
            }
            buffer.writeln();
          }
          numIndex = 1;
          break;
        case WorkspaceBlockType.divider:
          buffer.writeln('\n---\n');
          numIndex = 1;
          break;
        case WorkspaceBlockType.text:
          buffer.writeln('${b.content}\n');
          numIndex = 1;
          break;
      }
    }
    return buffer.toString().trim();
  }

  WorkspaceDoc copyWith({
    String? id,
    String? userId,
    String? title,
    String? icon,
    String? coverColor,
    String? category,
    bool? isPinned,
    bool? isFavorite,
    List<WorkspaceBlock>? blocks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkspaceDoc(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      coverColor: coverColor ?? this.coverColor,
      category: category ?? this.category,
      isPinned: isPinned ?? this.isPinned,
      isFavorite: isFavorite ?? this.isFavorite,
      blocks: blocks ??
          this.blocks.map((b) => b.copyWith()).toList(),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'icon': icon,
      'coverColor': coverColor,
      'category': category,
      'isPinned': isPinned,
      'isFavorite': isFavorite,
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory WorkspaceDoc.fromJson(Map<String, dynamic> json) {
    return WorkspaceDoc(
      id: json['id'] as String? ?? const Uuid().v4(),
      userId: json['userId'] as String? ?? '',
      title: json['title'] as String? ?? 'بدون عنوان',
      icon: json['icon'] as String? ?? '📝',
      coverColor: json['coverColor'] as String? ?? '0xFFE0F2FE',
      category: json['category'] as String? ?? 'عام',
      isPinned: json['isPinned'] as bool? ?? false,
      isFavorite: json['isFavorite'] as bool? ?? false,
      blocks: (json['blocks'] as List<dynamic>? ?? [])
          .map((b) => WorkspaceBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
