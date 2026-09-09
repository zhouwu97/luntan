import 'api_client.dart';

class ShareRecordResult {
  const ShareRecordResult({required this.recorded, required this.shareCount});

  final bool recorded;
  final int shareCount;
}

abstract interface class InteractionRepository {
  Future<void> setPostLike({required String postId, required bool active});
  Future<void> setCommentLike({
    required String commentId,
    required bool active,
  });
  Future<void> setCommentDislike({
    required String commentId,
    required bool active,
  });
  Future<void> setBookmark({required String postId, required bool active});
  Future<ShareRecordResult> recordPostShare({required String postId});
  Future<void> setUserFollow({required String userId, required bool active});
  Future<void> setCommunityFollow({
    required String communityId,
    required bool active,
  });
  Future<void> setCommunityMembership({
    required String communityId,
    required bool active,
  });
}

class ApiInteractionRepository implements InteractionRepository {
  ApiInteractionRepository(this._client);

  final ApiClient _client;

  @override
  Future<void> setPostLike({required String postId, required bool active}) =>
      _toggle('/api/v1/posts/$postId/like', active);

  @override
  Future<void> setCommentLike({
    required String commentId,
    required bool active,
  }) => _toggle('/api/v1/comments/$commentId/like', active);

  @override
  Future<void> setCommentDislike({
    required String commentId,
    required bool active,
  }) => _toggle('/api/v1/comments/$commentId/dislike', active);

  @override
  Future<void> setBookmark({required String postId, required bool active}) =>
      _toggle('/api/v1/posts/$postId/bookmark', active);

  @override
  Future<ShareRecordResult> recordPostShare({required String postId}) async {
    final payload = await _client.postJson('/api/v1/posts/$postId/share');
    return ShareRecordResult(
      recorded: payload['recorded'] == true,
      shareCount: (payload['share_count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> setUserFollow({required String userId, required bool active}) =>
      _toggle('/api/v1/users/$userId/follow', active);

  @override
  Future<void> setCommunityFollow({
    required String communityId,
    required bool active,
  }) => _toggle('/api/v1/communities/$communityId/follow', active);

  @override
  Future<void> setCommunityMembership({
    required String communityId,
    required bool active,
  }) => _toggle('/api/v1/communities/$communityId/membership', active);

  Future<void> _toggle(String path, bool active) async {
    if (active) {
      await _client.putJson(path);
    } else {
      await _client.deleteJson(path);
    }
  }
}
