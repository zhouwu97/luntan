import 'package:flutter/foundation.dart';

import '../data/api/interaction_repository.dart';
import '../domain/models.dart';

/// 统一处理点赞/收藏的乐观更新、回滚和重复点击锁。
class InteractionController extends ChangeNotifier {
  InteractionController({required InteractionRepository repository})
    : _repository = repository;

  final InteractionRepository _repository;
  final Set<String> _inFlight = <String>{};
  final Set<String> likedCommentIds = <String>{};

  bool isInFlight(String target) => _inFlight.contains(target);

  void clearUserState() {
    _inFlight.clear();
    likedCommentIds.clear();
    notifyListeners();
  }

  Future<void> togglePostLike(Post post) async {
    final key = 'post-like:${post.id}';
    if (!_inFlight.add(key)) return;
    final next = !post.isLiked;
    post.isLiked = next;
    post.likeCount = (post.likeCount + (next ? 1 : -1)).clamp(0, 1 << 30);
    notifyListeners();
    try {
      await _repository.setPostLike(postId: post.id, active: next);
    } catch (_) {
      post.isLiked = !next;
      post.likeCount = (post.likeCount + (next ? -1 : 1)).clamp(0, 1 << 30);
      notifyListeners();
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<void> toggleBookmark(Post post) async {
    final key = 'post-bookmark:${post.id}';
    if (!_inFlight.add(key)) return;
    final next = !post.isBookmarked;
    post.isBookmarked = next;
    post.bookmarkCount = (post.bookmarkCount + (next ? 1 : -1)).clamp(0, 1 << 30);
    notifyListeners();
    try {
      await _repository.setBookmark(postId: post.id, active: next);
    } catch (_) {
      post.isBookmarked = !next;
      post.bookmarkCount = (post.bookmarkCount + (next ? -1 : 1)).clamp(0, 1 << 30);
      notifyListeners();
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<void> toggleCommentLike(Comment comment) async {
    final key = 'comment-like:${comment.id}';
    if (!_inFlight.add(key)) return;
    final next = likedCommentIds.add(comment.id);
    if (!next) likedCommentIds.remove(comment.id);
    notifyListeners();
    try {
      await _repository.setCommentLike(commentId: comment.id, active: next);
    } catch (_) {
      if (next) {
        likedCommentIds.remove(comment.id);
      } else {
        likedCommentIds.add(comment.id);
      }
      notifyListeners();
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }
}
