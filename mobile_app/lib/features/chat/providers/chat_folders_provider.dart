import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../models/chat_models.dart';

class ChatFoldersController extends AsyncNotifier<List<ChatFolder>> {
  @override
  FutureOr<List<ChatFolder>> build() async {
    final repository = ref.read(chatRepositoryProvider);
    return repository.getFolders();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(chatRepositoryProvider).getFolders(),
    );
  }

  Future<void> createFolder(
    String name, {
    String? icon,
    List<String> conversationIds = const [],
  }) async {
    final repository = ref.read(chatRepositoryProvider);
    final folder = await repository.createFolder(
      name: name,
      icon: icon,
      conversationIds: conversationIds,
    );
    state = AsyncData([...state.valueOrNull ?? [], folder]);
  }

  Future<void> updateFolder(
    String folderId, {
    String? name,
    String? icon,
    List<String>? conversationIds,
  }) async {
    final repository = ref.read(chatRepositoryProvider);
    final updated = await repository.updateFolder(
      folderId: folderId,
      name: name,
      icon: icon,
      conversationIds: conversationIds,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncData([
      for (final f in current)
        if (f.id == folderId) updated else f,
    ]);
  }

  Future<void> updateFolderMembership({
    required String folderId,
    required String conversationId,
    required bool add,
  }) async {
    final updated = await ref.read(chatRepositoryProvider).updateFolderMembership(
      folderId: folderId,
      conversationId: conversationId,
      add: add,
    );
    final current = state.valueOrNull ?? [];
    state = AsyncData([
      for (final folder in current)
        if (folder.id == folderId) updated else folder,
    ]);
  }

  Future<void> removeConversationFromAllFolders(String conversationId) async {
    final folders = state.valueOrNull ?? [];
    for (final folder in folders) {
      if (folder.conversationIds.contains(conversationId)) {
        await updateFolderMembership(
          folderId: folder.id,
          conversationId: conversationId,
          add: false,
        );
      }
    }
  }

  Future<void> deleteFolder(String folderId) async {
    final repository = ref.read(chatRepositoryProvider);
    await repository.deleteFolder(folderId);
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((f) => f.id != folderId).toList());
  }

  Future<void> reorderFolders(List<String> folderIds) async {
    final repository = ref.read(chatRepositoryProvider);
    final folders = await repository.reorderFolders(folderIds);
    state = AsyncData(folders);
  }
}

final chatFoldersProvider =
    AsyncNotifierProvider<ChatFoldersController, List<ChatFolder>>(() {
      return ChatFoldersController();
    });
