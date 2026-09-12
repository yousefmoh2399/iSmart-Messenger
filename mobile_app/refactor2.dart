import 'dart:io';

void main() async {
  final file = File('lib/features/files/presentation/my_files_screen.dart');
  var content = await file.readAsString();

  final tabStart = content.indexOf('return DefaultTabController(');
  final tabEnd = content.lastIndexOf('  }\n}');
  final tabEndFallback = content.lastIndexOf('  }\r\n}');
  
  final actualTabEnd = tabEnd != -1 ? tabEnd : tabEndFallback;
  
  if (tabStart != -1 && actualTabEnd != -1) {
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
    content = content.substring(0, tabStart) + newBuildLogic + '\n' + content.substring(actualTabEnd);
    await file.writeAsString(content);
    print('Refactored correctly.');
  } else {
    print('Could not find tabStart (\$tabStart) or tabEnd (\$actualTabEnd)');
  }
}
