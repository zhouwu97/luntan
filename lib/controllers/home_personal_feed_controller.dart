import 'package:flutter/foundation.dart';

import '../data/api/profile_repository.dart';
import '../data/mock_forum_data.dart';
import '../domain/models.dart';
import 'feed_controller.dart';

/// 首页右侧胶囊的三种互斥状态。
///
/// [receivedComments] 和 [myPosts] 都仍然渲染普通帖子卡片，只改变数据源和
/// 排序语义；它们不是评论页或个人中心页的导航状态。
enum HomeFeedMode { public, receivedComments, myPosts }

class HomePersonalFeedState {
  const HomePersonalFeedState({
    this.mode = HomeFeedMode.public,
    this.status = FeedStatus.initial,
    this.items = const [],
    this.nextCursor,
    this.hasMore = false,
    this.activityAtByPostId = const {},
    this.error,
  });

  final HomeFeedMode mode;
  final FeedStatus status;
  final List<Post> items;
  final String? nextCursor;
  final bool hasMore;
  final Map<String, DateTime> activityAtByPostId;
  final Object? error;

  bool get isBusy =>
      status == FeedStatus.loading || status == FeedStatus.loadingMore;

  HomePersonalFeedState copyWith({
    HomeFeedMode? mode,
    FeedStatus? status,
    List<Post>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? hasMore,
    Map<String, DateTime>? activityAtByPostId,
    Object? error,
    bool clearError = false,
  }) {
    return HomePersonalFeedState(
      mode: mode ?? this.mode,
      status: status ?? this.status,
      items: items ?? this.items,
      nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      activityAtByPostId: activityAtByPostId ?? this.activityAtByPostId,
      error: clearError ? null : error ?? this.error,
    );
  }
}

/// 评论/帖子个人 Feed 的分页状态机。
///
/// API 模式使用 `/api/v1/me/comments` 和 `/api/v1/me/posts`，并要求服务端
/// 返回可直接构造 [Post] 的摘要；Mock 模式沿用 ForumStore，保证首页离线预览
/// 也能验证两种模式的排序和卡片复用。
class HomePersonalFeedController extends ChangeNotifier {
  HomePersonalFeedController({
    this.repository,
    this.mockStore,
    this.mockUserId = 'user-1',
  });

  final ProfileRepository? repository;
  final ForumStore? mockStore;
  final String mockUserId;

  HomePersonalFeedState _state = const HomePersonalFeedState();
  int _generation = 0;
  int? _loadingMoreGeneration;
  final Set<String> _knownIds = <String>{};

  HomePersonalFeedState get state => _state;

  DateTime? activityAtFor(String postId) => _state.activityAtByPostId[postId];

  Future<void> selectMode(HomeFeedMode mode) async {
    if (mode == HomeFeedMode.public) {
      reset();
      return;
    }
    if (_state.mode == mode && _state.status != FeedStatus.initial) {
      return;
    }
    _knownIds.clear();
    _loadingMoreGeneration = null;
    _state = HomePersonalFeedState(mode: mode);
    notifyListeners();
    await _startFirstPage(mode);
  }

  Future<void> refresh({HomeFeedMode? mode}) async {
    final nextMode = mode ?? _state.mode;
    if (nextMode == HomeFeedMode.public) return;
    if (_state.mode != nextMode) {
      _knownIds.clear();
      _state = HomePersonalFeedState(mode: nextMode);
      notifyListeners();
    }
    await _startFirstPage(nextMode);
  }

