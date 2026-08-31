import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// 正文中的 URL 正则：http(s):// 或 www. 开头，遇到空白、中文标点等截断。
final RegExp _postContentUrlPattern = RegExp(
  r'(?:(?:https?://)|(?:www\.))[^\s<>"\u0000-\u001F，。！？；：、（）【】]+',
  caseSensitive: false,
);

const String _urlTrailingPunctuation = '.,!?;:)]}，。！？；：）】、';

/// 正文中的一个网址：位置 + 规范化后的打开地址。
class ContentLink {
  final String text;
  final int start;
  final int end;
  final Uri uri;

  const ContentLink({
    required this.text,
    required this.start,
    required this.end,
    required this.uri,
  });
}

/// 提取正文中的网页链接；`www.` 开头的链接在打开时补充 https 协议。
List<ContentLink> extractContentLinks(String text) {
  final links = <ContentLink>[];
  for (final match in _postContentUrlPattern.allMatches(text)) {
    final raw = match.group(0);
    if (raw == null || raw.isEmpty) continue;

    var linkText = raw;
    while (linkText.isNotEmpty &&
        _urlTrailingPunctuation.contains(linkText[linkText.length - 1])) {
      linkText = linkText.substring(0, linkText.length - 1);
    }
    if (linkText.isEmpty) continue;

    final candidate = linkText.toLowerCase().startsWith('www.')
        ? 'https://$linkText'
        : linkText;
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty) continue;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') continue;

    links.add(
      ContentLink(
        text: linkText,
        start: match.start,
        end: match.start + linkText.length,
        uri: uri,
      ),
    );
  }
  return links;
}

/// 判断一段选中的文本是否就是一个完整的正文 URL。
bool isContentUrl(String value) {
  final trimmed = value.trim();
  final links = extractContentLinks(trimmed);
  return links.length == 1 && links.single.text == trimmed;
}

/// 外部打开网址（带确认弹窗），失败时返回 false。
Future<bool> openExternalLink(BuildContext context, Uri uri) async {
  final shouldOpen = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('打开网页？'),
          content: Text(
            '确定要跳转到以下网址吗？\n${uri.toString()}',
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('打开'),
            ),
          ],
        ),
      ) ??
      false;
  if (!shouldOpen) return true;

  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// 帖子/评论正文文本组件（学习自 xynewui 的 PostContentLinkText）。
///
/// - 正文里的网址自动高亮，点击确认后用系统浏览器打开。
/// - [selectable] 为 true 时支持长按选择复制，并自带「复制/打开链接/全选」菜单。
class LinkText extends StatefulWidget {
  const LinkText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.textAlign,
    this.selectable = false,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;
  final bool selectable;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final _recognizers = <TapGestureRecognizer>[];
  List<TextSpan> _spans = const [];

  @override
  void initState() {
    super.initState();
    _rebuildSpans();
  }

  @override
  void didUpdateWidget(covariant LinkText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _rebuildSpans();
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  void _rebuildSpans() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final links = extractContentLinks(widget.text);
    final spans = <TextSpan>[];
    var cursor = 0;
    final linkStyle = (widget.style ?? const TextStyle()).copyWith(
      color: AppTheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: AppTheme.primary,
    );

    void addPlain(int start, int end) {
      if (start >= end) return;
      spans.add(TextSpan(text: widget.text.substring(start, end)));
    }

    for (final link in links) {
      if (link.start > cursor) addPlain(cursor, link.start);
      final recognizer = TapGestureRecognizer()..onTap = () => _open(link.uri);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: link.text,
          style: linkStyle,
          recognizer: recognizer,
        ),
      );
      cursor = link.end;
    }
    if (cursor < widget.text.length) addPlain(cursor, widget.text.length);
    if (spans.isEmpty) spans.add(TextSpan(text: widget.text));
    _spans = spans;
  }

  Future<void> _open(Uri uri) async {
    final opened = await openExternalLink(context, uri);
    if (!mounted || opened) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('无法打开该网址')),
    );
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final selection = editableTextState.textEditingValue.selection;
    final selected = selection.textInside(
      editableTextState.textEditingValue.text,
    );
    if (selection.isCollapsed || selected.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final items = <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        type: ContextMenuButtonType.copy,
        label: '复制',
        onPressed: () {
          editableTextState.copySelection(SelectionChangedCause.toolbar);
          editableTextState.hideToolbar();
        },
      ),
    ];
    if (isContentUrl(selected)) {
      items.add(
        ContextMenuButtonItem(
          type: ContextMenuButtonType.custom,
          label: '打开链接',
          onPressed: () {
            editableTextState.hideToolbar();
            final links = extractContentLinks(selected.trim());
            if (links.isNotEmpty) _open(links.first.uri);
          },
        ),
      );
    }
    if (selection.start != 0 || selection.end != widget.text.length) {
      items.add(
        ContextMenuButtonItem(
          type: ContextMenuButtonType.selectAll,
          label: '全选',
          onPressed: () {
            editableTextState.selectAll(SelectionChangedCause.toolbar);
          },
        ),
      );
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textSpan = TextSpan(style: widget.style, children: _spans);
    if (widget.selectable) {
      return SelectableText.rich(
        textSpan,
        maxLines: widget.maxLines,
        textAlign: widget.textAlign,
        contextMenuBuilder: _buildContextMenu,
        semanticsLabel: widget.text,
      );
    }
    return Text.rich(
      textSpan,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
    );
  }
}
