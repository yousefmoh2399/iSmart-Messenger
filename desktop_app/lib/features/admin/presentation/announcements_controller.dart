import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/admin_announcement.dart';
import '../../../shared/providers/providers.dart';

class AnnouncementsController extends AsyncNotifier<List<AdminAnnouncement>> {
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
}

class AdminAnnouncementsController
    extends AsyncNotifier<List<AdminAnnouncement>> {
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
}
