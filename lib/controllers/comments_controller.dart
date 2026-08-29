import 'package:flutter/foundation.dart';

import '../data/api/comment_repository.dart';
import '../domain/models.dart';

/// 楼层制评论控制器：items 只含服务端排好序的根评论楼层，
/// 回复通过 Comment.replyPreview 内嵌或楼中楼视图独立分页拉取。
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
  CommentSort sort = CommentSort.asc;

  /// 只看楼主：作者 user id，null 表示查看全部楼层。
  String? authorFilter;
  int total = 0;
  bool hasMore = true;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? errorMessage;
  Future<Comment>? _addInFlight;
  String? _pendingCommentIdempotencyKey;
  final Map<String, Future<Comment>> _replyInFlight = {};
  final Map<String, String> _pendingReplyIdempotencyKeys = {};
  int _generation = 0;
  int _nextOffset = 0;

  void setSort(CommentSort value) {
    if (sort == value) return;
    sort = value;
    load(force: true);
  }

  void setAuthorFilter(String? authorId) {
    if (authorFilter == authorId) return;
    authorFilter = authorId;
    load(force: true);
  }

  Future<void> load({bool force = false}) async {
    if (isLoading && !force) return;
    final requestGeneration = ++_generation;
    isLoading = true;
    isLoadingMore = false;
    errorMessage = null;
    notifyListeners();
    try {
      final page = await _repository.listComments(
        postId: postId,
        sort: sort,
        authorId: authorFilter,
      );
      if (requestGeneration != _generation) return;
      _replaceItems(page.items);
      total = page.total;
      hasMore = page.hasMore;
      _nextOffset = items.length;
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
    if (isLoading || isLoadingMore || !hasMore) return;
    final requestGeneration = _generation;
    final offset = _nextOffset;
    isLoadingMore = true;
    errorMessage = null;
    notifyListeners();
    try {
      final page = await _repository.listComments(
        postId: postId,
        offset: offset,
        sort: sort,
        authorId: authorFilter,
      );
      if (requestGeneration != _generation) return;
      _mergeItems(page.items);
      total = page.total;
      hasMore = page.hasMore;
      _nextOffset = offset + page.items.length;
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

  /// 楼层顺序由服务端决定，客户端只按 id 去重、保持服务端顺序。
  void _replaceItems(Iterable<Comment> next) {
    final byId = <String, Comment>{for (final item in next) item.id: item};
    items
      ..clear()
      ..addAll(byId.values);
  }

  void _mergeItems(Iterable<Comment> next) {
    for (final item in next) {
      final index = items.indexWhere((existing) => existing.id == item.id);
      if (index == -1) {
        items.add(item);
      } else {
        items[index] = item;
      }
    }
  }

  Future<Comment> addComment(
    String content, {
    List<String> mediaIds = const [],
    String? stickerId,
  }) {
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
                mediaIds: mediaIds,
                stickerId: stickerId,
              )
        : _repository.createComment(
            postId: postId,
            content: content,
            mediaIds: mediaIds,
            stickerId: stickerId,
          );
    future = create
        .then((comment) {
          _pendingCommentIdempotencyKey = null;
          _insertFloorItem(comment);
          total += 1;
          notifyListeners();
          return comment;
        })
        .whenComplete(() {
          if (identical(_addInFlight, future)) _addInFlight = null;
        });
    _addInFlight = future;
    return future;
  }

  /// 新楼层按服务端楼层号插入到正确位置；hot 排序或缺失楼层号时追加尾部。
  void _insertFloorItem(Comment comment) {
    final existingIndex = items.indexWhere((item) => item.id == comment.id);
    if (existingIndex != -1) {
      items[existingIndex] = comment;
      return;
    }
    final floor = comment.floor;
    if (floor == null || sort == CommentSort.hot) {
      items.add(comment);
      return;
    }
    final index = items.indexWhere((item) {
      final itemFloor = item.floor;
      if (itemFloor == null) return false;
      return sort == CommentSort.desc ? itemFloor < floor : itemFloor > floor;
    });
    if (index == -1) {
      items.add(comment);
    } else {
      items.insert(index, comment);
    }
  }

  Future<Comment> replyTo(
    Comment parent,
    String content, {
    String? replyToUserId,
    List<String> mediaIds = const [],
    String? stickerId,
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
                mediaIds: mediaIds,
                stickerId: stickerId,
              )
        : _repository.createReply(
            commentId: parent.id,
            content: content,
            replyToUserId: replyToUserId,
            mediaIds: mediaIds,
            stickerId: stickerId,
          );
    late final Future<Comment> future;
    future = create
        .then((comment) {
          _pendingReplyIdempotencyKeys.remove(parent.id);
          // 服务端返回新回复；本地同步楼层回复计数与预览。
          final rootId = parent.rootId ?? parent.id;
          for (final item in items) {
            if (item.id == rootId) {
              item.replyCount += 1;
              item.replyPreview = [...item.replyPreview, comment];
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
    final index = items.indexWhere((item) => item.id == comment.id);
    if (index >= 0) {
      items.removeAt(index);
      total = (total - 1).clamp(0, 1 << 30);
    } else if (comment.parentId != null) {
      final rootId = comment.rootId ?? comment.parentId;
      for (final item in items) {
        if (item.id == rootId) {
          item.replyCount = (item.replyCount - 1).clamp(0, 1 << 30);
          item.replyPreview = item.replyPreview
              .where((reply) => reply.id != comment.id)
              .toList();
        }
      }
    }
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
    if (index >= 0) {
      if (updated.replyPreview.isEmpty && comment.replyPreview.isNotEmpty) {
        updated.replyPreview = comment.replyPreview;
      }
      items[index] = updated;
    } else {
      for (final item in items) {
        final replyIndex = item.replyPreview.indexWhere(
          (reply) => reply.id == comment.id,
        );
        if (replyIndex >= 0) {
          item.replyPreview = [...item.replyPreview];
          item.replyPreview[replyIndex] = updated;
        }
      }
    }
    notifyListeners();
    return updated;
  }
}
