import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class GifPickerPanel extends StatefulWidget {
  const GifPickerPanel({super.key});

  @override
  State<GifPickerPanel> createState() => _GifPickerPanelState();
}

class _GifPickerPanelState extends State<GifPickerPanel> {
  final _searchController = TextEditingController();
  List<String> _gifUrls = [];
  bool _isLoading = false;
  Timer? _debounce;
  final String _tenorKey = 'LIVDSRZULELA';

  @override
  void initState() {
    super.initState();
    _fetchGifs(''); // trending
  }

  Future<void> _fetchGifs(String query) async {
    setState(() => _isLoading = true);
    try {
      final endpoint = query.isEmpty ? 'featured' : 'search';
      final url = 'https://tenor.googleapis.com/v2/$endpoint?key=$_tenorKey&client_key=ismart&limit=30${query.isNotEmpty ? '&q=$query' : ''}';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List;
        
        final urls = results.map((result) {
          final mediaFormats = result['media_formats'];
          // Try to get tinygif or nanogif for faster loading, fallback to gif
          if (mediaFormats['tinygif'] != null) {
            return mediaFormats['tinygif']['url'] as String;
          }
          if (mediaFormats['gif'] != null) {
            return mediaFormats['gif']['url'] as String;
          }
          return '';
        }).where((url) => url.isNotEmpty).toList();

        if (mounted) {
          setState(() {
            _gifUrls = urls;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching GIFs: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchGifs(query);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'البحث عن GIF...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: _isLoading && _gifUrls.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _gifUrls.length,
                    itemBuilder: (context, index) {
                      final url = _gifUrls[index];
                      return InkWell(
                        onTap: () {
                          Navigator.of(context).pop(url);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  value: progress.expectedTotalBytes != null
                                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                      : null,
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
