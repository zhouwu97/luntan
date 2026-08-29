import 'package:flutter/material.dart';

import 'emoji_catalog.dart';
import 'sticker_catalog.dart';

/// 评论专用的表情/贴纸面板。
/// 支持 Emoji 输入与贴纸一键选中。
class CommentEmojiPanel extends StatefulWidget {
  const CommentEmojiPanel({
    super.key,
    required this.onEmojiSelected,
    required this.onBackspace,
    this.onStickerSelected,
    this.enabled = true,
  });

  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onBackspace;
  final ValueChanged<AppSticker>? onStickerSelected;
  final bool enabled;

  @override
  State<CommentEmojiPanel> createState() => _CommentEmojiPanelState();
}

class _CommentEmojiPanelState extends State<CommentEmojiPanel> {
  late final PageController _pageController;
  int _tabIndex = 0;

  List<String> get _emojis => appEmojiCatalog['表情'] ?? const [];

  int get _pageCount =>
      1 + (widget.onStickerSelected == null ? 0 : appStickerGroups.length);

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _pageCount) return;
    _pageController.jumpToPage(index);
    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _tabIndex = index),
              itemCount: _pageCount,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildEmojiGrid(context);
                }
                final groupIndex = index - 1;
                final group = appStickerGroups[groupIndex];
                return _buildStickerGrid(context, group);
              },
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          _buildBottomTabBar(context),
        ],
      ),
    );
  }

  Widget _buildEmojiGrid(BuildContext context) {
    final theme = Theme.of(context);
    final emojis = _emojis;

    return Stack(
      children: [
        GridView.builder(
          key: const Key('emoji_grid_view'),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 56),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: emojis.length,
          itemBuilder: (context, index) {
            final emoji = emojis[index];
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.enabled ? () => widget.onEmojiSelected(emoji) : null,
              child: Center(
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 26),
                ),
              ),
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 8,
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(20),
            color: theme.colorScheme.surface,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.enabled ? widget.onBackspace : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.backspace_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStickerGrid(BuildContext context, AppStickerGroup group) {
    return GridView.builder(
      key: Key('sticker_grid_${group.id}'),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: group.items.length,
      itemBuilder: (context, index) {
        final sticker = group.items[index];
        return InkWell(
          key: ValueKey('sticker_item_${sticker.id}'),
          borderRadius: BorderRadius.circular(10),
          onTap: widget.enabled && widget.onStickerSelected != null
              ? () => widget.onStickerSelected!(sticker)
              : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
            ),
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Image.asset(
                    sticker.thumbnailAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.broken_image_outlined,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sticker.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomTabBar(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: theme.colorScheme.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _pageCount,
        itemBuilder: (context, index) {
          final isSelected = _tabIndex == index;
          Widget iconWidget;
          if (index == 0) {
            iconWidget = Icon(
              Icons.sentiment_satisfied_alt_rounded,
              color: isSelected ? activeColor : theme.colorScheme.onSurfaceVariant,
              size: 22,
            );
          } else {
            final group = appStickerGroups[index - 1];
            final previewAsset = group.items.isNotEmpty ? group.items.first.thumbnailAsset : '';
            iconWidget = previewAsset.isNotEmpty
                ? Image.asset(
                    previewAsset,
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                  )
                : Icon(
                    Icons.sticky_note_2_outlined,
                    color: isSelected ? activeColor : theme.colorScheme.onSurfaceVariant,
                    size: 22,
                  );
          }

          return InkWell(
            key: ValueKey('emoji_tab_$index'),
            onTap: () => _selectTab(index),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(child: iconWidget),
            ),
          );
        },
      ),
    );
  }
}
