import 'package:flutter/foundation.dart';

import '../data/api/comment_repository.dart';
import '../domain/models.dart';

class CommentsController extends ChangeNotifier {
  CommentsController({
    required CommentRepository repository,
    required this.postId,
  }) : _repository = repository;

  final CommentRepository _repository;
  final String postId;

  /// 暴露给楼中楼视图做独立的分页拉取。
  CommentRepository get repository => _repository;
  final List<Comment> items = [];
  String? nextCursor;
  bool hasMore = true;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? errorMessage;
  Future<Comment>? _addInFlight;
  String? _pendingCommentIdempotencyKey;
  final Map<String, Future<Comment>> _replyInFlight = {};
  final Map<String, String> _pendingReplyIdempotencyKeys = {};
  int _generation = 0;

  Future<void> load({bool force = false}) async {
    if (isLoading && !force) return;
    final requestGeneration = ++_generation;
    isLoading = true;
    isLoadingMore = false;
    errorMessage = null;
    notifyListeners();
    try {
      final page = await _repository.listComments(postId: postId);
      if (requestGeneration != _generation) return;
      _replaceItems(page.items);
      nextCursor = page.nextCursor;
      hasMore = page.hasMore && page.nextCursor != null;
    } catch (error) {
      if (requestGeneration != _generation) return;
      errorMessage = '评论加载失败，请重试';
      rethrow;
    } finally {
      if (requestGeneration == _generation) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() => load(force: true);

  Future<void> loadMore() async {
    if (isLoading || isLoadingMore || !hasMore || nextCursor == null) return;
    final requestGeneration = _generation;
    final cursor = nextCursor!;
    isLoadingMore = true;
    errorMessage = null;
    notifyListeners();
    try {
      final page = await _repository.listComments(
        postId: postId,
        cursor: cursor,
      );
      if (requestGeneration != _generation || cursor != nextCursor) return;
      _mergeItems(page.items);
      nextCursor = page.nextCursor;
      hasMore = page.hasMore && page.nextCursor != cursor;
    } catch (error) {
      if (requestGeneration != _generation) return;
      errorMessage = '更多评论加载失败，请重试';
      rethrow;
    } finally {
      if (requestGeneration == _generation) {
        isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  void _replaceItems(Iterable<Comment> next) {
    items
      ..clear()
      ..addAll(next);
    _sortAndDedupe();
  }

  void _mergeItems(Iterable<Comment> next) {
    items.addAll(next);
    _sortAndDedupe();
  }

  void _sortAndDedupe() {
    final byId = <String, Comment>{for (final item in items) item.id: item};
    items
      ..clear()
      ..addAll(byId.values)
      ..sort(_compareByCreatedAt);
  }

  Future<Comment> addComment(String content) {
    final running = _addInFlight;
    if (running != null) return running;
    late final Future<Comment> future;
    final key = _pendingCommentIdempotencyKey ??= _newIdempotencyKey('comment');
    final create = _repository is IdempotentCommentRepository
        ? (_repository as IdempotentCommentRepository)
              .createCommentWithIdempotency(
                postId: postId,
                content: content,
                idempotencyKey: key,
              )
        : _repository.createComment(postId: postId, content: content);
    future = create
        .then((comment) {
          _pendingCommentIdempotencyKey = null;
          _mergeItems([comment]);
          notifyListeners();
          return comment;
        })
        .whenComplete(() {
          if (identical(_addInFlight, future)) _addInFlight = null;
        });
    _addInFlight = future;
    return future;
  }

  Future<Comment> replyTo(
    Comment parent,
    String content, {
    String? replyToUserId,
  }) {
    final running = _replyInFlight[parent.id];
    if (running != null) return running;
    final key = _pendingReplyIdempotencyKeys[parent.id] ??= _newIdempotencyKey(
      'reply',
    );
    final create = _repository is IdempotentCommentRepository
        ? (_repository as IdempotentCommentRepository)
              .createReplyWithIdempotency(
                commentId: parent.id,
                content: content,
                idempotencyKey: key,
                replyToUserId: replyToUserId,
              )
        : _repository.createReply(
            commentId: parent.id,
            content: content,
            replyToUserId: replyToUserId,
          );
    late final Future<Comment> future;
    future = create
        .then((comment) {
          _pendingReplyIdempotencyKeys.remove(parent.id);
          _mergeItems([comment]);
          // 服务端返回新回复，不会重复返回父评论；本地同步楼中楼入口数量。
          parent.replyCount += 1;
          for (final item in items) {
            if (item.id == parent.id && !identical(item, parent)) {
              item.replyCount += 1;
            }
          }
          notifyListeners();
          return comment;
        })
        .whenComplete(() {
          if (identical(_replyInFlight[parent.id], future)) {
            _replyInFlight.remove(parent.id);
          }
        });
    _replyInFlight[parent.id] = future;
    return future;
  }

  String _newIdempotencyKey(String prefix) =>
      '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-${identityHashCode(this)}';

  Future<void> delete(Comment comment) async {
    await _repository.deleteComment(comment.id);
    items.removeWhere((item) => item.id == comment.id);
    notifyListeners();
  }

  Future<Comment?> edit(Comment comment, String content) async {
    final repository = _repository;
    if (repository is! CommentMutationRepository) return null;
    final mutationRepository = repository as CommentMutationRepository;
    final updated = await mutationRepository.updateComment(
      commentId: comment.id,
      content: content,
    );
    final index = items.indexWhere((item) => item.id == comment.id);
    if (index >= 0) items[index] = updated;
    notifyListeners();
    return updated;
  }

  int _compareByCreatedAt(Comment a, Comment b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime == 0 ? a.id.compareTo(b.id) : byTime;
  }
}
