import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/cache/feed_cache.dart';
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
  FeedController({required FeedRepository repository, String? accountScope})
    : _repository = repository,
      _accountScope = accountScope ?? 'anon';

  final FeedRepository _repository;
  final FeedCacheService _cache = FeedCacheService();
  String _accountScope;
  FeedState _state = const FeedState();
  int _generation = 0;
  int? _loadingMoreGeneration;
  final Set<String> _knownIds = <String>{};
  String? _communityId;
  String _sort = 'recommended';
  LatestOrder _latestOrder = LatestOrder.comment;

  FeedState get state => _state;
  LatestOrder get latestOrder => _latestOrder;
  String get sort => _sort;
  String? get communityId => _communityId;

  /// 账号切换时清理上一个用户的列表和游标，避免把旧会话的阅读态
  /// 短暂展示给新用户。
  void reset() {
    _generation += 1;
    _knownIds.clear();
    _loadingMoreGeneration = null;
    _state = const FeedState();
    notifyListeners();
  }

  Future<void> initialLoad() async {
    if (_state.status != FeedStatus.initial) return;
    final requestGeneration = _generation + 1;
    unawaited(_restoreCache(requestGeneration));
    await _startFirstPage();
  }

  void setAccountScope(String? accountId) {
    final next = accountId?.trim().isNotEmpty == true ? accountId!.trim() : 'anon';
    if (_accountScope == next) return;
    _accountScope = next;
    reset();
  }

  Future<void> refresh() async {
    if (_state.status == FeedStatus.loading) {
      return;
    }
    // 下拉刷新优先级高于正在进行的下一页请求：递增 generation 使旧请求
    // 的结果失效，避免刷新后又把旧游标的数据拼回列表。
    await _startFirstPage();
  }

  Future<void> setQuery({
    String? communityId,
    String sort = 'recommended',
    LatestOrder? latestOrder,
  }) async {
    final nextLatestOrder = latestOrder ?? _latestOrder;
    if (_communityId == communityId &&
        _sort == sort &&
        _latestOrder == nextLatestOrder &&
        _state.status != FeedStatus.initial) {
      return;
    }
    final queryChanged =
        _communityId != communityId ||
        _sort != sort ||
        _latestOrder != nextLatestOrder;
    _communityId = communityId;
    _sort = sort;
    _latestOrder = nextLatestOrder;
    if (queryChanged) {
      // 查询条件变化时清空当前列表，避免短暂展示上一个板块/排序的内容。
      _knownIds.clear();
      _state = const FeedState();
    }
    await _startFirstPage();
  }

  Future<void> setLatestOrder(LatestOrder order) async {
    if (_latestOrder == order && _state.status != FeedStatus.initial) {
      return;
    }
    _latestOrder = order;
    _knownIds.clear();
    _state = const FeedState();
    await _startFirstPage();
  }

  Future<void> loadMore() async {
    final generation = _generation;
    if (_loadingMoreGeneration == generation ||
        !_state.hasMore ||
        _state.nextCursor == null) {
      return;
    }
    final cursor = _state.nextCursor;
    final communityId = _communityId;
    final sort = _sort;
    final latestOrder = _latestOrder;
    _loadingMoreGeneration = generation;
    _state = _state.copyWith(status: FeedStatus.loadingMore, clearError: true);
    notifyListeners();
    try {
      final page = await _fetch(
        cursor: cursor,
        communityId: communityId,
        sort: sort,
        latestOrder: latestOrder,
      );
      if (generation != _generation) return;
      final incoming = page.items
          .where((item) => _knownIds.add(item.id))
          .toList();
      final items = [..._state.items, ...incoming];
      final cursorRepeated =
          page.nextCursor != null && page.nextCursor == cursor;
      _state = FeedState(
        status: items.isEmpty ? FeedStatus.empty : FeedStatus.success,
        items: items,
        nextCursor: cursorRepeated ? null : page.nextCursor,
        hasMore: cursorRepeated ? false : page.hasMore,
      );
      unawaited(_cache.write(accountScope: _accountScope, communityId: communityId, sort: sort, latestOrder: latestOrder, page: FeedPage(items: items, nextCursor: _state.nextCursor, hasMore: _state.hasMore)));
    } catch (error) {
      if (generation != _generation) return;
      _state = _state.copyWith(
        status: _state.items.isEmpty ? FeedStatus.error : FeedStatus.success,
        error: error,
      );
    } finally {
      if (_loadingMoreGeneration == generation) {
        _loadingMoreGeneration = null;
        if (generation == _generation) notifyListeners();
      }
    }
  }

  Future<void> _startFirstPage() {
    final generation = ++_generation;
    _loadingMoreGeneration = null;
    return _loadFirstPage(
      generation,
      communityId: _communityId,
      sort: _sort,
      latestOrder: _latestOrder,
    );
  }

  Future<void> _loadFirstPage(
    int generation, {
    required String? communityId,
    required String sort,
    required LatestOrder latestOrder,
  }) async {
    final previousItems = _state.items;
    _state = FeedState(status: FeedStatus.loading, items: previousItems);
    notifyListeners();
    try {
      final page = await _fetch(
        communityId: communityId,
        sort: sort,
        latestOrder: latestOrder,
      );
      if (generation != _generation) return;
      _knownIds
        ..clear()
        ..addAll(page.items.map((item) => item.id));
      _state = FeedState(
        status: page.items.isEmpty ? FeedStatus.empty : FeedStatus.success,
        items: page.items,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
      unawaited(_cache.write(accountScope: _accountScope, communityId: communityId, sort: sort, latestOrder: latestOrder, page: page));
    } catch (error) {
      if (generation != _generation) return;
      _state = FeedState(
        status: previousItems.isEmpty ? FeedStatus.error : FeedStatus.success,
        items: previousItems,
        error: error,
      );
    }
    if (generation == _generation) notifyListeners();
  }

  Future<void> _restoreCache(int expectedGeneration) async {
    final cached = await _cache.read(
      accountScope: _accountScope,
      communityId: _communityId,
      sort: _sort,
      latestOrder: _latestOrder,
    );
    if (cached == null || expectedGeneration != _generation || _state.items.isNotEmpty) return;
    _knownIds
      ..clear()
      ..addAll(cached.items.map((item) => item.id));
    _state = FeedState(
      status: cached.items.isEmpty ? FeedStatus.empty : FeedStatus.success,
      items: cached.items,
      nextCursor: cached.nextCursor,
      hasMore: cached.hasMore,
    );
    notifyListeners();
  }

  Future<FeedPage> _fetch({
    String? cursor,
    required String? communityId,
    required String sort,
    required LatestOrder latestOrder,
  }) {
    final repository = _repository;
    if (repository is QueryableFeedRepository) {
      final queryable = repository as QueryableFeedRepository;
      return queryable.getFeed(
        cursor: cursor,
        communityId: communityId,
        sort: sort,
        latestOrder: latestOrder,
      );
    }
    return repository.getLatestFeed(cursor: cursor);
  }

  /// 详情页返回后把该帖的互动/计数同步回列表，避免无条件整页刷新。
  /// 结构化变更（编辑标题/正文、删除）由各自回调负责刷新。
  void applyDetailResult(Post detail) {
    final index = _state.items.indexWhere((post) => post.id == detail.id);
    if (index < 0) return;
    final feedPost = _state.items[index];
    var changed = false;
    if (feedPost.isLiked != detail.isLiked) {
      feedPost.isLiked = detail.isLiked;
      changed = true;
    }
    if (feedPost.isBookmarked != detail.isBookmarked) {
      feedPost.isBookmarked = detail.isBookmarked;
      changed = true;
    }
    if (feedPost.likeCount != detail.likeCount) {
      feedPost.likeCount = detail.likeCount;
      changed = true;
    }
    if (feedPost.bookmarkCount != detail.bookmarkCount) {
      feedPost.bookmarkCount = detail.bookmarkCount;
      changed = true;
    }
    if (feedPost.commentCount != detail.commentCount) {
      feedPost.commentCount = detail.commentCount;
      changed = true;
    }
    if (feedPost.title != detail.title) {
      feedPost.title = detail.title;
      changed = true;
    }
    if (feedPost.content != detail.content) {
      feedPost.content = detail.content;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}
