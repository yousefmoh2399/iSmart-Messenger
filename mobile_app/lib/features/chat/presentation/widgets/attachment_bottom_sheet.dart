import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

enum AttachmentBottomSheetResult {
  image,
  file,
  screenshot,
  reaction,
  poll,
  checklist,
  gif
}

class AttachmentBottomSheet extends StatefulWidget {
  const AttachmentBottomSheet({super.key});

  @override
  State<AttachmentBottomSheet> createState() => _AttachmentBottomSheetState();
}

class _AttachmentBottomSheetState extends State<AttachmentBottomSheet> {
  List<AssetEntity> _recentPhotos = [];
  bool _isLoadingPhotos = true;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _fetchRecentPhotos();
  }

  Future<void> _fetchRecentPhotos() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth) {
      setState(() => _hasPermission = true);
      final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );
      if (paths.isNotEmpty) {
        final List<AssetEntity> photos = await paths.first.getAssetListPaged(
          page: 0,
          size: 20,
        );
        if (mounted) {
          setState(() {
            _recentPhotos = photos;
            _isLoadingPhotos = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoadingPhotos = false);
        }
      }
    } else {
      if (mounted) {
        setState(() => _isLoadingPhotos = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
            margin: const EdgeInsets.only(bottom: 16),
          ),
          
          // Recent Photos Horizontal List
          if (_hasPermission)
            SizedBox(
              height: 120,
              child: _isLoadingPhotos
                  ? const Center(child: CircularProgressIndicator())
                  : _recentPhotos.isEmpty
                      ? const Center(child: Text('لا توجد صور حديثة'))
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _recentPhotos.length,
                          itemBuilder: (listContext, index) {
                            final asset = _recentPhotos[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: GestureDetector(
                                onTap: () async {
                                  final file = await asset.file;
                                  if (file != null && context.mounted) {
                                    Navigator.pop(context, file.path);
                                  }
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AssetThumbnail(asset: asset),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          
          if (_hasPermission)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Divider(),
            ),

          // Attachment Options Grid (Telegram Style)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 24,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              children: [
                _AttachmentIconBtn(
                  icon: Icons.image_rounded,
                  label: 'المعرض',
                  color: Colors.blue,
                  onTap: () => Navigator.pop(context, AttachmentBottomSheetResult.image),
                ),
                _AttachmentIconBtn(
                  icon: Icons.insert_drive_file_rounded,
                  label: 'ملف',
                  color: Colors.orange,
                  onTap: () => Navigator.pop(context, AttachmentBottomSheetResult.file),
                ),
                _AttachmentIconBtn(
                  icon: Icons.poll_rounded,
                  label: 'استطلاع',
                  color: Colors.green,
                  onTap: () => Navigator.pop(context, AttachmentBottomSheetResult.poll),
                ),
                _AttachmentIconBtn(
                  icon: Icons.checklist_rounded,
                  label: 'مهام',
                  color: Colors.teal,
                  onTap: () => Navigator.pop(context, AttachmentBottomSheetResult.checklist),
                ),
                _AttachmentIconBtn(
                  icon: Icons.gif_box_rounded,
                  label: 'GIF',
                  color: Colors.pink,
                  onTap: () => Navigator.pop(context, AttachmentBottomSheetResult.gif),
                ),
                _AttachmentIconBtn(
                  icon: Icons.add_reaction_rounded,
                  label: 'تفاعل',
                  color: Colors.purple,
                  onTap: () => Navigator.pop(context, AttachmentBottomSheetResult.reaction),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AssetThumbnail extends StatelessWidget {
  const AssetThumbnail({super.key, required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
      builder: (_, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return Container(
            width: 120,
            height: 120,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        return Image.memory(
          bytes,
          width: 120,
          height: 120,
          fit: BoxFit.cover,
        );
      },
    );
  }
}

class _AttachmentIconBtn extends StatelessWidget {
  const _AttachmentIconBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
