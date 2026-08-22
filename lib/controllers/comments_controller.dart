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
  final List<Comment> items = [];
  String? nextCursor;
  bool hasMore = true;
  bool isLoading = false;
  bool isLoadingMore = false;
  String? errorMessage;

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
    final comment = await _repository.createComment(
      postId: postId,
      content: content,
    );
    items.add(comment);
    notifyListeners();
    return comment;
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
}
