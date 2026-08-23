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

  Future<void> load() async {
    if (isLoading) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final page = await _repository.listComments(postId: postId);
      items
        ..clear()
        ..addAll(page.items);
      nextCursor = page.nextCursor;
      hasMore = page.hasMore;
    } catch (error) {
      errorMessage = '评论加载失败，请重试';
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  Future<void> loadMore() async {
    if (isLoading || isLoadingMore || !hasMore) return;
    isLoadingMore = true;
    errorMessage = null;
    notifyListeners();
    try {
      final page = await _repository.listComments(
        postId: postId,
        cursor: nextCursor,
      );
      items.addAll(page.items);
      nextCursor = page.nextCursor;
      hasMore = page.hasMore;
    } catch (error) {
      errorMessage = '更多评论加载失败，请重试';
      rethrow;
    } finally {
      isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<Comment> addComment(String content) async {
    final running = _addInFlight;
    if (running != null) return running;
    late final Future<Comment> future;
    future = _repository.createComment(
      postId: postId,
      content: content,
    ).then((comment) {
      items.add(comment);
      notifyListeners();
      return comment;
    }).whenComplete(() {
      if (identical(_addInFlight, future)) _addInFlight = null;
    });
    _addInFlight = future;
    return future;
  }

  Future<Comment> replyTo(
    Comment parent,
    String content, {
    String? replyToUserId,
  }) async {
    final comment = await _repository.createReply(
      commentId: parent.id,
      content: content,
      replyToUserId: replyToUserId,
    );
    items.add(comment);
    notifyListeners();
    return comment;
  }

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
}
