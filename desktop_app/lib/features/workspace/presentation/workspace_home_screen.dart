import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/workspace_doc.dart';
import 'widgets/workspace_doc_card.dart';
import 'workspace_controller.dart';
import 'workspace_doc_editor_screen.dart';
import 'workspace_templates.dart';

class WorkspaceHomeScreen extends ConsumerStatefulWidget {
  const WorkspaceHomeScreen({
    super.key,
    this.isWrapped = false,
  });

  final bool isWrapped;

  @override
  ConsumerState<WorkspaceHomeScreen> createState() => _WorkspaceHomeScreenState();
}

class _WorkspaceHomeScreenState extends ConsumerState<WorkspaceHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'الكل';
  bool _isGridView = true;
  WorkspaceDoc? _activeEditingDoc;

  static const List<String> _filters = [
    'الكل',
    'المثبتة 📌',
    'المفضلة ⭐',
    'مهام الفرع',
    'استلام وتسليم',
    'أفكار ومشاريع',
    'اجتماعات',
    'شخصي',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openEditor(WorkspaceDoc doc) {
    setState(() {
      _activeEditingDoc = doc;
    });
  }

  Future<void> _createBlankDoc() async {
    final newDoc = await ref.read(workspaceDocsProvider.notifier).createDoc();
    if (!mounted) return;
    _openEditor(newDoc);
  }

  Future<void> _createFromTemplate(WorkspaceTemplate template) async {
    final newDoc = await ref
        .read(workspaceDocsProvider.notifier)
        .createFromTemplate(template);
    if (!mounted) return;
    _openEditor(newDoc);
  }

  void _confirmDelete(WorkspaceDoc doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('حذف المستند'),
        content: Text('هل أنت متأكد من حذف "${doc.title}"؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(workspaceDocsProvider.notifier).deleteDoc(doc.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('تم حذف "${doc.title}"'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  List<WorkspaceDoc> _filterDocs(List<WorkspaceDoc> docs) {
    var result = docs;
    final query = _searchController.text.trim().toLowerCase();

    if (_selectedCategory == 'المثبتة 📌') {
      result = result.where((d) => d.isPinned).toList();
    } else if (_selectedCategory == 'المفضلة ⭐') {
      result = result.where((d) => d.isFavorite).toList();
    } else if (_selectedCategory != 'الكل') {
      result = result.where((d) => d.category == _selectedCategory).toList();
    }

    if (query.isNotEmpty) {
      result = result.where((d) {
        final titleMatch = d.title.toLowerCase().contains(query);
        final contentMatch = d.blocks.any((b) => b.content.toLowerCase().contains(query));
        return titleMatch || contentMatch;
      }).toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_activeEditingDoc != null) {
      return WorkspaceDocEditorScreen(
        doc: _activeEditingDoc!,
        onBack: () => setState(() => _activeEditingDoc = null),
      );
    }

    final docsState = ref.watch(workspaceDocsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: widget.isWrapped
            ? null
            : IconButton(
                icon: const Icon(CupertinoIcons.chevron_back, size: 22),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF5856D6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit_note_rounded, color: Color(0xFF5856D6), size: 22),
            ),
            const SizedBox(width: 10),
            const Text(
              'مساحة العمل والملاحظات (Notion)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isGridView ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2, size: 20),
            tooltip: _isGridView ? 'عرض كقائمة' : 'عرض كشبكة',
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF007AFF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            onPressed: _createBlankDoc,
            icon: const Icon(CupertinoIcons.plus, size: 16),
            label: const Text('صفحة جديدة', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: docsState.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF007AFF)),
          ),
          error: (err, _) => Center(
            child: Text('خطأ في تحميل المستندات: $err'),
          ),
          data: (docs) {
            final filtered = _filterDocs(docs);

            return CustomScrollView(
              slivers: [
                // 1. Search Bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                          width: 0.8,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.search,
                            size: 19,
                            color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(
                                fontSize: 14.5,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: 'البحث في عناوين الصفحات أو محتوى البلوكات...',
                                hintStyle: TextStyle(
                                  fontSize: 14.5,
                                  color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              child: const Icon(Icons.close_rounded, size: 18),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 2. Templates Carousel
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'قوالب جاهزة سريعة',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'اضغط لاختيار القالب وتوليد المستند فورياً',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 98,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: WorkspaceTemplates.all.length,
                            itemBuilder: (context, index) {
                              final template = WorkspaceTemplates.all[index];
                              return _buildTemplateCard(template, isDark);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Category Filter Chips
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _filters.map((filter) {
                          final isSelected = _selectedCategory == filter;
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ChoiceChip(
                              label: Text(filter),
                              selected: isSelected,
                              onSelected: (_) => setState(() => _selectedCategory = filter),
                              labelStyle: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : const Color(0xFF475569)),
                              ),
                              selectedColor: const Color(0xFF007AFF),
                              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                              side: BorderSide(
                                color: isSelected
                                    ? Colors.transparent
                                    : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),

                // 4. Documents Feed
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.doc_text_search,
                            size: 56,
                            color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            docs.isEmpty ? 'لا توجد مستندات بعد في مساحة عملك' : 'لا توجد نتائج مطابقة للبحث',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            docs.isEmpty
                                ? 'اختر أحد القوالب الجاهزة في الأعلى أو اضغط "صفحة جديدة" للبدء'
                                : 'جرب تغيير كلمة البحث أو التصنيف المحدد',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_isGridView)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 280,
                        childAspectRatio: 0.95,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final doc = filtered[index];
                          return WorkspaceDocCard(
                            doc: doc,
                            isGrid: true,
                            isDark: isDark,
                            onTap: () => _openEditor(doc),
                            onTogglePin: () => ref.read(workspaceDocsProvider.notifier).togglePin(doc.id),
                            onToggleFavorite: () => ref.read(workspaceDocsProvider.notifier).toggleFavorite(doc.id),
                            onDuplicate: () => ref.read(workspaceDocsProvider.notifier).duplicateDoc(doc.id),
                            onDelete: () => _confirmDelete(doc),
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 40),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final doc = filtered[index];
                          return WorkspaceDocCard(
                            doc: doc,
                            isGrid: false,
                            isDark: isDark,
                            onTap: () => _openEditor(doc),
                            onTogglePin: () => ref.read(workspaceDocsProvider.notifier).togglePin(doc.id),
                            onToggleFavorite: () => ref.read(workspaceDocsProvider.notifier).toggleFavorite(doc.id),
                            onDuplicate: () => ref.read(workspaceDocsProvider.notifier).duplicateDoc(doc.id),
                            onDelete: () => _confirmDelete(doc),
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTemplateCard(WorkspaceTemplate template, bool isDark) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _createFromTemplate(template),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(template.icon, style: const TextStyle(fontSize: 22)),
                    const Spacer(),
                    Icon(Icons.add_circle_outline_rounded, size: 18, color: template.accentColor),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  template.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  template.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
