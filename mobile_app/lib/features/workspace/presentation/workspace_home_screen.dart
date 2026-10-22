import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/workspace_doc.dart';
import 'widgets/workspace_doc_card.dart';
import 'workspace_controller.dart';
import 'workspace_doc_editor_screen.dart';
import 'workspace_templates.dart';

class WorkspaceHomeScreen extends ConsumerStatefulWidget {
  const WorkspaceHomeScreen({super.key});

  @override
  ConsumerState<WorkspaceHomeScreen> createState() => _WorkspaceHomeScreenState();
}

class _WorkspaceHomeScreenState extends ConsumerState<WorkspaceHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'الكل';
  bool _isGridView = true;

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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkspaceDocEditorScreen(doc: doc),
      ),
    );
  }

  Future<void> _createBlankDoc() async {
    HapticFeedback.mediumImpact();
    final newDoc = await ref.read(workspaceDocsProvider.notifier).createDoc();
    if (!mounted) return;
    _openEditor(newDoc);
  }

  Future<void> _createFromTemplate(WorkspaceTemplate template) async {
    HapticFeedback.mediumImpact();
    final newDoc = await ref
        .read(workspaceDocsProvider.notifier)
        .createFromTemplate(template);
    if (!mounted) return;
    _openEditor(newDoc);
  }

  List<WorkspaceDoc> _filterDocs(List<WorkspaceDoc> docs) {
    var result = docs;
    final query = _searchController.text.trim().toLowerCase();

    // Category filter
    if (_selectedCategory == 'المثبتة 📌') {
      result = result.where((d) => d.isPinned).toList();
    } else if (_selectedCategory == 'المفضلة ⭐') {
      result = result.where((d) => d.isFavorite).toList();
    } else if (_selectedCategory != 'الكل') {
      result = result.where((d) => d.category == _selectedCategory).toList();
    }

    // Search query filter
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
    final docsState = ref.watch(workspaceDocsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF161618) : Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: const Text(
          'مساحة العمل (Notion)',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: Icon(_isGridView ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2, size: 20),
            tooltip: _isGridView ? 'عرض كقائمة' : 'عرض كشبكة',
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _isGridView = !_isGridView);
            },
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.plus_circle_fill, color: Color(0xFF007AFF), size: 26),
            tooltip: 'صفحة جديدة',
            onPressed: _createBlankDoc,
          ),
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
                          width: 0.8,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.search,
                            size: 18,
                            color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              decoration: InputDecoration(
                                hintText: 'البحث في العناوين والمحتوى...',
                                hintStyle: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 11),
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

                // 2. Templates Carousel (Notion One-Tap Templates)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                        child: Row(
                          children: [
                            const Text(
                              'قوالب جاهزة سريعة',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'اضغط للإنشاء الفوري',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 95,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
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

                // 3. Category Filter Chips
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: Row(
                      children: _filters.map((filter) {
                        final isSelected = _selectedCategory == filter;
                        return Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Text(filter),
                            selected: isSelected,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedCategory = filter);
                            },
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : const Color(0xFF475569)),
                            ),
                            selectedColor: const Color(0xFF007AFF),
                            backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
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

                // 4. Documents Feed (Grid or List)
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.doc_text_search,
                            size: 52,
                            color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            docs.isEmpty ? 'لا توجد مستندات بعد' : 'لا توجد نتائج مطابقة للبحث',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            docs.isEmpty
                                ? 'اختر أحد القوالب في الأعلى أو أنشئ صفحة جديدة'
                                : 'جرب البحث بكلمات أخرى',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_isGridView)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.88,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
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
                            onDelete: () => ref.read(workspaceDocsProvider.notifier).deleteDoc(doc.id),
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 80),
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
                            onDelete: () => ref.read(workspaceDocsProvider.notifier).deleteDoc(doc.id),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createBlankDoc,
        backgroundColor: const Color(0xFF007AFF),
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(CupertinoIcons.pencil_outline, size: 20),
        label: const Text('صفحة جديدة', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildTemplateCard(WorkspaceTemplate template, bool isDark) {
    return Container(
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
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
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(template.icon, style: const TextStyle(fontSize: 20)),
                    const Spacer(),
                    Icon(Icons.add_circle_outline_rounded, size: 16, color: template.accentColor),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  template.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
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
                    fontSize: 10,
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
