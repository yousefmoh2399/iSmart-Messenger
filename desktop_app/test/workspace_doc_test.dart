import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/features/workspace/models/workspace_doc.dart';
import 'package:desktop_app/features/workspace/presentation/workspace_templates.dart';

void main() {
  group('Desktop WorkspaceDoc & WorkspaceBlock Tests', () {
    test('WorkspaceBlock initialization and properties', () {
      final block = WorkspaceBlock(
        type: WorkspaceBlockType.todo,
        content: 'تجهيز أوراق الطابعة',
        isChecked: false,
      );

      expect(block.id, isNotEmpty);
      expect(block.type, WorkspaceBlockType.todo);
      expect(block.content, 'تجهيز أوراق الطابعة');
      expect(block.isChecked, isFalse);

      block.isChecked = true;
      expect(block.isChecked, isTrue);

      block.type = WorkspaceBlockType.heading1;
      expect(block.type, WorkspaceBlockType.heading1);
    });

    test('All WorkspaceBlockType serialization and deserialization', () {
      for (final type in WorkspaceBlockType.values) {
        final block = WorkspaceBlock(
          type: type,
          content: 'Test content for ${type.name}',
          isChecked: true,
          calloutIcon: '🔥',
          isExpanded: false,
        );

        final json = block.toJson();
        final restored = WorkspaceBlock.fromJson(json);

        expect(restored.type, type);
        expect(restored.content, block.content);
        expect(restored.isChecked, block.isChecked);
        expect(restored.calloutIcon, block.calloutIcon);
        expect(restored.isExpanded, block.isExpanded);
      }
    });

    test('WorkspaceDoc todo counts and word counts', () {
      final doc = WorkspaceDoc(
        userId: 'desktop_user_1',
        title: 'مهام الفرع اليومية',
        blocks: [
          WorkspaceBlock(type: WorkspaceBlockType.heading1, content: 'صباح الخير للجميع'),
          WorkspaceBlock(type: WorkspaceBlockType.todo, content: 'مهمة 1', isChecked: true),
          WorkspaceBlock(type: WorkspaceBlockType.todo, content: 'مهمة 2', isChecked: false),
          WorkspaceBlock(type: WorkspaceBlockType.todo, content: 'مهمة 3', isChecked: true),
          WorkspaceBlock(type: WorkspaceBlockType.numbered, content: 'أولا مراجعة الخزينة'),
          WorkspaceBlock(type: WorkspaceBlockType.numbered, content: 'ثانيا فحص الطابعات'),
          WorkspaceBlock(type: WorkspaceBlockType.code, content: 'net stop spooler'),
          WorkspaceBlock(type: WorkspaceBlockType.toggle, content: 'تفاصيل إضافية'),
        ],
      );

      expect(doc.todoCount, 3);
      expect(doc.completedTodoCount, 2);
      expect(doc.wordCount, greaterThan(10));
      expect(doc.characterCount, greaterThan(30));
    });

    test('WorkspaceDoc Markdown Export', () {
      final doc = WorkspaceDoc(
        userId: 'desktop_user_1',
        title: 'خطة العمل',
        icon: '📋',
        blocks: [
          WorkspaceBlock(type: WorkspaceBlockType.heading1, content: 'القسم الأول'),
          WorkspaceBlock(type: WorkspaceBlockType.todo, content: 'إنهاء التقارير', isChecked: true),
          WorkspaceBlock(type: WorkspaceBlockType.numbered, content: 'الخطوة الأولى'),
          WorkspaceBlock(type: WorkspaceBlockType.code, content: 'echo Hello'),
          WorkspaceBlock(type: WorkspaceBlockType.callout, content: 'تنبيه هام', calloutIcon: '⚠️'),
          WorkspaceBlock(type: WorkspaceBlockType.quote, content: 'اقتباس اليوم'),
          WorkspaceBlock(type: WorkspaceBlockType.divider, content: ''),
        ],
      );

      final md = doc.toMarkdown();
      expect(md, contains('# 📋 خطة العمل'));
      expect(md, contains('[x] إنهاء التقارير'));
      expect(md, contains('1. الخطوة الأولى'));
      expect(md, contains('echo Hello'));
      expect(md, contains('> ⚠️ تنبيه هام'));
      expect(md, contains('---'));
    });

    test('WorkspaceDoc JSON serialization and deserialization', () {
      final doc = WorkspaceDoc(
        userId: 'desktop_emp_99',
        title: 'استلام وتسليم',
        icon: '🤝',
        category: 'استلام وتسليم',
        isPinned: true,
        isFavorite: true,
        coverColor: '0xFFDCFCE7',
        blocks: [
          WorkspaceBlock(type: WorkspaceBlockType.text, content: 'تم التسليم بالكامل'),
        ],
      );

      final json = doc.toJson();
      final restored = WorkspaceDoc.fromJson(json);

      expect(restored.id, doc.id);
      expect(restored.userId, 'desktop_emp_99');
      expect(restored.title, 'استلام وتسليم');
      expect(restored.icon, '🤝');
      expect(restored.isPinned, isTrue);
      expect(restored.isFavorite, isTrue);
      expect(restored.category, 'استلام وتسليم');
      expect(restored.coverColor, '0xFFDCFCE7');
      expect(restored.blocks.length, 1);
      expect(restored.blocks.first.content, 'تم التسليم بالكامل');
    });

    test('WorkspaceTemplates generation', () {
      expect(WorkspaceTemplates.all.length, greaterThanOrEqualTo(5));

      for (final t in WorkspaceTemplates.all) {
        expect(t.id, isNotEmpty);
        expect(t.title, isNotEmpty);
        expect(t.icon, isNotEmpty);
        final blocks = t.blocksBuilder();
        expect(blocks, isNotEmpty);
      }
    });
  });
}
