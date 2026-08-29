import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/app_theme.dart';
import '../app_network_image.dart';
import 'search_post_row.dart';

class SearchCommunityRow extends StatelessWidget {
  const SearchCommunityRow({
    super.key,
    required this.name,
    required this.description,
    this.avatar,
    this.isFollowing = false,
    this.query = '',
    this.onToggleFollow,
    required this.onTap,
  });

  factory SearchCommunityRow.fromCommunity({
    required Community community,
    String query = '',
    VoidCallback? onToggleFollow,
    required VoidCallback onTap,
  }) {
    return SearchCommunityRow(
      name: community.name,
      description: community.description,
      avatar: community.avatar,
      isFollowing: community.isFollowing,
      query: query,
      onToggleFollow: onToggleFollow,
      onTap: onTap,
    );
  }

  final String name;
  final String description;
  final String? avatar;
  final bool isFollowing;
  final String query;
  final VoidCallback? onToggleFollow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const nameBase = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: AppTheme.textPrimary,
    );
    const nameHighlight = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: AppTheme.highlight,
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.surfaceBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatar != null
                  ? AppNetworkImage(url: avatar, fit: BoxFit.cover)
                  : Center(
                      child: Text(
                        name.isNotEmpty ? name.characters.first : '板',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: buildHighlightedSpans(
                        source: name,
                        query: query,
                        baseStyle: nameBase,
                        highlightStyle: nameHighlight,
                      ),
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onToggleFollow != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: onToggleFollow,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isFollowing
                        ? const Color(0xFFEEF2F5)
                        : AppTheme.surfaceBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isFollowing ? '已关注' : '关注',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isFollowing
                          ? AppTheme.textSecondary
                          : AppTheme.primary,
                    ),
                  ),
                ),
              ),
            ] else ...[
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textSecondary,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
