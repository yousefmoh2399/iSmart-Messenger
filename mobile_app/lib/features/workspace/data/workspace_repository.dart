import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workspace_doc.dart';

class WorkspaceRepository {
  static const String _storagePrefix = 'ismart_workspace_docs_';

  String _key(String userId) => '$_storagePrefix${userId.trim()}';

  Future<List<WorkspaceDoc>> getDocs(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null || raw.trim().isEmpty) {
      // Seed default welcome doc for this employee
      final seeded = _createStarterDocs(userId);
      await saveDocs(userId, seeded);
      return seeded;
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final docs = list
          .map((item) => WorkspaceDoc.fromJson(item as Map<String, dynamic>))
          .toList();
      // Sort pinned first, then by updatedAt descending
      docs.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      return docs;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDocs(String userId, List<WorkspaceDoc> docs) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(docs.map((d) => d.toJson()).toList());
    await prefs.setString(_key(userId), jsonString);
  }

  List<WorkspaceDoc> _createStarterDocs(String userId) {
    return [
      WorkspaceDoc(
        userId: userId,
        title: 'مرحباً بك في مساحة العمل والملاحظات 🚀',
        icon: '👋',
        category: 'عام',
        isPinned: true,
        coverColor: '0xFFE0F2FE',
        blocks: [
          WorkspaceBlock(
            type: WorkspaceBlockType.callout,
            content: 'مساحة عملك الخاصة لتنظيم مهامك، كتابة ملاحظات الشفت، وتوثيق الأفكار بكل سهولة وأناقة.',
            calloutIcon: '💡',
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.heading1,
            content: 'ما الذي يمكنك فعله هنا؟',
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.todo,
            content: 'إنشاء صفحات وملاحظات وجداول غير محدودة في مساحة العمل والملاحظات',
            isChecked: true,
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.todo,
            content: 'متابعة قوائم المهام التفاعلية ووضع علامات الإنجاز بنقرة واحدة',
            isChecked: false,
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.todo,
            content: 'استخدام القوالب الجاهزة (خطة اليوم، تسليم الشفت، مقترحات التطوير)',
            isChecked: false,
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.todo,
            content: 'مشاركة الملاحظة بنقرة واحدة مباشرة إلى محادثات الزملاء أو الفروع',
            isChecked: false,
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.divider,
            content: '',
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.quote,
            content: '«البساطة هي قمة التطور والذكاء» — ابدأ بإنشاء أول صفحة لك الآن!',
          ),
        ],
      ),
    ];
  }
}
