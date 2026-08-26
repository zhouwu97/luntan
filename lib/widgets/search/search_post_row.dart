import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/app_theme.dart';

/// 搜索高亮文本构建工具
List<InlineSpan> buildHighlightedSpans({
  required String source,
  required String query,
  required TextStyle baseStyle,
  required TextStyle highlightStyle,
}) {
  if (query.trim().isEmpty || source.isEmpty) {
    return [TextSpan(text: source, style: baseStyle)];
  }

  final lowerSource = source.toLowerCase();
  final lowerQuery = query.trim().toLowerCase();
  final spans = <InlineSpan>[];
  int start = 0;

  while (true) {
    final index = lowerSource.indexOf(lowerQuery, start);
    if (index < 0) {
      if (start < source.length) {
        spans.add(TextSpan(text: source.substring(start), style: baseStyle));
      }
      break;
    }
    if (index > start) {
      spans.add(TextSpan(text: source.substring(start, index), style: baseStyle));
    }
    final matchEnd = index + lowerQuery.length;
    spans.add(
      TextSpan(
        text: source.substring(index, matchEnd),
        style: highlightStyle,
      ),
    );
    start = matchEnd;
  }

  return spans;
}

class SearchPostRow extends StatelessWidget {
  const SearchPostRow({
    super.key,
    required this.title,
    this.snippet = '',
    this.authorName = '',
    this.authorAvatar,
    this.authorLevel = 1,
    this.communityName = '',
    this.timeLabel = '',
    this.commentCount = 0,
    this.likeCount = 0,
    this.viewCount = 0,
    this.query = '',
    required this.onTap,
  });

  factory SearchPostRow.fromPost({
    required Post post,
    String query = '',
    required VoidCallback onTap,
  }) {
    return SearchPostRow(
      title: post.title,
      snippet: post.body.replaceAll('\n', ' '),
      authorName: post.author?.nickname ?? '用户',
      authorAvatar: post.author?.avatar,
      authorLevel: post.author?.level ?? 1,
      communityName: post.community?.name ?? post.tag,
      timeLabel: relativeTimeLabel(post.publishedAt ?? post.createdAt),
      commentCount: post.commentCount,
      likeCount: post.likeCount,
      viewCount: post.viewCount,
      query: query,
      onTap: onTap,
    );
  }

  final String title;
  final String snippet;
  final String authorName;
  final String? authorAvatar;
  final int authorLevel;
  final String communityName;
  final String timeLabel;
  final int commentCount;
  final int likeCount;
  final int viewCount;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const titleBase = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: AppTheme.textPrimary,
      height: 1.35,
    );
    const titleHighlight = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: AppTheme.highlight,
      height: 1.35,
    );

    const snippetBase = TextStyle(
      fontSize: 12.5,
      color: AppTheme.textSecondary,
      height: 1.5,
    );
    const snippetHighlight = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: AppTheme.highlight,
      height: 1.5,
    );

    final subMetaParts = <String>[];
    if (communityName.isNotEmpty) subMetaParts.add(communityName);
    if (timeLabel.isNotEmpty) subMetaParts.add(timeLabel);
    final subMetaText = subMetaParts.join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 作者与板块信息
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppTheme.surfaceBlue,
                  backgroundImage:
                      authorAvatar != null ? NetworkImage(authorAvatar!) : null,
                  child: authorAvatar == null
                      ? Text(
                          authorName.isNotEmpty
                              ? authorName.characters.first
                              : '友',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.levelBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Lv.$authorLevel',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.levelText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (subMetaText.isNotEmpty)
                        Text(
                          subMetaText,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 标题（带高亮）
            RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: buildHighlightedSpans(
                  source: title,
                  query: query,
                  baseStyle: titleBase,
                  highlightStyle: titleHighlight,
                ),
              ),
            ),

            // 摘要（带高亮）
            if (snippet.isNotEmpty) ...[
              const SizedBox(height: 4),
              RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: buildHighlightedSpans(
                    source: snippet,
                    query: query,
                    baseStyle: snippetBase,
                    highlightStyle: snippetHighlight,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),

            // 底部度量指标
            Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 13,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '$commentCount',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 14),
                const Icon(
                  Icons.favorite_border_rounded,
                  size: 13,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '$likeCount',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (viewCount > 0) ...[
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.visibility_outlined,
                    size: 13,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$viewCount',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
