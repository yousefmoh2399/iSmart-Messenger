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
  bool _isSidebarOpen = true;
  String? _selectedDocId;

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

  void _openDoc(WorkspaceDoc doc) {
    setState(() {
      _selectedDocId = doc.id;
    });
  }

  Future<void> _createBlankDoc() async {
    final newDoc = await ref.read(workspaceDocsProvider.notifier).createDoc();
    if (!mounted) return;
    _openDoc(newDoc);
  }

  Future<void> _createFromTemplate(WorkspaceTemplate template) async {
    final newDoc = await ref
        .read(workspaceDocsProvider.notifier)
        .createFromTemplate(template);
    if (!mounted) return;
    _openDoc(newDoc);
  }

  void _confirmDelete(WorkspaceDoc doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('حذف الصفحة', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('هل أنت متأكد من حذف "${doc.title}"؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              Navigator.pop(ctx);
              if (_selectedDocId == doc.id) {
                setState(() => _selectedDocId = null);
              }
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
        final contentMatch = d.blocks.any(
          (b) =>
              b.content.toLowerCase().contains(query) ||
              b.subContent.toLowerCase().contains(query),
        );
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
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
      body: docsState.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF007AFF)),
        ),
        error: (err, _) => Center(
          child: Text('خطأ في تحميل مساحة العمل: $err'),
        ),
        data: (docs) {
          final filtered = _filterDocs(docs);
          WorkspaceDoc? activeDoc;
          if (_selectedDocId != null) {
            for (final d in docs) {
              if (d.id == _selectedDocId) {
                activeDoc = d;
                break;
              }
            }
          }

          return Row(
            children: [
              // 1. Right-side Notion Pages Tree Sidebar (in RTL, first child is on the right)
              if (_isSidebarOpen)
                _buildNotionSidebar(docs, filtered, activeDoc, isDark),

              // 2. Main Area (Either Live Document Editor OR Bento Overview Dashboard)
              Expanded(
                child: Column(
                  children: [
                    if (activeDoc != null)
                      Expanded(
                        child: WorkspaceDocEditorScreen(
                          key: ValueKey(activeDoc.id),
                          doc: activeDoc,
                          onBack: () => setState(() => _selectedDocId = null),
                          onDeleteDoc: () => _confirmDelete(activeDoc!),
                        ),
                      )
                    else
                      Expanded(
                        child: _buildOverviewDashboard(docs, filtered, isDark),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNotionSidebar(
    List<WorkspaceDoc> allDocs,
    List<WorkspaceDoc> filteredDocs,
    WorkspaceDoc? activeDoc,
    bool isDark,
  ) {
    final pinnedDocs = allDocs.where((d) => d.isPinned).toList();

    return Container(
      width: 270,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131C2E) : const Color(0xFFF1F5F9),
        border: Border(
          left: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidebar Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(CupertinoIcons.doc_richtext, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مساحة العمل',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Notion Workspace',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white38 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'صفحة جديدة',
                  icon: const Icon(CupertinoIcons.square_pencil, size: 19, color: Color(0xFF007AFF)),
                  onPressed: _createBlankDoc,
                ),
              ],
            ),
          ),

          // Quick Search in Sidebar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(CupertinoIcons.search, size: 15, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: 'بحث سريع...',
                        hintStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white30 : const Color(0xFF94A3B8)),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      child: const Icon(CupertinoIcons.xmark_circle_fill, size: 14, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Overview Home Item
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Material(
              color: activeDoc == null
                  ? const Color(0xFF007AFF).withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selectedDocId = null),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.square_grid_2x2_fill,
                        size: 16,
                        color: activeDoc == null
                            ? const Color(0xFF007AFF)
                            : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'الرئيسية والقوالب الجاهزة',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: activeDoc == null ? FontWeight.w800 : FontWeight.w600,
                          color: activeDoc == null
                              ? const Color(0xFF007AFF)
                              : (isDark ? Colors.white70 : const Color(0xFF334155)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 0.6),

          // Pages List in Sidebar
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                if (pinnedDocs.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                    child: Text(
                      'المثبتة 📌',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white38 : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  ...pinnedDocs.map((d) => _buildSidebarDocTile(d, activeDoc?.id == d.id, isDark)),
                  const SizedBox(height: 10),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                  child: Row(
                    children: [
                      Text(
                        'صفحاتي (${allDocs.length})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white38 : const Color(0xFF64748B),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _createBlankDoc,
                        child: const Icon(CupertinoIcons.plus, size: 14, color: Color(0xFF007AFF)),
                      ),
                    ],
                  ),
                ),
                ...filteredDocs.map((d) => _buildSidebarDocTile(d, activeDoc?.id == d.id, isDark)),
              ],
            ),
          ),

          // Bottom New Page Button
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(CupertinoIcons.add, size: 16),
              label: const Text('صفحة فارغة جديدة', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              onPressed: _createBlankDoc,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarDocTile(WorkspaceDoc doc, bool isSelected, bool isDark) {
    final todos = doc.todoCount;
    final done = doc.completedTodoCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: isSelected
            ? (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openDoc(doc),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Text(doc.icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    doc.title.trim().isNotEmpty ? doc.title : 'بدون عنوان',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFF007AFF)
                          : (isDark ? Colors.white70 : const Color(0xFF334155)),
                    ),
                  ),
                ),
                if (todos > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: done == todos
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '$done/$todos',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: done == todos
                            ? const Color(0xFF10B981)
                            : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewDashboard(
    List<WorkspaceDoc> docs,
    List<WorkspaceDoc> filtered,
    bool isDark,
  ) {
    final totalTodos = docs.fold<int>(0, (sum, d) => sum + d.todoCount);
    final completedTodos = docs.fold<int>(0, (sum, d) => sum + d.completedTodoCount);
    final pinnedCount = docs.where((d) => d.isPinned).length;

    return CustomScrollView(
      slivers: [
        // Top Bar
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131C2E) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: _isSidebarOpen ? 'إخفاء القائمة الجانبية' : 'إظهار القائمة الجانبية',
                  icon: Icon(
                    CupertinoIcons.sidebar_right,
                    size: 20,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                  onPressed: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مساحة العمل والملاحظات الذكية',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'نظم مهامك اليومية، الجداول، ومحاضر تسليم الشفت بتصميم أبل ونوشن',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  tooltip: _isGridView ? 'عرض كقائمة' : 'عرض كشبكة',
                  icon: Icon(
                    _isGridView ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(CupertinoIcons.add, size: 17),
                  label: const Text('صفحة جديدة', style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: _createBlankDoc,
                ),
              ],
            ),
          ),
        ),

        // Quick Summary Metrics Row
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
            child: Row(
              children: [
                _buildSummaryMetricCard(
                  'إجمالي الصفحات',
                  '${docs.length}',
                  CupertinoIcons.doc_text_fill,
                  const Color(0xFF007AFF),
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildSummaryMetricCard(
                  'المهام المنجزة',
                  '$completedTodos من $totalTodos',
                  CupertinoIcons.checkmark_seal_fill,
                  const Color(0xFF10B981),
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildSummaryMetricCard(
                  'الصفحات المثبتة',
                  '$pinnedCount',
                  CupertinoIcons.pin_fill,
                  const Color(0xFFF59E0B),
                  isDark,
                ),
              ],
            ),
          ),
        ),

        // Templates Section
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.sparkles, size: 16, color: Color(0xFF007AFF)),
                    const SizedBox(width: 6),
                    Text(
                      'قوالب جاهزة بضغطة واحدة (تحتوي على جداول ومهام جاهزة)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white70 : const Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 112,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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

        // Category Filter Chips
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
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

        // Documents Feed
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
                    docs.isEmpty ? 'مساحة عملك جاهزة للبدء' : 'لا توجد صفحات مطابقة للفلتر',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
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
                maxCrossAxisExtent: 290,
                childAspectRatio: 1.05,
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
                    onTap: () => _openDoc(doc),
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
                    onTap: () => _openDoc(doc),
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
  }

  Widget _buildSummaryMetricCard(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateCard(WorkspaceTemplate template, bool isDark) {
    return Container(
      width: 215,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _createFromTemplate(template),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: template.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(template.icon, style: const TextStyle(fontSize: 18)),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: template.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '+ استخدام',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: template.accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  template.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  template.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
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