  Future<void> loadMore() async {
    final mode = _state.mode;
    if (mode == HomeFeedMode.public ||
        _loadingMoreGeneration == _generation ||
        !_state.hasMore ||
        _state.nextCursor == null) {
      return;
    }
    final generation = _generation;
    final cursor = _state.nextCursor;
    _loadingMoreGeneration = generation;
    _state = _state.copyWith(status: FeedStatus.loadingMore, clearError: true);
    notifyListeners();
    try {
      final page = await _fetch(mode, cursor: cursor);
      if (generation != _generation) return;
      final incoming = <Post>[];
      final activity = <String, DateTime>{..._state.activityAtByPostId};
      for (final item in page.items) {
        if (_knownIds.add(item.id)) {
          incoming.add(_toPost(item));
          final activityAt = item.activityAt;
          if (activityAt != null) activity[item.id] = activityAt;
        }
      }
      final repeatedCursor =
          page.nextCursor != null && page.nextCursor == cursor;
      final items = [..._state.items, ...incoming];
      _state = HomePersonalFeedState(
        mode: mode,
        status: items.isEmpty ? FeedStatus.empty : FeedStatus.success,
        items: items,
        nextCursor: repeatedCursor ? null : page.nextCursor,
        hasMore: repeatedCursor ? false : page.hasMore,
        activityAtByPostId: activity,
      );
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

  Future<void> _startFirstPage(HomeFeedMode mode) async {
    final generation = ++_generation;
    _loadingMoreGeneration = null;
    final previousItems = _state.mode == mode ? _state.items : const <Post>[];
    _state = HomePersonalFeedState(
      mode: mode,
      status: FeedStatus.loading,
      items: previousItems,
    );
    notifyListeners();
    try {
      final page = await _fetch(mode);
      if (generation != _generation) return;
      final items = <Post>[];
      final activity = <String, DateTime>{};
      _knownIds.clear();
      for (final item in page.items) {
        if (!_knownIds.add(item.id)) continue;
        items.add(_toPost(item));
        final activityAt = item.activityAt;
        if (activityAt != null) activity[item.id] = activityAt;
      }
      _state = HomePersonalFeedState(
        mode: mode,
        status: items.isEmpty ? FeedStatus.empty : FeedStatus.success,
        items: items,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        activityAtByPostId: activity,
      );
    } catch (error) {
      if (generation != _generation) return;
      _state = HomePersonalFeedState(
        mode: mode,
        status: previousItems.isEmpty ? FeedStatus.error : FeedStatus.success,
        items: previousItems,
        error: error,
      );
    }
    if (generation == _generation) notifyListeners();
  }

  Future<ProfileListPage> _fetch(HomeFeedMode mode, {String? cursor}) async {
    final profileRepository = repository;
    if (profileRepository != null) {
      return profileRepository.list(
        mode == HomeFeedMode.receivedComments ? 'comments' : 'posts',
        cursor: cursor,
        includeDetails: true,
      );
    }
    return _mockPage(mode);
  }

  Future<ProfileListPage> _mockPage(HomeFeedMode mode) async {
    final store = mockStore;
    if (store == null) {
      return const ProfileListPage(items: []);
    }
    final mine = store.posts
        .where((post) => post.authorId == mockUserId)
        .where(
          (post) =>
              post.publicationStatus == PublicationStatus.published &&
              post.moderationStatus == ModerationStatus.normal,
        )
        .toList();
    final activity = <String, DateTime>{};
    if (mode == HomeFeedMode.receivedComments) {
      mine.removeWhere((post) {
        final received = (store.commentsByPost[post.id] ?? const <Comment>[])
            .where(
              (comment) =>
                  comment.authorId != mockUserId &&
                  comment.publicationStatus ==
                      CommentPublicationStatus.published &&
                  comment.moderationStatus == ModerationStatus.normal,
            )
            .toList();
        if (received.isEmpty) return true;
        activity[post.id] = received
            .map((comment) => comment.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return false;
      });
      mine.sort((a, b) {
        final byActivity = activity[b.id]!.compareTo(activity[a.id]!);
        return byActivity == 0 ? b.id.compareTo(a.id) : byActivity;
      });
    } else {
      mine.sort(_comparePublished);
    }
    return ProfileListPage(
      items: mine
          .map(
            (post) => ProfilePostItem(
              id: post.id,
              communityName: post.community?.name ?? post.tag,
              title: post.title,
              contentPreview: post.content,
              communityId: post.communityId,
              commentCount: post.commentCount,
              likeCount: post.likeCount,
              bookmarkCount: post.bookmarkCount,
              publishedAt: post.publishedAt ?? post.createdAt,
              activityAt: activity[post.id],
              authorId: post.authorId,
              authorUsername: post.author?.username ?? '',
              authorNickname: post.author?.nickname ?? '',
              authorLevel: post.author?.level ?? 1,
              communitySlug: post.community?.slug ?? '',
              postType: _wireType(post.type),
              viewCount: post.viewCount,
              shareCount: post.shareCount,
              createdAt: post.createdAt,
              updatedAt: post.updatedAt,
              publicationStatus: post.publicationStatus,
              moderationStatus: post.moderationStatus,
              viewerState: post.viewerState,
              media: post.media,
              isFeatured: post.isFeatured,
              isPinned: post.isPinned,
            ),
          )
          .toList(),
    );
  }

  Post _toPost(ProfilePostItem item) {
    final now = DateTime.now().toUtc();
    final authorId = item.authorId.isEmpty ? 'unknown' : item.authorId;
    final communityId = item.communityId;
    final communityName = item.communityName.isEmpty
        ? '社区'
        : item.communityName;
    return Post(
      id: item.id,
      authorId: authorId,
      author: User(
        id: authorId,
        username: item.authorUsername,
        nickname: item.authorNickname.isEmpty ? '匿名用户' : item.authorNickname,
        level: item.authorLevel,
        createdAt: now,
        updatedAt: now,
      ),
      communityId: communityId,
      community: Community(
        id: communityId,
        slug: item.communitySlug,
        name: communityName,
        description: '',
        categoryId: '',
      ),
      type: _postType(item.postType),
      publicationStatus: item.publicationStatus,
      moderationStatus: item.moderationStatus,
      title: item.title,
      content: item.contentPreview,
      commentCount: item.commentCount,
      likeCount: item.likeCount,
      bookmarkCount: item.bookmarkCount,
      shareCount: item.shareCount,
      viewCount: item.viewCount,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      publishedAt: item.publishedAt,
      viewerState: item.viewerState,
      isFeatured: item.isFeatured,
      isPinned: item.isPinned,
      media: item.media,
    );
  }

  void applyDetailResult(Post detail) {
    final index = _state.items.indexWhere((item) => item.id == detail.id);
    if (index < 0) return;
    final current = _state.items[index];
    current
      ..title = detail.title
      ..content = detail.content
      ..commentCount = detail.commentCount
      ..likeCount = detail.likeCount
      ..bookmarkCount = detail.bookmarkCount
      ..isLiked = detail.isLiked
      ..isBookmarked = detail.isBookmarked;
    notifyListeners();
  }

  void removePost(String postId) {
    final next = _state.items.where((post) => post.id != postId).toList();
    if (next.length == _state.items.length) return;
    _state = _state.copyWith(
      items: next,
      status: next.isEmpty ? FeedStatus.empty : FeedStatus.success,
    );
    notifyListeners();
  }

  void reset() {
    _generation++;
    _loadingMoreGeneration = null;
    _knownIds.clear();
    _state = const HomePersonalFeedState();
    notifyListeners();
  }
}

int _comparePublished(Post a, Post b) {
  final byTime = (b.publishedAt ?? b.createdAt).compareTo(
    a.publishedAt ?? a.createdAt,
  );
  return byTime == 0 ? b.id.compareTo(a.id) : byTime;
}

PostType _postType(String value) => switch (value) {
  'game_share' => PostType.gameShare,
  'image' => PostType.image,
  'poll' => PostType.poll,
  'question' => PostType.question,
  'article' => PostType.article,
  'video' => PostType.video,
  'activity' => PostType.activity,
  _ => PostType.normal,
};

String _wireType(PostType type) => switch (type) {
  PostType.gameShare => 'game_share',
  PostType.poll => 'poll',
  PostType.image => 'image',
  PostType.question => 'question',
  PostType.article => 'article',
  PostType.video => 'video',
  PostType.activity => 'activity',
  PostType.normal => 'normal',
};
