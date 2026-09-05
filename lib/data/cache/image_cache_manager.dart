import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 图片按访问成本分池，避免几张原图挤掉信息流缩略图。
enum ImageCachePolicy { preview, original, avatar, private, none }

class ForumImageCaches {
  static final preview = CacheManager(
    Config('forum_preview_cache', stalePeriod: const Duration(days: 30), maxNrOfCacheObjects: 800),
  );
  static final original = CacheManager(
    Config('forum_original_cache', stalePeriod: const Duration(days: 7), maxNrOfCacheObjects: 50),
  );
  static final avatar = CacheManager(
    Config('avatar_cache', stalePeriod: const Duration(days: 30), maxNrOfCacheObjects: 1000),
  );
  static final Map<String, CacheManager> _privateByAccount = <String, CacheManager>{};

  static CacheManager privateMedia(String accountScope) {
    final scope = accountScope.trim().isEmpty ? 'anonymous' : accountScope.trim();
    return _privateByAccount.putIfAbsent(
      scope,
      () => CacheManager(Config('private_media_cache_$scope', stalePeriod: const Duration(days: 3), maxNrOfCacheObjects: 128)),
    );
  }

  static CacheManager? forPolicy(ImageCachePolicy policy, {String? accountScope}) => switch (policy) {
    ImageCachePolicy.preview => preview,
    ImageCachePolicy.original => original,
    ImageCachePolicy.avatar => avatar,
    ImageCachePolicy.private => privateMedia(accountScope ?? 'anonymous'),
    ImageCachePolicy.none => null,
  };

  static Future<void> clearPrivate() async {
    for (final manager in _privateByAccount.values) {
      await manager.emptyCache();
    }
  }
}
