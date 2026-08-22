// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';

import '../controllers/post_detail_controller.dart';
import '../data/mock_forum_data.dart';
import '../theme/app_theme.dart';
import '../widgets/forum_author_row.dart';
import '../widgets/post_media_preview.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.store, required this.controller, this.focusComments = false});

  final ForumStore store;
  final PostDetailController controller;
  final bool focusComments;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final replyController = TextEditingController();
  final commentsKey = GlobalKey();
  bool isSending = false;
  bool hasFocusedComments = false;
  Comment? replyTarget;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.load();
    });
  }

  @override
  void dispose() {
    replyController.dispose();
    super.dispose();
  }

  void submitReply(Post post) {
    if (isSending) return;
    final content = replyController.text.trim();
    if (content.isEmpty) return;
    setState(() => isSending = true);
    final target = replyTarget;
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      widget.store.addComment(post, content, parentId: target?.id, replyToUserId: target?.authorId);
      setState(() {
        replyController.clear();
        replyTarget = null;
        isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('回复已发布，评论数 +1')));
    });
  }

  void focusCommentsIfNeeded() {
    if (!widget.focusComments || hasFocusedComments) return;
    hasFocusedComments = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && commentsKey.currentContext != null) Scrollable.ensureVisible(commentsKey.currentContext!, duration: const Duration(milliseconds: 260), alignment: .08);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.store, widget.controller]),
      builder: (context, _) {
        final state = widget.controller.state;
        if (state.status == PostDetailStatus.loading || state.status == PostDetailStatus.initial) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (state.status != PostDetailStatus.success || state.detail == null) {
          final message = state.status == PostDetailStatus.notFound ? '帖子不存在或已被删除' : '帖子加载失败，请稍后重试';
          return Scaffold(appBar: AppBar(), body: _StateMessage(message: message, onRetry: widget.controller.load));
        }
        final post = state.detail!.post;
        focusCommentsIfNeeded();
        final allComments = widget.store.commentsFor(post);
        final roots = allComments.where((comment) => comment.parentId == null).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(post.community?.name ?? post.section.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            actions: [
              IconButton(onPressed: () => widget.store.toggleBookmark(post), tooltip: '收藏帖子', icon: Icon(post.isBookmarked ? Icons.star_rounded : Icons.star_border_rounded, color: post.isBookmarked ? AppTheme.orange : AppTheme.textSecondary)),
              IconButton(onPressed: () => widget.store.toggleLike(post), icon: Icon(post.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: post.isLiked ? AppTheme.pink : AppTheme.textSecondary)),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(15, 8, 15, 22),
                  children: [
                    ForumAuthorRow(post: post, onMenu: () => _showPostMenu(post)),
                    const SizedBox(height: 15),
                    if (post.isPinned || post.isFeatured || post.extraTag == '精华') _Tag(text: post.isPinned ? '置顶' : '精华', color: post.isPinned ? AppTheme.pink : AppTheme.orange),
                    if (post.isPinned || post.isFeatured || post.extraTag == '精华') const SizedBox(height: 8),
                    Text(post.title, style: const TextStyle(fontSize: 22, height: 1.35, color: AppTheme.textPrimary, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 11),
                    Text(post.body, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, height: 1.75)),
                    if (post.images.isNotEmpty) PostMediaPreview(images: post.images, onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MediaGalleryScreen(images: post.images)))),
                    const SizedBox(height: 15),
                    Row(children: [const Icon(Icons.visibility_outlined, color: AppTheme.textSecondary, size: 17), const SizedBox(width: 5), Text(post.views + ' 浏览', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)), const SizedBox(width: 16), const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.textSecondary, size: 17), const SizedBox(width: 5), Text(post.comments.toString() + ' 回复', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)), const SizedBox(width: 16), Icon(post.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: post.isLiked ? AppTheme.pink : AppTheme.textSecondary, size: 17), const SizedBox(width: 5), Text(post.likeCount.toString() + ' 赞', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))]),
                    const Divider(height: 35, color: AppTheme.border),
                    Container(key: commentsKey, child: Row(children: [Expanded(child: Text('全部回复 ' + post.comments.toString(), style: const TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w800))), Text(roots.length.toString() + ' 条可见', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11))])),
                    const SizedBox(height: 13),
                    if (roots.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 45), child: Center(child: Text('还没有回复，来抢沙发吧', style: TextStyle(color: AppTheme.textSecondary)))),
                    ...roots.asMap().entries.map((entry) {
                      final comment = entry.value;
                      final children = allComments.where((item) => item.parentId == comment.id).toList();
                      return _CommentTile(post: post, comment: comment, floor: entry.key + 2, children: children, store: widget.store, onReply: () => setState(() => replyTarget = comment), onLike: () => widget.store.toggleCommentLike(comment), onMore: () => _showCommentMenu(post, comment));
                    }),
                  ],
                ),
              ),
              _ReplyBar(controller: replyController, target: replyTarget, sending: isSending, onSubmit: () => submitReply(post)),
            ],
          ),
        );
      },
    );
  }

  void _showPostMenu(Post post) {
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (sheetContext) => SafeArea(child: Wrap(children: [
      ListTile(leading: Icon(post.isBookmarked ? Icons.star_rounded : Icons.star_border_rounded, color: post.isBookmarked ? AppTheme.orange : AppTheme.textSecondary), title: Text(post.isBookmarked ? '取消收藏' : '收藏帖子'), onTap: () { widget.store.toggleBookmark(post); Navigator.pop(sheetContext); }),
      const ListTile(leading: Icon(Icons.flag_outlined, color: AppTheme.orange), title: Text('举报或屏蔽')),
    ])));
  }

  void _showCommentMenu(Post post, Comment comment) {
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (sheetContext) => SafeArea(child: Wrap(children: [
      const ListTile(leading: Icon(Icons.flag_outlined, color: AppTheme.orange), title: Text('举报评论')),
      if (comment.authorId == 'user-1') ListTile(leading: const Icon(Icons.delete_outline), title: const Text('删除评论'), onTap: () { widget.store.deleteComment(post, comment); Navigator.pop(sheetContext); }),
    ])));
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, style: const TextStyle(color: AppTheme.textSecondary)), const SizedBox(height: 12), OutlinedButton(onPressed: onRetry, child: const Text('重试'))]));
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.controller, required this.target, required this.sending, required this.onSubmit});

  final TextEditingController controller;
  final Comment? target;
  final bool sending;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final hint = target == null ? '友善地回复一句…' : '回复 ' + (target!.authorId == 'user-1' ? '楼主' : '这位同学') + '…';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppTheme.border))),
        child: Row(children: [
          Expanded(child: TextField(controller: controller, textInputAction: TextInputAction.send, onSubmitted: (_) => onSubmit(), decoration: InputDecoration(hintText: hint, isDense: true))),
          const SizedBox(width: 7),
          FilledButton(onPressed: sending ? null : onSubmit, style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)), child: Text(sending ? '…' : '发送')),
        ]),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.post, required this.comment, required this.floor, required this.children, required this.store, required this.onReply, required this.onLike, required this.onMore});

  final Post post;
  final Comment comment;
  final int floor;
  final List<Comment> children;
  final ForumStore store;
  final VoidCallback onReply;
  final VoidCallback onLike;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final author = store.userById(comment.authorId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 17, backgroundColor: AppTheme.surfaceBlue, child: Text((author?.nickname ?? '匿').characters.first, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800))),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Flexible(child: Text(author?.nickname ?? '匿名用户', overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700))), const SizedBox(width: 6), Text('Lv.' + (author?.level ?? 1).toString(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)), const Spacer(), Text(floor.toString() + '楼', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10))]),
            const SizedBox(height: 3),
            Text(relativeTimeLabel(comment.createdAt), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
            const SizedBox(height: 6),
            Text(comment.content, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.55)),
            const SizedBox(height: 6),
            Row(children: [TextButton(onPressed: onReply, style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(38, 28)), child: const Text('回复')), TextButton(onPressed: onLike, style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 28)), child: Text((store.isCommentLiked(comment) ? '♥ ' : '♡ ') + (comment.likeCount + (store.isCommentLiked(comment) ? 1 : 0)).toString())), IconButton(onPressed: onMore, visualDensity: VisualDensity.compact, icon: const Icon(Icons.more_horiz_rounded, size: 17, color: AppTheme.textSecondary))]),
          ])),
        ]),
        if (children.isNotEmpty) Container(margin: const EdgeInsets.only(left: 43, top: 2), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children.take(3).map((child) { final childAuthor = store.userById(child.authorId); return Padding(padding: const EdgeInsets.only(bottom: 4), child: Text((childAuthor?.nickname ?? '匿名用户') + '：' + child.content, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.5))); }).toList())),
        if (children.length > 3) Padding(padding: const EdgeInsets.only(left: 43, top: 5), child: Text('查看全部 ' + children.length.toString() + ' 条回复', style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(7)), child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)));
}
