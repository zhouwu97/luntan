import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

enum FeedStatus { initial, loading, success, empty, error, loadingMore }

class FeedState {
  const FeedState({
    this.status = FeedStatus.initial,
    this.items = const [],
    this.nextCursor,
    this.hasMore = false,
    this.error,
  });

  final FeedStatus status;
  final List<Post> items;
  final String? nextCursor;
  final bool hasMore;
  final Object? error;

  bool get isBusy =>
      status == FeedStatus.loading || status == FeedStatus.loadingMore;

  FeedState copyWith({
    FeedStatus? status,
    List<Post>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) {
    return FeedState(
      status: status ?? this.status,
      items: items ?? this.items,
      nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class FeedController extends ChangeNotifier {
  FeedController({required FeedRepository repository})
    : _repository = repository;

  final FeedRepository _repository;
  FeedState _state = const FeedState();
  bool _loadingMore = false;

  FeedState get state => _state;

  Future<void> initialLoad() async {
    if (_state.status != FeedStatus.initial) return;
    await _loadFirstPage();
  }

  Future<void> refresh() async {
    if (_state.status == FeedStatus.loading ||
        _state.status == FeedStatus.loadingMore) {
      return;
    }
    await _loadFirstPage();
  }

  Future<void> loadMore() async {
    if (_loadingMore || !_state.hasMore || _state.nextCursor == null) return;
    _loadingMore = true;
    _state = _state.copyWith(status: FeedStatus.loadingMore, clearError: true);
    notifyListeners();
    try {
      final page = await _repository.getLatestFeed(cursor: _state.nextCursor);
      final items = [..._state.items, ...page.items];
      _state = FeedState(
        status: items.isEmpty ? FeedStatus.empty : FeedStatus.success,
        items: items,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
    } catch (error) {
      _state = _state.copyWith(
        status: _state.items.isEmpty ? FeedStatus.error : FeedStatus.success,
        error: error,
      );
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> _loadFirstPage() async {
    _state = FeedState(status: FeedStatus.loading, items: _state.items);
    notifyListeners();
    try {
      final page = await _repository.getLatestFeed();
      _state = FeedState(
        status: page.items.isEmpty ? FeedStatus.empty : FeedStatus.success,
        items: page.items,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
    } catch (error) {
      _state = FeedState(
        status: FeedStatus.error,
        items: const [],
        error: error,
      );
    }
    notifyListeners();
  }
}
