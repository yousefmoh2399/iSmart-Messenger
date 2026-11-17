import '../models/chat_models.dart';

/// Comprehensive utility for Arabic and text normalization and multi-token search.
class ChatSearchUtils {
  ChatSearchUtils._();

  static final RegExp _tashkeelRegex = RegExp(r'[\u064B-\u065F\u0670]');
  static final RegExp _alefRegex = RegExp(r'[\u0622\u0623\u0625\u0671]');
  static final RegExp _multiSpaceRegex = RegExp(r'\s+');

  /// Normalizes Arabic and general text:
  /// - Lowercases and trims
  /// - Strips Tashkeel (diacritics: fatha, damma, kasra, tanween, shadda, sukun)
  /// - Strips Tatweel (kashida: ـ)
  /// - Normalizes Alef forms (أ, إ, آ, ٱ -> ا)
  /// - Normalizes Alef Maqsura (ى -> ي)
  /// - Normalizes Taa Marbuta (ة -> ه)
  /// - Normalizes Hamza on Waw (ؤ -> و)
  /// - Normalizes Hamza on Yaa (ئ -> ي)
  /// - Collapses multiple spaces into single space
  static String normalize(String? text) {
    if (text == null || text.isEmpty) return '';
    var s = text.trim().toLowerCase();

    // Remove tashkeel (diacritics)
    s = s.replaceAll(_tashkeelRegex, '');
    // Remove tatweel / kashida
    s = s.replaceAll('\u0640', '');

    // Alef variations -> ا
    s = s.replaceAll(_alefRegex, '\u0627');

    // Alef Maqsura -> Yaa
    s = s.replaceAll('\u0649', '\u064A');

    // Taa Marbuta -> Haa
    s = s.replaceAll('\u0629', '\u0647');

    // Waw with Hamza -> Waw
    s = s.replaceAll('\u0624', '\u0648');

    // Yaa with Hamza -> Yaa
    s = s.replaceAll('\u0626', '\u064A');

    // Multiple spaces -> single space
    s = s.replaceAll(_multiSpaceRegex, ' ');

    return s.trim();
  }

  /// Checks if [target] matches all whitespace-separated tokens in [query].
  /// Matches case-insensitively and with Arabic normalization.
  static bool matches(String? target, String? query) {
    if (query == null || query.trim().isEmpty) return true;
    if (target == null || target.trim().isEmpty) return false;

    final normQuery = normalize(query);
    if (normQuery.isEmpty) return true;

    final normTarget = normalize(target);
    final tokens = normQuery.split(' ').where((t) => t.isNotEmpty);

    for (final token in tokens) {
      if (!normTarget.contains(token)) {
        return false;
      }
    }
    return true;
  }

  /// Checks if a directory user matches [query] across:
  /// - Display name / Full name
  /// - Username
  /// - Job title
  /// - Role
  /// - Branch code & Branch name
  /// - Department code(s) & Department name(s)
  static bool matchesUser({
    required ChatDirectoryUser user,
    DepartmentSummary? primaryDepartment,
    List<DepartmentSummary> userDepartments = const [],
    BranchSummary? branch,
    required String query,
  }) {
    if (query.trim().isEmpty) return true;

    final buffer = StringBuffer()
      ..write(user.displayName)
      ..write(' ')
      ..write(user.fullName)
      ..write(' ')
      ..write(user.username)
      ..write(' ')
      ..write(user.jobTitle)
      ..write(' ')
      ..write(user.role)
      ..write(' ')
      ..write(user.branchCode)
      ..write(' ');

    if (primaryDepartment != null) {
      buffer.write(primaryDepartment.name);
      buffer.write(' ');
      buffer.write(primaryDepartment.code);
      buffer.write(' ');
    }

    for (final dept in userDepartments) {
      buffer.write(dept.name);
      buffer.write(' ');
      buffer.write(dept.code);
      buffer.write(' ');
    }

    if (branch != null) {
      buffer.write(branch.name);
      buffer.write(' ');
      buffer.write(branch.code);
      buffer.write(' ');
    }

    return matches(buffer.toString(), query);
  }

  /// Checks if a conversation matches [query] across:
  /// - Conversation title/name
  /// - Description
  /// - Last message content & sender name/username
  /// - Member display names, full names, usernames, and job titles
  static bool matchesConversation({
    required ChatConversation conversation,
    required String query,
    String? currentUserId,
  }) {
    if (query.trim().isEmpty) return true;

    final buffer = StringBuffer()
      ..write(conversation.name)
      ..write(' ')
      ..write(conversation.description)
      ..write(' ');

    if (currentUserId != null && currentUserId.isNotEmpty) {
      buffer.write(conversation.displayTitle(currentUserId));
      buffer.write(' ');
    }

    if (conversation.lastMessage != null) {
      buffer.write(conversation.lastMessage!.content);
      buffer.write(' ');
      buffer.write(conversation.lastMessage!.senderName);
      buffer.write(' ');
    }

    for (final member in conversation.members) {
      if (currentUserId != null && member.id == currentUserId) continue;
      buffer.write(member.displayName);
      buffer.write(' ');
      buffer.write(member.fullName);
      buffer.write(' ');
      buffer.write(member.username);
      buffer.write(' ');
      buffer.write(member.jobTitle);
      buffer.write(' ');
      buffer.write(member.branchCode);
      buffer.write(' ');
    }

    return matches(buffer.toString(), query);
  }
}
