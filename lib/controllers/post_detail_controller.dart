import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

enum PostDetailStatus {
  initial,
  loading,
  success,
  notFound,
  deleted,
  forbidden,
  error,
}

class PostDetailState {
  const PostDetailState({
    this.status = PostDetailStatus.initial,
    this.detail,
    this.error,
  });

  final PostDetailStatus status;
  final PostDetail? detail;
  final Object? error;
}

class PostDetailController extends ChangeNotifier {
  PostDetailController({
    required PostRepository repository,
    required this.postId,
    this.initialPost,
  }) : _repository = repository {
    if (initialPost != null) {
      _state = PostDetailState(
        status: PostDetailStatus.success,
        detail: PostDetail(post: initialPost!),
      );
    }
  }

  final PostRepository _repository;
  final String postId;
  final Post? initialPost;
  PostDetailState _state = const PostDetailState();

  PostDetailState get state => _state;

  Future<void> load() async {
    final snapshot = _state.detail;
    if (snapshot == null) {
      _state = const PostDetailState(status: PostDetailStatus.loading);
      notifyListeners();
    }
    try {
      final detail = await _repository.getPost(postId);
      _state = detail == null
          ? const PostDetailState(status: PostDetailStatus.notFound)
          : PostDetailState(status: PostDetailStatus.success, detail: detail);
    } catch (error) {
      _state = snapshot == null
          ? PostDetailState(status: PostDetailStatus.error, error: error)
          : PostDetailState(
              status: PostDetailStatus.success,
              detail: snapshot,
              error: error,
            );
    }
    notifyListeners();
  }
}
