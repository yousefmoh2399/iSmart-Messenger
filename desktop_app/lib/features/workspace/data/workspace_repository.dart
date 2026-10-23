import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workspace_doc.dart';

class WorkspaceRepository {
  static const String _storagePrefix = 'ismart_desktop_workspace_docs_';

  String _key(String userId) => '$_storagePrefix${userId.trim()}';

  Future<List<WorkspaceDoc>> getDocs(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null || raw.trim().isEmpty) {
      final seeded = _createStarterDocs(userId);
      await saveDocs(userId, seeded);
      return seeded;
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final docs = list
          .map((item) => WorkspaceDoc.fromJson(item as Map<String, dynamic>))
          .toList();
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
        title: 'مرحباً بك في مساحة عمل iSmart المكتبية 🚀',
        icon: '💻',
        category: 'عام',
        isPinned: true,
        coverColor: '0xFFE0F2FE',
        blocks: [
          WorkspaceBlock(
            type: WorkspaceBlockType.callout,
            content: 'مساحة العمل المتكاملة على الكمبيوتر: وثق ملاحظاتك، تابع مهام الشفت، ونظم أعمالك بسهولة.',
            calloutIcon: '💡',
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.heading1,
            content: 'مميزات مساحة العمل',
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.todo,
            content: 'تحرير مرن وبلوكات متنوعة (عناوين، نصوص، قوائم مهام، اقتباسات)',
            isChecked: true,
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.todo,
            content: 'قوالب بنقرة واحدة لخطة اليوم واستلام وتسليم الشفت ومحاضر الاجتماعات',
            isChecked: false,
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.todo,
            content: 'حفظ فوري وتلقائي وتصنيفات مفلترة',
            isChecked: false,
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.divider,
            content: '',
          ),
          WorkspaceBlock(
            type: WorkspaceBlockType.quote,
            content: '«التنظيم الجيد يوفر نصف وقت العمل» — ابدأ بإنشاء صفحتك الآن!',
          ),
        ],
      ),
    ];
  }
}
