import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/app_theme.dart';
import 'search_post_row.dart';

class SearchUserRow extends StatelessWidget {
  const SearchUserRow({
    super.key,
    required this.nickname,
    required this.username,
    this.avatar,
    this.level = 1,
    this.signature,
    this.query = '',
    required this.onTap,
  });

  factory SearchUserRow.fromUser({
    required User user,
    String query = '',
    required VoidCallback onTap,
  }) {
    return SearchUserRow(
      nickname: user.nickname,
      username: user.username,
      avatar: user.avatar,
      level: user.level,
      signature: user.signature,
      query: query,
      onTap: onTap,
    );
  }

  final String nickname;
  final String username;
  final String? avatar;
  final int level;
  final String? signature;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const nameBase = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
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
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.surfaceBlue,
              backgroundImage: avatar != null ? NetworkImage(avatar!) : null,
              child: avatar == null
                  ? Text(
                      nickname.isNotEmpty ? nickname.characters.first : '友',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            children: buildHighlightedSpans(
                              source: nickname,
                              query: query,
                              baseStyle: nameBase,
                              highlightStyle: nameHighlight,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
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
                          'Lv.$level',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.levelText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '@$username${signature != null && signature!.isNotEmpty ? " · $signature" : ""}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
