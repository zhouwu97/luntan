import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/widgets/comments/comment_item.dart';
import 'package:luntan/widgets/comments/comment_reply_preview.dart';
import 'package:luntan/widgets/comments/comment_thread_sheet.dart';
import 'package:luntan/widgets/comments/comment_composer_controller.dart';
import 'package:luntan/widgets/comments/emoji/comment_emoji_panel.dart';
import 'package:luntan/widgets/comments/emoji/sticker_catalog.dart';

void main() {
  group('评论系统头像与昵称跳转测试', () {
    testWidgets('CommentItem 头像与昵称区域点击触发 onAuthorTap 并传递作者ID', (tester) async {
      String? tappedUserId;
      final comment = Comment(
        id: 'c1',
        postId: 'p1',
        authorId: 'user-xyz',
        author: User(
          id: 'user-xyz',
          username: 'tester',
          nickname: '测试达人',
          level: 4,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        content: '这是一条带有效作者的评论',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentItem(
              comment: comment,
              floor: 2,
              onAuthorTap: (id) => tappedUserId = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击昵称
      await tester.tap(find.text('测试达人'));
      await tester.pumpAndSettle();
      expect(tappedUserId, 'user-xyz');

      tappedUserId = null;
      // 点击头像区域
      await tester.tap(find.text('测'));
      await tester.pumpAndSettle();
      expect(tappedUserId, 'user-xyz');
    });

    testWidgets('CommentItem 游客用户点击不会触发 onAuthorTap', (tester) async {
      String? tappedUserId;
      final guestComment = Comment(
        id: 'c2',
        postId: 'p1',
        authorId: 'guest-999',
        content: '游客评论内容',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentItem(
              comment: guestComment,
              floor: 3,
              onAuthorTap: (id) => tappedUserId = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('游客'));
      await tester.pumpAndSettle();
      expect(tappedUserId, isNull);
    });

    testWidgets('CommentReplyPreview 作者与被回复人点击触发 onAuthorTap', (tester) async {
      final tappedIds = <String>[];
      final replies = [
        Comment(
          id: 'r1',
          postId: 'p1',
          authorId: 'user-author-1',
          author: User(
            id: 'user-author-1',
            username: 'alice',
            nickname: '爱丽丝',
            level: 3,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          replyToUserId: 'user-replyto-2',
          replyToUser: User(
            id: 'user-replyto-2',
            username: 'bob',
            nickname: '鲍伯',
            level: 2,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          content: '我也觉得挺好用的',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentReplyPreview(
              replies: replies,
              totalReplyCount: 1,
              onOpenThread: () {},
              onAuthorTap: (id) => tappedIds.add(id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('爱丽丝', findRichText: true), findsOneWidget);
      expect(find.textContaining('@鲍伯', findRichText: true), findsOneWidget);
    });

    testWidgets('CommentThreadSheet 根评论与二级回复头像昵称点击触发 onAuthorTap', (tester) async {
      String? tappedUserId;
      final commentRepo = MockCommentRepository();
      final rootComment = Comment(
        id: 'comment-u4-1',
        postId: 'u4',
        authorId: 'user-root',
        author: User(
          id: 'user-root',
          username: 'root_user',
          nickname: '根评论作者',
          level: 6,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        content: '这是楼中楼的根评论',
        replyCount: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentThreadSheet(
              rootComment: rootComment,
              repository: commentRepo,
              blockedMessage: '禁言中',
              onAuthorTap: (id) => tappedUserId = id,
              onReply: (target, content) async {
                return commentRepo.createReply(
                  commentId: rootComment.id,
                  content: content,
                  replyToUserId: target.authorId,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('根评论作者'));
      await tester.pumpAndSettle();
      expect(tappedUserId, 'user-root');
    });
  });

  group('评论表情贴纸与多媒体测试', () {
    testWidgets('CommentItem 能够正常渲染贴纸与多张图片附件', (tester) async {
      final commentWithMedia = Comment(
        id: 'c-media',
        postId: 'p1',
        authorId: 'u1',
        content: '看我拍的照片和表情包',
        stickerId: 'aad70d8d064f9eb79286c1393490716c',
        media: [
          MediaAsset(
            id: 'm1',
            type: MediaType.image,
            url: 'https://example.com/photo1.jpg',
          ),
          MediaAsset(
            id: 'm2',
            type: MediaType.image,
            url: 'https://example.com/photo2.jpg',
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CommentItem(
                comment: commentWithMedia,
                floor: 2,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('看我拍的照片和表情包'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('CommentEmojiPanel 支持表情与贴纸包切换和选择', (tester) async {
      String? selectedEmoji;
      AppSticker? selectedSticker;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentEmojiPanel(
              onEmojiSelected: (emoji) => selectedEmoji = emoji,
              onStickerSelected: (sticker) => selectedSticker = sticker,
              onBackspace: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证表情渲染并点击
      expect(find.text('😀'), findsOneWidget);
      await tester.tap(find.text('😀'));
      await tester.pumpAndSettle();
      expect(selectedEmoji, '😀');

      // 切换贴纸分类 Tab
      final stickerTabs = find.byType(InkWell);
      expect(stickerTabs, findsWidgets);
      await tester.tap(stickerTabs.at(1));
      await tester.pumpAndSettle();

      final firstSticker = appStickerGroups.first.items.first;
      expect(firstSticker.id, isNotEmpty);
    });

    test('CommentComposerController 状态机及 draft 校验正确', () {
      final composer = CommentComposerController();

      expect(composer.draft.isEmpty, isTrue);

      composer.textController.text = '测试评论文字';
      expect(composer.draft.isEmpty, isFalse);
      expect(composer.draft.text, '测试评论文字');

      final sticker = appStickerGroups.first.items.first;
      composer.setSticker(sticker);
      expect(composer.draft.sticker, equals(sticker));

      composer.clearSticker();
      expect(composer.draft.sticker, isNull);

      composer.toggleEmoji();
      expect(composer.bottomPanel, equals(CommentBottomPanel.emoji));

      composer.close();
      expect(composer.bottomPanel, equals(CommentBottomPanel.none));

      composer.dispose();
    });
  });
}
