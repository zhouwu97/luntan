import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'emoji/sticker_catalog.dart';

/// 评论输入框上方的附件（图片或贴纸）预览区域。
class CommentAttachmentPreview extends StatelessWidget {
  const CommentAttachmentPreview({
    super.key,
    this.localImage,
    this.sticker,
    this.onRemoveImage,
    this.onRemoveSticker,
  });

  final XFile? localImage;
  final AppSticker? sticker;
  final VoidCallback? onRemoveImage;
  final VoidCallback? onRemoveSticker;

  @override
  Widget build(BuildContext context) {
    if (localImage == null && sticker == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

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
            child: localImage != null
                ? (kIsWeb
                    ? Image.network(localImage!.path, fit: BoxFit.cover)
                    : Image.file(File(localImage!.path), fit: BoxFit.cover))
                : (sticker != null
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: Image.asset(
                          sticker!.thumbnailAsset,
                          fit: BoxFit.contain,
                        ),
                      )
                    : const SizedBox.shrink()),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: InkWell(
              onTap: localImage != null ? onRemoveImage : onRemoveSticker,
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
}
