import 'dart:io';

void main() async {
  final file = File('lib/features/files/presentation/my_files_screen.dart');
  var content = await file.readAsString();

  content = content.replaceFirst(
      "import 'pending_uploads_screen.dart';",
      "import 'pending_uploads_screen.dart';\nimport '../../../shared/models/pending_upload.dart';\nimport 'upload_summary_screen.dart';");

  content = content.replaceFirst(
      "final documentsState = ref.watch(remoteDocumentsControllerProvider);",
      "final documentsState = ref.watch(remoteDocumentsControllerProvider);\n    final pendingState = ref.watch(pendingUploadsControllerProvider);");

  content = content.replaceFirst(
      "Future<void> refreshDocuments() {\n      return ref.read(remoteDocumentsControllerProvider.notifier).refresh();\n    }",
      "Future<void> refreshDocuments() async {\n      await ref.read(remoteDocumentsControllerProvider.notifier).refresh();\n      await ref.read(pendingUploadsControllerProvider.notifier).refresh();\n    }");

  final tabStart = content.indexOf('return DefaultTabController(');
  final tabEnd = content.lastIndexOf('  }\n}');
  
  if (tabStart != -1 && tabEnd != -1) {
    final newBuildLogic = '''return Scaffold(
      appBar: AppBar(
        title: const Text('الملفات'),
        actions: [
          IconButton(
            tooltip: 'طباعة ملف من الجهاز',
            onPressed: _printLocalFileFromDevice,
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            onPressed: refreshDocuments,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Builder(
            builder: (context) {
              final isLoading = documentsState.isLoading || pendingState.isLoading;
              if (isLoading && documentsState.valueOrNull == null && pendingState.valueOrNull == null) {
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    headerCard,
                    ...banners,
                    searchField,
                    ...List.generate(
                      6,
                      (_) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ShimmerSkeleton(width: 180, height: 14),
                                SizedBox(height: 10),
                                ShimmerSkeleton(width: 260, height: 12),
                                SizedBox(height: 8),
                                ShimmerSkeleton(width: 220, height: 12),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              
              if (documentsState.hasError) {
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    headerCard,
                    ...banners,
                    searchField,
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(documentsState.error.toString())),
                    ),
                  ],
                );
              }
              
              final remoteDocs = documentsState.valueOrNull ?? [];
              final pendingDocs = pendingState.valueOrNull ?? [];
              
              final filteredRemote = _filter(remoteDocs);
              final query = _searchController.text.trim().toLowerCase();
              final filteredPending = query.isEmpty 
                  ? pendingDocs 
                  : pendingDocs.where((doc) => doc.fileName.toLowerCase().contains(query)).toList();
                  
              final merged = <dynamic>[...filteredPending, ...filteredRemote];
              merged.sort((a, b) {
                final aDate = a is PendingUpload ? a.createdAt : (a as RemoteDocument).createdAt;
                final bDate = b is PendingUpload ? b.createdAt : (b as RemoteDocument).createdAt;
                return bDate.compareTo(aDate);
              });

              return RefreshIndicator(
                onRefresh: refreshDocuments,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    headerCard,
                    ...banners,
                    searchField,
                    if (merged.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('لا توجد ملفات')),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: merged.map((doc) {
                              if (doc is PendingUpload) {
                                return _buildPendingCard(context, doc);
                              } else {
                                return _buildDocumentCard(context, doc as RemoteDocument);
                              }
                            }).toList(),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          if (_isSendingToDesktop)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.18),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.computer_rounded,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'إرسال \${_sendingFileName ?? 'الملف'} إلى الكمبيوتر',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              LinearProgressIndicator(
                                value: _desktopSendProgress <= 0
                                    ? null
                                    : _desktopSendProgress
                                          .clamp(0, 1)
                                          .toDouble(),
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _desktopSendStageMessage ??
                                          'جاري الإرسال...',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '\${(_desktopSendProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );''';
    content = content.substring(0, tabStart) + newBuildLogic + '\\n' + content.substring(tabEnd);
  }

  final buildDocIdx = content.indexOf('  Widget _buildDocumentCard(');
  if (buildDocIdx != -1) {
    final pendingCardLogic = '''  Widget _buildPendingCard(BuildContext context, PendingUpload pendingUpload) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark 
            ? colorScheme.primary.withValues(alpha: 0.1) 
            : colorScheme.primaryContainer.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF1F5F9),
          ),
          left: BorderSide(
            color: colorScheme.primary,
            width: 4,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UploadSummaryScreen(
                  pendingUpload: pendingUpload,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.phone_iphone_rounded,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pendingUpload.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.pages_outlined,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'محلي - \${pendingUpload.pageCount} صفحة',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.data_usage_rounded,
                            size: 14,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formatFileSize(pendingUpload.fileSize),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => OpenFilex.open(pendingUpload.filePath),
                  icon: const Icon(Icons.open_in_new_rounded),
                  tooltip: 'فتح محليًا',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

''';
    content = content.substring(0, buildDocIdx) + pendingCardLogic + content.substring(buildDocIdx);
  }

  await file.writeAsString(content);
}
