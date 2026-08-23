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
  final Set<String> _knownIds = <String>{};
  String? _communityId;
  String _sort = 'recommended';

  FeedState get state => _state;

  /// 账号切换时清理上一个用户的列表和游标，避免把旧会话的阅读态
  /// 短暂展示给新用户。
  void reset() {
    _knownIds.clear();
    _loadingMore = false;
    _state = const FeedState();
    notifyListeners();
  }

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

  Future<void> setQuery({String? communityId, String sort = 'recommended'}) async {
    if (_communityId == communityId && _sort == sort && _state.status != FeedStatus.initial) return;
    _communityId = communityId;
    _sort = sort;
    await _loadFirstPage();
  }

  Future<void> loadMore() async {
    if (_loadingMore || !_state.hasMore || _state.nextCursor == null) return;
    _loadingMore = true;
    _state = _state.copyWith(status: FeedStatus.loadingMore, clearError: true);
    notifyListeners();
    try {
      final page = await _fetch(cursor: _state.nextCursor);
      final incoming = page.items.where((item) => _knownIds.add(item.id)).toList();
      final items = [..._state.items, ...incoming];
      final cursorRepeated = page.nextCursor != null && page.nextCursor == _state.nextCursor;
      _state = FeedState(
        status: items.isEmpty ? FeedStatus.empty : FeedStatus.success,
        items: items,
        nextCursor: cursorRepeated ? null : page.nextCursor,
        hasMore: cursorRepeated ? false : page.hasMore,
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
    final previousItems = _state.items;
    _state = FeedState(status: FeedStatus.loading, items: previousItems);
    notifyListeners();
    try {
      final page = await _fetch();
      _knownIds
        ..clear()
        ..addAll(page.items.map((item) => item.id));
      _state = FeedState(
        status: page.items.isEmpty ? FeedStatus.empty : FeedStatus.success,
        items: page.items,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
    } catch (error) {
      _state = FeedState(
        status: previousItems.isEmpty ? FeedStatus.error : FeedStatus.success,
        items: previousItems,
        error: error,
      );
    }
    notifyListeners();
  }

  Future<FeedPage> _fetch({String? cursor}) {
    final repository = _repository;
    if (repository is QueryableFeedRepository) {
      final queryable = repository as QueryableFeedRepository;
      return queryable.getFeed(
        cursor: cursor,
        communityId: _communityId,
        sort: _sort,
      );
    }
    return repository.getLatestFeed(cursor: cursor);
  }
}
