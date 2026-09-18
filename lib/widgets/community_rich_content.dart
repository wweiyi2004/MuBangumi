import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_smiles.dart';

/// Render the original BBCode so inline images and spoiler boundaries survive.
class CommunityRichContent extends StatefulWidget {
  const CommunityRichContent(this.source, {super.key, this.onOpenLink});
  final String source;
  final ValueChanged<Uri>? onOpenLink;

  @override
  State<CommunityRichContent> createState() => _CommunityRichContentState();
}

class _CommunityRichContentState extends State<CommunityRichContent> {
  final _recognizers = <TapGestureRecognizer>[];
  bool _expanded = false;

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void didUpdateWidget(covariant CommunityRichContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _expanded = false;
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  Uri? _safeUri(String raw) {
    final value = raw.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
    final uri = Uri.tryParse(
      value.startsWith('/') ? 'https://bgm.tv$value' : value,
    );
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  Future<void> _open(Uri uri) async {
    if (widget.onOpenLink != null) {
      widget.onOpenLink!(uri);
      return;
    }
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('无法打开链接')));
    }
  }

  TapGestureRecognizer? _linkRecognizer(Uri? uri) {
    if (uri == null) return null;
    final recognizer = TapGestureRecognizer()..onTap = () => _open(uri);
    _recognizers.add(recognizer);
    return recognizer;
  }

  InlineSpan _span(_BbNode node, TextStyle style, double width, {Uri? link}) {
    final text = node.plain;
    if (node.tag.isEmpty) {
      return TextSpan(
        children: [
          for (final part in BangumiSmiles.split(node.text))
            if (part.isImage)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Image(
                  image: CachedNetworkImageProvider(
                    BangumiEndpoints.imageUrl(part.imageUrl!),
                  ),
                  height: 22,
                  errorBuilder: (_, _, _) => Text(part.text),
                ),
              )
            else
              TextSpan(
                text: part.text,
                style: style,
                recognizer: _linkRecognizer(link),
              ),
        ],
      );
    }
    if (node.tag == 'img') {
      final uri = _safeUri(text.startsWith('//') ? 'https:$text' : text);
      return WidgetSpan(
        child: uri == null
            ? const Text('（无效图片链接）')
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width, maxHeight: 360),
                child: CachedNetworkImage(
                  imageUrl: BangumiEndpoints.imageUrl(uri.toString()),
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) => const Text('（图片加载失败）'),
                ),
              ),
      );
    }
    if (node.tag == 'url') {
      final uri = _safeUri(node.value.isEmpty ? text : node.value);
      final linkStyle = uri == null
          ? style
          : style.copyWith(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            );
      // Keep the label's tree: flattening it would expose nested spoilers.
      return TextSpan(
        children: [
          for (final child in node.children)
            _span(child, linkStyle, width, link: uri),
        ],
      );
    }
    if (node.tag == 'code') {
      return WidgetSpan(
        child: Container(
          width: width,
          padding: const EdgeInsets.all(10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SelectableText(
            text,
            scrollPhysics: const NeverScrollableScrollPhysics(),
            style: style.copyWith(fontFamily: 'monospace'),
          ),
        ),
      );
    }
    final childStyle = switch (node.tag) {
      'b' => style.copyWith(fontWeight: FontWeight.bold),
      'i' => style.copyWith(fontStyle: FontStyle.italic),
      'u' => style.copyWith(decoration: TextDecoration.underline),
      's' || 'del' => style.copyWith(decoration: TextDecoration.lineThrough),
      'color' => style.copyWith(color: _bbColor(node.value) ?? style.color),
      'size' => style.copyWith(
        fontSize: (double.tryParse(node.value) ?? style.fontSize ?? 14).clamp(
          10,
          32,
        ),
      ),
      _ => style,
    };
    final innerWidth = node.tag == 'quote'
        ? (width - 24).clamp(0.0, width)
        : width;
    final children = [
      for (final child in node.children)
        _span(child, childStyle, innerWidth, link: link),
    ];
    if (node.tag == 'quote') {
      return WidgetSpan(
        child: Container(
          width: width,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 3,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: SelectableText.rich(
            TextSpan(children: children, style: style),
            scrollPhysics: const NeverScrollableScrollPhysics(),
          ),
        ),
      );
    }
    if (node.tag == 'align') {
      final alignment = switch (node.value.toLowerCase()) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        'justify' => TextAlign.justify,
        _ => TextAlign.left,
      };
      return WidgetSpan(
        child: SizedBox(
          width: width,
          child: SelectableText.rich(
            TextSpan(children: children, style: childStyle),
            textAlign: alignment,
            scrollPhysics: const NeverScrollableScrollPhysics(),
          ),
        ),
      );
    }
    if (node.tag == 'mask') {
      return WidgetSpan(
        child: _Spoiler(
          key: ValueKey('${widget.source.hashCode}:${node.offset}'),
          child: SizedBox(
            width: width,
            child: SelectableText.rich(
              TextSpan(children: children, style: style),
              scrollPhysics: const NeverScrollableScrollPhysics(),
            ),
          ),
        ),
      );
    }
    return TextSpan(children: children, style: childStyle);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _clearRecognizers();
      final style = DefaultTextStyle.of(context).style;
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 300.0;
      final long =
          widget.source.length > 700 ||
          '\n'.allMatches(widget.source).length >= 14;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText.rich(
            TextSpan(
              style: style,
              children: [
                for (final node in _parseBbCode(widget.source))
                  _span(node, style, width),
              ],
            ),
            maxLines: long && !_expanded ? 14 : null,
            scrollPhysics: const NeverScrollableScrollPhysics(),
          ),
          if (long)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '收起长内容' : '展开全文'),
            ),
        ],
      );
    },
  );
}

