import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:luntan/data/repositories/mock_repositories.dart';
import 'package:luntan/domain/models.dart';
import 'package:luntan/widgets/comments/comment_item.dart';
import 'package:luntan/widgets/comments/comment_reply_preview.dart';
import 'package:luntan/widgets/comments/comment_thread_sheet.dart';
import 'package:luntan/widgets/comments/comment_composer_controller.dart';
import 'package:luntan/widgets/comments/emoji/comment_emoji_panel.dart';
import 'package:luntan/widgets/comments/emoji/sticker_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      // 点击头像区域（显示首字）
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

    testWidgets('CommentReplyPreview 作者与被回复人点击触发 onAuthorTap 并传递正确ID', (tester) async {
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

      // 真正 tap 作者 '爱丽丝'
      expect(find.text('爱丽丝'), findsOneWidget);
      await tester.tap(find.text('爱丽丝'));
      await tester.pumpAndSettle();
      expect(tappedIds, contains('user-author-1'));

      // 真正 tap 被回复人 '@鲍伯'
      expect(find.text('@鲍伯'), findsOneWidget);
      await tester.tap(find.text('@鲍伯'));
      await tester.pumpAndSettle();
      expect(tappedIds, contains('user-replyto-2'));
      expect(tappedIds.length, 2);
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
    testWidgets('4 套明风贴纸的所有图片 asset 均可在 Bundle 中正常加载', (tester) async {
      expect(appStickerGroups.length, 4);
      var totalCount = 0;
      for (final group in appStickerGroups) {
        expect(group.items.isNotEmpty, isTrue);
        for (final sticker in group.items) {
          totalCount++;
          final bytes = await rootBundle.load(sticker.thumbnailAsset);
          expect(bytes.lengthInBytes, greaterThan(0), reason: '${sticker.thumbnailAsset} 应当存在且不为空');
        }
      }
      expect(totalCount, 64);
    });

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

    testWidgets('CommentEmojiPanel 支持表情与 4 套贴纸包切换且真实触发选中回调', (tester) async {
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

      // 1. 测试 Emoji 点击
      expect(find.text('😀'), findsOneWidget);
      await tester.tap(find.text('😀'));
      await tester.pumpAndSettle();
      expect(selectedEmoji, '😀');

      // 2. 依次测试 4 套贴纸 Tab（第 0 个是 Emoji，第 1-4 是 4 套贴纸）
      for (int i = 0; i < appStickerGroups.length; i++) {
        final expectedGroup = appStickerGroups[i];

        // 点击底部对应的贴纸分类 Tab 切换页面
        final tabFinder = find.byKey(ValueKey('emoji_tab_${i + 1}'));
        expect(tabFinder, findsOneWidget, reason: 'Tab 按钮 ${expectedGroup.name} 应当存在');
        await tester.tap(tabFinder);
        await tester.pumpAndSettle();

        // 查找并点击该组第一个贴纸
        final firstSticker = expectedGroup.items.first;
        final stickerItemFinder = find.byKey(ValueKey('sticker_item_${firstSticker.id}'));
        expect(stickerItemFinder, findsOneWidget, reason: 'Tab ${expectedGroup.name} 中的贴纸项应当渲染');

        await tester.tap(stickerItemFinder);
        await tester.pumpAndSettle();

        expect(selectedSticker?.id, equals(firstSticker.id), reason: '应当正确选中 ${expectedGroup.name} 的首张贴纸');
      }
    });

    test('CommentComposerController 状态机及互斥 draft 校验正确', () {
      final composer = CommentComposerController();

      expect(composer.draft.isEmpty, isTrue);

      // 1. 文字草稿
      composer.textController.text = '测试评论文字';
      expect(composer.draft.isEmpty, isFalse);
      expect(composer.draft.text, '测试评论文字');

      // 2. 设置贴纸附件
      final sticker = appStickerGroups.first.items.first;
      composer.setSticker(sticker);
      expect(composer.draft.sticker, equals(sticker));
      expect(composer.draft.localImage, isNull);

      // 3. 设置图片附件（自动清除贴纸）
      final localImage = XFile('test.jpg');
      composer.setLocalImage(localImage);
      expect(composer.draft.localImage, equals(localImage));
      expect(composer.draft.sticker, isNull);

      // 4. 再次设置贴纸（自动清除图片）
      composer.setSticker(sticker);
      expect(composer.draft.sticker, equals(sticker));
      expect(composer.draft.localImage, isNull);

      // 5. 清除贴纸
      composer.clearSticker();
      expect(composer.draft.sticker, isNull);

      // 6. 面板状态切换
      composer.toggleEmoji();
      expect(composer.bottomPanel, equals(CommentBottomPanel.emoji));

      composer.close();
      expect(composer.bottomPanel, equals(CommentBottomPanel.none));

      composer.dispose();
    });

    test('MockCommentRepository 支持创建带贴纸与图片附件的评论并成功检索', () async {
      final repo = MockCommentRepository();

      // 创建带贴纸的评论
      final stickerComment = await repo.createComment(
        postId: 'u4',
        content: '带贴纸评论',
        stickerId: 'aad70d8d064f9eb79286c1393490716c',
      );
      expect(stickerComment.stickerId, 'aad70d8d064f9eb79286c1393490716c');

      // 创建带图片附件的评论
      final mediaComment = await repo.createComment(
        postId: 'u4',
        content: '带图片评论',
        mediaIds: ['media_mock_1'],
      );
      expect(mediaComment.media.isNotEmpty, isTrue);
      expect(mediaComment.media.first.id, 'media_mock_1');

      // 列表检索
      final page = await repo.listComments(postId: 'u4');
      expect(page.items.any((c) => c.id == stickerComment.id), isTrue);
      expect(page.items.any((c) => c.id == mediaComment.id), isTrue);
    });
  });
}
