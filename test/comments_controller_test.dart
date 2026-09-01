import 'dart:async';

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

  test(
    'CommentsController prevents duplicate replies while request is in flight',
    () async {
      final repository = _FakeCommentRepository();
      final controller = CommentsController(
        repository: repository,
        postId: 'p1',
      );
      final parent = repository.comment('parent', 'parent');

      final first = controller.replyTo(parent, 'reply');
      final second = controller.replyTo(parent, 'reply');

      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      expect(repository.replyCalls, 1);
    },
  );

  test(
    'CommentsController deduplicates repeated offset pages',
    () async {
      final repository = _FakeCommentRepository()..repeatOffsetPage = true;
      final controller = CommentsController(
        repository: repository,
        postId: 'p1',
      );

      await controller.load();
      await controller.loadMore();

      expect(controller.items, hasLength(1));
      expect(controller.items.single.id, 'c1');
      expect(controller.hasMore, isFalse);
    },
  );

  test('CommentsController ignores a stale load after refresh', () async {
    final pending = Completer<CommentPage>();
    final repository = _FakeCommentRepository()
      ..delayedInitialLoad = pending
      ..returnFreshOnNextLoad = true;
    final controller = CommentsController(repository: repository, postId: 'p1');

    final staleLoad = controller.load();
    await Future<void>.delayed(Duration.zero);
    final freshLoad = controller.refresh();
    await freshLoad;
    pending.complete(
      CommentPage(items: [repository.comment('stale', 'stale')]),
    );
    await staleLoad;

    expect(controller.items, hasLength(1));
    expect(controller.items.single.id, 'fresh');
  });

  test('CommentsController reloads floors with sort and author filter', () async {
    final repository = _FakeCommentRepository();
    final controller = CommentsController(repository: repository, postId: 'p1');
    await controller.load();
    expect(repository.lastSort, CommentSort.desc);
    expect(repository.lastAuthorId, isNull);
    expect(repository.lastOffset, 0);

    controller.setSort(CommentSort.hot);
    await Future<void>.delayed(Duration.zero);
    expect(repository.lastSort, CommentSort.hot);
    expect(controller.sort, CommentSort.hot);

    controller.setAuthorFilter('u9');
    await Future<void>.delayed(Duration.zero);
    expect(repository.lastAuthorId, 'u9');

    controller.setAuthorFilter(null);
    await Future<void>.delayed(Duration.zero);
    expect(repository.lastAuthorId, isNull);
  });

  test(
    'CommentsController syncs reply count and preview on the root floor',
    () async {
      final repository = _FakeCommentRepository();
      final controller = CommentsController(
        repository: repository,
        postId: 'p1',
      );
      await controller.load();
      final parent = controller.items.single;

      await controller.replyTo(parent, 'reply');

      expect(controller.items.single.replyCount, 1);
      expect(controller.items.single.replyPreview, hasLength(1));
      expect(controller.items.single.replyPreview.single.content, 'reply');
    },
  );

  test('CommentsController inserts a new floor by server floor number', () async {
    final repository = _FakeCommentRepository();
    final controller = CommentsController(repository: repository, postId: 'p1');
    await controller.load();
    await controller.loadMore();
    // items: c1 (floor 1), c2 (floor 3)
    repository.nextCreatedFloor = 2;
    await controller.addComment('inserted');

    expect(controller.items.map((item) => item.id).toList(), [
      'c3',
      'c1',
      'c2',
    ]);
  });
}

class _FakeCommentRepository implements CommentRepository {
  bool failFirstLoad = false;
  bool repeatOffsetPage = false;
  Completer<CommentPage>? delayedInitialLoad;
  bool returnFreshOnNextLoad = false;
  int replyCalls = 0;
  CommentSort? lastSort;
  String? lastAuthorId;
  int lastOffset = -1;
  int? nextCreatedFloor;

  Comment comment(String id, String content, {int? floor}) => Comment(
    id: id,
    postId: 'p1',
    authorId: 'u1',
    content: content,
    floor: floor,
    createdAt: DateTime.utc(2026, 8, 22),
    updatedAt: DateTime.utc(2026, 8, 22),
  );

  @override
  Future<CommentPage> listComments({
    required String postId,
    int limit = 20,
    int offset = 0,
    CommentSort? sort,
    String? authorId,
  }) async {
    lastSort = sort;
    lastAuthorId = authorId;
    lastOffset = offset;
    if (offset == 0 && delayedInitialLoad != null) {
      final pending = delayedInitialLoad!;
      delayedInitialLoad = null;
      return pending.future;
    }
    if (offset == 0 && returnFreshOnNextLoad) {
      returnFreshOnNextLoad = false;
      return CommentPage(items: [comment('fresh', 'fresh')], hasMore: false);
    }
    if (failFirstLoad) {
      failFirstLoad = false;
      throw StateError('network');
    }
    if (offset == 0) {
      return CommentPage(
        items: [comment('c1', 'first', floor: 1)],
        hasMore: true,
        total: 2,
      );
    }
    if (repeatOffsetPage) {
      return CommentPage(
        items: [comment('c1', 'duplicate', floor: 1)],
        hasMore: false,
        total: 2,
      );
    }
    return CommentPage(
      items: [comment('c2', 'second', floor: 3)],
      hasMore: false,
      total: 3,
    );
  }

  @override
  Future<Comment> createComment({
    required String postId,
    required String content,
    String? parentId,
    String? replyToUserId,
    List<String> mediaIds = const [],
    String? stickerId,
  }) async => comment('c3', content, floor: nextCreatedFloor);

  @override
  Future<Comment> createReply({
    required String commentId,
    required String content,
    String? replyToUserId,
    List<String> mediaIds = const [],
    String? stickerId,
  }) async {
    replyCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return comment('c4', content);
  }

  @override
  Future<CommentPage> listReplies({
    required String commentId,
    String? cursor,
    int limit = 20,
  }) async {
    return CommentPage(items: [comment('r1', 'thread reply')], hasMore: false);
  }

  @override
  Future<void> deleteComment(String commentId) async {}
}