class _Spoiler extends StatefulWidget {
  const _Spoiler({super.key, required this.child});
  final Widget child;
  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _visible = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton.icon(
        onPressed: () => setState(() => _visible = !_visible),
        icon: Icon(
          _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
        label: Text(_visible ? '隐藏剧透' : '显示剧透'),
      ),
      if (_visible) widget.child,
    ],
  );
}

class _BbNode {
  _BbNode({this.tag = '', this.value = '', this.text = '', this.offset = 0});
  final String tag, value, text;
  final int offset;
  final children = <_BbNode>[];
  String get plain =>
      tag.isEmpty ? text : children.map((child) => child.plain).join();
}

Color? _bbColor(String raw) {
  final value = raw.trim().toLowerCase();
  const names = <String, int>{
    'black': 0x000000,
    'white': 0xffffff,
    'red': 0xff0000,
    'green': 0x008000,
    'blue': 0x0000ff,
    'orange': 0xffa500,
    'yellow': 0xffff00,
    'purple': 0x800080,
    'pink': 0xffc0cb,
    'gray': 0x808080,
    'grey': 0x808080,
    'silver': 0xc0c0c0,
    'navy': 0x000080,
    'teal': 0x008080,
    'aqua': 0x00ffff,
    'lime': 0x00ff00,
    'maroon': 0x800000,
    'olive': 0x808000,
    'fuchsia': 0xff00ff,
  };
  if (names.containsKey(value)) return Color(0xff000000 | names[value]!);
  if (!RegExp(r'^#(?:[0-9a-f]{3}|[0-9a-f]{6})$').hasMatch(value)) return null;
  var hex = value.substring(1);
  if (hex.length == 3) hex = hex.split('').map((char) => '$char$char').join();
  return Color(0xff000000 | int.parse(hex, radix: 16));
}

List<_BbNode> _parseBbCode(String source) {
  final root = _BbNode(tag: 'root');
  final stack = [root];
  final pattern = RegExp(
    r'\[(/?)(b|i|u|s|del|quote|code|mask|url|img|size|color|align)(?:=([^\]]*))?\]',
    caseSensitive: false,
  );
  final lower = source.toLowerCase();
  var cursor = 0;
  for (final match in pattern.allMatches(source)) {
    if (match.start < cursor) continue;
    if (match.start > cursor) {
      stack.last.children.add(
        _BbNode(text: source.substring(cursor, match.start)),
      );
    }
    final tag = match.group(2)!.toLowerCase();
    if (match.group(1) == '/') {
      if (stack.length > 1 && stack.last.tag == tag) {
        stack.removeLast();
      } else {
        stack.last.children.add(_BbNode(text: match.group(0)!));
      }
      cursor = match.end;
      continue;
    }
    if (stack.length >= 32) {
      stack.last.children.add(_BbNode(text: match.group(0)!));
      cursor = match.end;
      continue;
    }
    final node = _BbNode(
      tag: tag,
      value: match.group(3) ?? '',
      offset: match.start,
    );
    stack.last.children.add(node);
    cursor = match.end;
    if (tag == 'code' || tag == 'img') {
      final end = lower.indexOf('[/$tag]', cursor);
      node.children.add(
        _BbNode(text: source.substring(cursor, end < 0 ? source.length : end)),
      );
      cursor = end < 0 ? source.length : end + tag.length + 3;
    } else {
      stack.add(node);
    }
  }
  if (cursor < source.length) {
    stack.last.children.add(_BbNode(text: source.substring(cursor)));
  }
  return root.children;
}
