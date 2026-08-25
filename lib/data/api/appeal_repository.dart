import 'api_client.dart';

/// 处罚动作详情；它是申诉的唯一发起对象，避免用户自由填写举报目标。
class ModerationAction {
  const ModerationAction({
    required this.id,
    required this.action,
    required this.reason,
    required this.appealable,
    required this.targetType,
    required this.targetId,
    required this.targetTitle,
    required this.targetContent,
    required this.mediaIds,
    required this.createdAt,
  });

  final String id;
  final String action;
  final String reason;
  final bool appealable;
  final String targetType;
  final String targetId;
  final String targetTitle;
  final String targetContent;
  final List<String> mediaIds;
  final DateTime createdAt;
}

class ModerationAppeal {
  const ModerationAppeal({
    required this.id,
    required this.moderationActionId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.description,
    required this.status,
    required this.reviewerNote,
    required this.createdAt,
    this.reviewedAt,
    this.updatedAt,
    this.action,
    this.actionReason,
    this.targetTitle,
    this.targetContent,
    this.mediaIds = const [],
  });

  final String id;
  final String moderationActionId;
  final String targetType;
  final String targetId;
  final String reason;
  final String description;
  final String status;
  final String reviewerNote;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final DateTime? updatedAt;
  final String? action;
  final String? actionReason;
  final String? targetTitle;
  final String? targetContent;
  final List<String> mediaIds;

  bool get isPending => status == 'pending' || status == 'reviewing';
}

class AppealPage {
  const AppealPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ModerationAppeal> items;
  final String? nextCursor;
  final bool hasMore;
}

class ModerationAppealPage extends AppealPage {
  const ModerationAppealPage({
    required super.items,
    super.nextCursor,
    super.hasMore,
  });
}

class AppealRepository {
  AppealRepository(this._client);

  final ApiClient _client;

  Future<ModerationAction> getModerationAction(String actionId) async {
    final payload = await _client.getJson(
      '/api/v1/moderation-actions/$actionId',
    );
    return _actionFromJson(payload);
  }

  Future<AppealPage> listAppeals({String? status, int limit = 20}) async {
    final payload = await _client.getJson(
      '/api/v1/appeals',
      queryParameters: {
        'limit': '$limit',
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    return AppealPage(
      items: _appealList(payload['items']),
      nextCursor: payload['next_cursor'] as String?,
      hasMore: payload['has_more'] == true,
    );
  }

  Future<ModerationAppeal> getAppeal(String appealId) async {
    final payload = await _client.getJson('/api/v1/appeals/$appealId');
    return _appealFromJson(payload);
  }

  Future<ModerationAppeal> createAppeal({
    required String moderationActionId,
    required String reason,
    String description = '',
    List<String> mediaIds = const [],
  }) async {
    final payload = await _client.postJson(
      '/api/v1/moderation-actions/$moderationActionId/appeals',
      body: {
        'reason': reason,
        'description': description,
        'media_ids': mediaIds,
      },
    );
    final appealId = _string(payload['id']);
    if (appealId.isEmpty) {
      throw const ApiException(type: ApiErrorType.unknown, message: '申诉响应格式错误');
    }
    return getAppeal(appealId);
  }

  Future<ModerationAppealPage> listModerationAppeals({
    String? status,
    int limit = 20,
  }) async {
    final payload = await _client.getJson(
      '/api/v1/moderation/appeals',
      queryParameters: {
        'limit': '$limit',
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    return ModerationAppealPage(
      items: _appealList(payload['items']),
      nextCursor: payload['next_cursor'] as String?,
      hasMore: payload['has_more'] == true,
    );
  }

  Future<ModerationAppeal> getModerationAppeal(String appealId) async {
    final payload = await _client.getJson(
      '/api/v1/moderation/appeals/$appealId',
    );
    return _appealFromJson(payload);
  }

  Future<void> reviewAppeal({
    required String appealId,
    required String result,
    String note = '',
  }) async {
    await _client.postJson(
      '/api/v1/moderation/appeals/$appealId/review',
      body: {'result': result, 'note': note},
    );
  }

  ModerationAction _actionFromJson(Map<String, dynamic> value) {
    return ModerationAction(
      id: _string(value['id']),
      action: _string(value['action']),
      reason: _string(value['reason']),
      appealable: value['appealable'] == true,
      targetType: _string(value['target_type']),
      targetId: _string(value['target_id']),
      targetTitle: _string(value['target_title']),
      targetContent: _string(value['target_content']),
      mediaIds: _stringList(value['media_ids']),
      createdAt: _date(value['created_at']),
    );
  }

  List<ModerationAppeal> _appealList(dynamic raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((item) => _appealFromJson(Map<String, dynamic>.from(item)))
            .toList()
      : <ModerationAppeal>[];

  ModerationAppeal _appealFromJson(Map<String, dynamic> value) {
    return ModerationAppeal(
      id: _string(value['id']),
      moderationActionId: _string(value['moderation_action_id']),
      targetType: _string(value['target_type']),
      targetId: _string(value['target_id']),
      reason: _string(value['reason']),
      description: _string(value['description']),
      status: _string(value['status']),
      reviewerNote: _string(value['reviewer_note']),
      createdAt: _date(value['created_at']),
      reviewedAt: _nullableDate(value['reviewed_at']),
      updatedAt: _nullableDate(value['updated_at']),
      action: _nullableString(value['action']),
      actionReason: _nullableString(value['action_reason']),
      targetTitle: _nullableString(value['target_title']),
      targetContent: _nullableString(value['target_content']),
      mediaIds: _stringList(value['media_ids']),
    );
  }

  String _string(dynamic value) => value is String ? value : '';

  String? _nullableString(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;

  List<String> _stringList(dynamic value) => value is List
      ? value.whereType<String>().where((item) => item.isNotEmpty).toList()
      : <String>[];

  DateTime _date(dynamic value) => value is String
      ? DateTime.tryParse(value) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
      : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  DateTime? _nullableDate(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;
}
