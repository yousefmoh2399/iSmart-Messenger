import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/admin_announcement.dart';
import '../../../shared/providers/providers.dart';

class AnnouncementsController extends AsyncNotifier<List<AdminAnnouncement>> {
  void resetState() { state = const AsyncLoading(); }

  @override
  Future<List<AdminAnnouncement>> build() async {
    ref.watch(serverRecoveryRevisionProvider);
    return ref
        .read(announcementRepositoryProvider)
        .fetchAnnouncements(includeInactive: false);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(
      await ref
          .read(announcementRepositoryProvider)
          .fetchAnnouncements(includeInactive: false),
    );
  }

  void applyAnnouncement(AdminAnnouncement announcement) {
    final current = state.valueOrNull ?? const <AdminAnnouncement>[];
    final next = current.where((item) => item.id != announcement.id).toList();
    if (announcement.isActive) {
      next.add(announcement);
    }
    next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = AsyncData(next);
  }
}

class AdminAnnouncementsController extends AsyncNotifier<List<AdminAnnouncement>> {
  void resetState() { state = const AsyncLoading(); }

  @override
  Future<List<AdminAnnouncement>> build() async {
    ref.watch(serverRecoveryRevisionProvider);
    return ref
        .read(announcementRepositoryProvider)
        .fetchAnnouncements(includeInactive: true);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(
      await ref
          .read(announcementRepositoryProvider)
          .fetchAnnouncements(includeInactive: true),
    );
  }

  void applyAnnouncement(AdminAnnouncement announcement) {
    final current = state.valueOrNull ?? const <AdminAnnouncement>[];
    final exists = current.any((item) => item.id == announcement.id);
    final next = exists
        ? current
              .map((item) => item.id == announcement.id ? announcement : item)
              .toList()
        : [...current, announcement];
    next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = AsyncData(next);
  }
}







