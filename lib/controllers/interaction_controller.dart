import 'package:flutter/foundation.dart';

import '../data/api/interaction_repository.dart';
import '../domain/models.dart';

/// 统一处理点赞/收藏的乐观更新、回滚和重复点击锁。
class InteractionController extends ChangeNotifier {
  InteractionController({required InteractionRepository repository})
    : _repository = repository;

  final InteractionRepository _repository;
  final Set<String> _inFlight = <String>{};

  bool isInFlight(String target) => _inFlight.contains(target);

  void clearUserState() {
    _inFlight.clear();
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
    post.bookmarkCount = (post.bookmarkCount + (next ? 1 : -1)).clamp(
      0,
      1 << 30,
    );
    notifyListeners();
    try {
      await _repository.setBookmark(postId: post.id, active: next);
    } catch (_) {
      post.isBookmarked = !next;
      post.bookmarkCount = (post.bookmarkCount + (next ? -1 : 1)).clamp(
        0,
        1 << 30,
      );
      notifyListeners();
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// 收藏夹选择器完成后同步服务端的收藏事实，只有从未收藏到收藏或反向变化时
  /// 才调整帖子公开的 bookmark_count，避免一个帖子进入多个收藏夹造成重复计数。
  void applyBookmarkState(Post post, bool active) {
    if (post.isBookmarked == active) return;
    post.isBookmarked = active;
    post.bookmarkCount = (post.bookmarkCount + (active ? 1 : -1)).clamp(
      0,
      1 << 30,
    );
    notifyListeners();
  }

  Future<void> toggleCommentLike(Comment comment) async {
    final key = 'comment-like:${comment.id}';
    if (!_inFlight.add(key)) return;
    final next = !comment.isLiked;
    comment.isLiked = next;
    comment.likeCount = (comment.likeCount + (next ? 1 : -1)).clamp(0, 1 << 30);
    // 点赞与点踩互斥：激活点赞时同步取消本地点踩状态。
    final dislikeCleared = next && comment.isDisliked;
    if (dislikeCleared) {
      comment.isDisliked = false;
      comment.dislikeCount = (comment.dislikeCount - 1).clamp(0, 1 << 30);
    }
    notifyListeners();
    try {
      await _repository.setCommentLike(commentId: comment.id, active: next);
    } catch (_) {
      comment.isLiked = !next;
      comment.likeCount = (comment.likeCount + (next ? -1 : 1)).clamp(
        0,
        1 << 30,
      );
      if (dislikeCleared) {
        comment.isDisliked = true;
        comment.dislikeCount = (comment.dislikeCount + 1).clamp(0, 1 << 30);
      }
      notifyListeners();
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<void> toggleCommentDislike(Comment comment) async {
    final key = 'comment-dislike:${comment.id}';
    if (!_inFlight.add(key)) return;
    final next = !comment.isDisliked;
    comment.isDisliked = next;
    comment.dislikeCount = (comment.dislikeCount + (next ? 1 : -1)).clamp(
      0,
      1 << 30,
    );
    // 点踩与点赞互斥：激活点踩时同步取消本地点赞状态。
    final likeCleared = next && comment.isLiked;
    if (likeCleared) {
      comment.isLiked = false;
      comment.likeCount = (comment.likeCount - 1).clamp(0, 1 << 30);
    }
    notifyListeners();
    try {
      await _repository.setCommentDislike(commentId: comment.id, active: next);
    } catch (_) {
      comment.isDisliked = !next;
      comment.dislikeCount = (comment.dislikeCount + (next ? -1 : 1)).clamp(
        0,
        1 << 30,
      );
      if (likeCleared) {
        comment.isLiked = true;
        comment.likeCount = (comment.likeCount + 1).clamp(0, 1 << 30);
      }
      notifyListeners();
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }
}
