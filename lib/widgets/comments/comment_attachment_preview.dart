import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'emoji/sticker_catalog.dart';

/// 评论输入框上方的附件（多张图片或单张贴纸）预览区域。
class CommentAttachmentPreview extends StatelessWidget {
  const CommentAttachmentPreview({
    super.key,
    this.localImages = const [],
    this.sticker,
    this.onRemoveImageAt,
    this.onAddMoreImages,
    this.onRemoveSticker,
    this.localImage,
    this.onRemoveImage,
  });

  final List<XFile> localImages;
  final AppSticker? sticker;
  final void Function(int index)? onRemoveImageAt;
  final VoidCallback? onAddMoreImages;
  final VoidCallback? onRemoveSticker;
  final XFile? localImage;
  final VoidCallback? onRemoveImage;

  @override
  Widget build(BuildContext context) {
    final effectiveImages = localImages.isNotEmpty
        ? localImages
        : (localImage != null ? [localImage!] : const <XFile>[]);

    if (effectiveImages.isEmpty && sticker == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    // 贴纸单选展示
    if (sticker != null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        alignment: Alignment.centerLeft,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Image.asset(
                  sticker!.thumbnailAsset,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: InkWell(
                onTap: onRemoveSticker,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.cancel,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 多图横向缩略图展示
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 6, bottom: 2),
          child: Row(
            children: [
              Text(
                '已添加图片',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${effectiveImages.length}/9)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 84,
          child: ListView.separated(
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            scrollDirection: Axis.horizontal,
            itemCount: effectiveImages.length +
                (effectiveImages.length < 9 && onAddMoreImages != null ? 1 : 0),
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index < effectiveImages.length) {
                final img = effectiveImages[index];
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        color: theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.3,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: kIsWeb
                          ? Image.network(img.path, fit: BoxFit.cover)
                          : Image.file(File(img.path), fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: InkWell(
                        onTap: () {
                          if (onRemoveImageAt != null) {
                            onRemoveImageAt!(index);
                          } else {
                            onRemoveImage?.call();
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.cancel,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // "+" 添加图片按钮
              return InkWell(
                onTap: onAddMoreImages,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 24,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '添加',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
