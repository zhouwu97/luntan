import 'package:flutter_test/flutter_test.dart';

import 'package:luntan/controllers/comments_controller.dart';
import 'package:luntan/data/api/comment_repository.dart';
import 'package:luntan/domain/models.dart';

void main() {
  test(
    'CommentsController loads, paginates, appends and deletes comments',
    () async {
      final repository = _FakeCommentRepository();
      final controller = CommentsController(
        repository: repository,
        postId: 'p1',
      );

      await controller.load();
      expect(controller.items, hasLength(1));
      expect(controller.hasMore, isTrue);
      await controller.loadMore();
      expect(controller.items, hasLength(2));
      await controller.addComment('new');
      expect(controller.items, hasLength(3));
      await controller.delete(controller.items.last);
      expect(controller.items, hasLength(2));
    },
  );

  test('CommentsController exposes retryable load failure', () async {
    final repository = _FakeCommentRepository()..failFirstLoad = true;
    final controller = CommentsController(repository: repository, postId: 'p1');
    await expectLater(controller.load(), throwsA(isA<StateError>()));
    expect(controller.errorMessage, isNotNull);
    await controller.load();
    expect(controller.items, hasLength(1));
  });
}

class _FakeCommentRepository implements CommentRepository {
  bool failFirstLoad = false;
  int page = 0;

  Comment _comment(String id, String content) => Comment(
    id: id,
    postId: 'p1',
    authorId: 'u1',
    content: content,
    createdAt: DateTime.utc(2026, 8, 22),
    updatedAt: DateTime.utc(2026, 8, 22),
  );

  @override
  Future<CommentPage> listComments({
    required String postId,
    String? cursor,
    int limit = 20,
  }) async {
    if (failFirstLoad) {
      failFirstLoad = false;
      throw StateError('network');
    }
    page++;
    if (page == 1) {
      return CommentPage(
        items: [_comment('c1', 'first')],
        nextCursor: 'c1',
        hasMore: true,
      );
    }
    return CommentPage(items: [_comment('c2', 'second')], hasMore: false);
  }

  @override
  Future<Comment> createComment({
    required String postId,
    required String content,
    String? parentId,
    String? replyToUserId,
  }) async => _comment('c3', content);

  @override
  Future<Comment> createReply({
    required String commentId,
    required String content,
    String? replyToUserId,
  }) async => _comment('c4', content);

  @override
  Future<CommentPage> listReplies({
    required String commentId,
    String? cursor,
    int limit = 20,
  }) async {
    return CommentPage(items: [_comment('r1', 'thread reply')], hasMore: false);
  }

  @override
  Future<void> deleteComment(String commentId) async {}
}
