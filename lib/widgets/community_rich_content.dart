import 'bounded_image.dart';
import '../core/theme/anime_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:url_launcher/url_launcher.dart';

import '../core/network/bangumi_endpoints.dart';
import '../core/network/bangumi_smiles.dart';

/// Resolve website-relative links and enforce the same rules for every renderer.
Uri? communityContentUri(String raw, {bool image = false}) {
  final value = raw.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
  final parsed = Uri.tryParse(value);
  if (parsed == null || value.isEmpty) return null;
  final uri = Uri.parse('https://bgm.tv/').resolveUri(parsed);
  if (!['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return image ? Uri.tryParse(BangumiEndpoints.imageUrl(uri.toString())) : uri;
}

/// Render the original BBCode so inline images and spoiler boundaries survive.
class CommunityRichContent extends StatefulWidget {
  const CommunityRichContent(this.source, {super.key, this.onOpenLink})
    : isHtml = false;
  const CommunityRichContent.html(this.source, {super.key, this.onOpenLink})
    : isHtml = true;
  final String source;
  final bool isHtml;
  final ValueChanged<Uri>? onOpenLink;

  @override
  State<CommunityRichContent> createState() => _CommunityRichContentState();
}

class _CommunityRichContentState extends State<CommunityRichContent> {
  final _recognizers = <TapGestureRecognizer>[];
  bool _expanded = false;
  late List<_BbNode> _nodes;

  List<_BbNode> _parseSource() => widget.isHtml
      ? _parseWebsiteHtml(widget.source)
      : _parseBbCode(widget.source);

  @override
  void initState() {
    super.initState();
    _nodes = _parseSource();
  }

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void didUpdateWidget(covariant CommunityRichContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.isHtml != widget.isHtml) {
      _expanded = false;
      _nodes = _parseSource();
    }
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
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

  List<InlineSpan> _plainSpans(String text, TextStyle style, Uri? link) {
    if (link != null) {
      return [
        TextSpan(text: text, style: style, recognizer: _linkRecognizer(link)),
      ];
    }
    final result = <InlineSpan>[];
    var cursor = 0;
    for (final match in RegExp(
      r'''https?://[^\s<>\[\]"'，。！？；]+''',
      caseSensitive: false,
    ).allMatches(text)) {
      if (match.start > cursor) {
        result.add(
          TextSpan(text: text.substring(cursor, match.start), style: style),
        );
      }
      final value = match.group(0)!.replaceFirst(RegExp(r'[.,;!?)]+$'), '');
      final uri = communityContentUri(value);
      result.add(
        TextSpan(
          text: value,
          style: uri == null
              ? style
              : style.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
          recognizer: _linkRecognizer(uri),
        ),
      );
      cursor = match.start + value.length;
    }
    if (cursor < text.length) {
      result.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return result;
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
                  image: boundedImageProvider(
                    CachedNetworkImageProvider(
                      BangumiEndpoints.imageUrl(part.imageUrl!),
                    ),
                    width: 44,
                    height: 22,
                    pixelRatio: MediaQuery.devicePixelRatioOf(context),
                  ),
                  height: 22,
                  errorBuilder: (_, _, _) => Text(part.text),
                ),
              )
            else
              ..._plainSpans(part.text, style, link),
        ],
      );
    }
    if (node.tag == 'img') {
      final smile = node.value == 'smile';
      final uri = communityContentUri(text, image: true);
      return WidgetSpan(
        alignment: smile
            ? PlaceholderAlignment.middle
            : PlaceholderAlignment.bottom,
        child: uri == null
            ? const Text('（无效图片链接）')
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: width,
                  maxHeight: smile ? 22 : 360,
                ),
                child: BoundedNetworkImage(
                  imageUrl: uri.toString(),
                  width: smile ? 44 : null,
                  height: smile ? 22 : null,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) => const Text('（图片加载失败）'),
                ),
              ),
      );
    }
    if (node.tag == 'url') {
      final uri = communityContentUri(node.value.isEmpty ? text : node.value);
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
    if (['align', 'center', 'left', 'right'].contains(node.tag)) {
      final alignment = switch (node.tag == 'align'
          ? node.value.toLowerCase()
          : node.tag) {
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
              children: [for (final node in _nodes) _span(node, style, width)],
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
        icon: AnimeIcon(
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

/// Map website markup into the same inert presentation tree as BBCode. Text
/// nodes stay literal: a quoted "[/mask]" cannot close an HTML spoiler.
List<_BbNode> _parseWebsiteHtml(String source) {
  var offset = 0;
  List<_BbNode> convert(dom.Node node, [int depth = 0]) {
    if (depth >= 32) return [_BbNode(text: '（内容嵌套过深，已省略）')];
    if (node is dom.Text) return [_BbNode(text: node.data)];
    if (node is! dom.Element) return [];
    final tag = node.localName;
    if (const {
      'script',
      'style',
      'iframe',
      'object',
      'input',
      'button',
    }.contains(tag)) {
      return [];
    }
    if (tag == 'br') return [_BbNode(text: '\n')];
    final children = node.nodes
        .expand((child) => convert(child, depth + 1))
        .toList();
    _BbNode wrap(String tag, {String value = '', List<_BbNode>? content}) =>
        _BbNode(tag: tag, value: value, offset: offset++)
          ..children.addAll(content ?? children);
    if (tag == 'img') {
      return [
        wrap(
          'img',
          value: node.classes.contains('smile') ? 'smile' : '',
          content: [_BbNode(text: node.attributes['src'] ?? '')],
        ),
      ];
    }
    if (tag == 'a') return [wrap('url', value: node.attributes['href'] ?? '')];
    if (tag == 'pre' || tag == 'code') {
      return [
        wrap('code', content: [_BbNode(text: node.text)]),
      ];
    }
    if (tag == 'blockquote' || node.classes.contains('quote')) {
      return [wrap('quote')];
    }
    final styles = <String, String>{};
    for (final declaration in (node.attributes['style'] ?? '').split(';')) {
      final colon = declaration.indexOf(':');
      if (colon > 0) {
        styles[declaration.substring(0, colon).trim().toLowerCase()] =
            declaration.substring(colon + 1).trim().toLowerCase();
      }
    }
    var result = children;
    void style(String tag, [String value = '']) {
      result = [wrap(tag, value: value, content: result)];
    }

    if (tag == 'b' ||
        tag == 'strong' ||
        styles['font-weight'] == 'bold' ||
        styles['font-weight'] == '700') {
      style('b');
    }
    if (tag == 'i' || tag == 'em' || styles['font-style'] == 'italic') {
      style('i');
    }
    if (tag == 'u' || styles['text-decoration'] == 'underline') style('u');
    if (tag == 's' ||
        tag == 'del' ||
        styles['text-decoration'] == 'line-through') {
      style('s');
    }
    if (styles['color'] case final String color) style('color', color);
    if (styles['text-align'] case final String align) style('align', align);
    // Bangumi's classic [mask] output uses identical foreground/background
    // colors rather than a named spoiler class.
    final background = styles['background-color'] ?? styles['background'];
    if (node.classes.any(const {'mask', 'spoiler'}.contains) ||
        (background != null && background == styles['color'])) {
      style('mask');
    }
    if (const {'p', 'div', 'li', 'h1', 'h2', 'h3', 'hr'}.contains(tag)) {
      return [_BbNode(text: '\n'), ...result, _BbNode(text: '\n')];
    }
    return result;
  }

  return html
      .parseFragment(source)
      .nodes
      .expand((node) => convert(node))
      .toList();
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
  source = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final root = _BbNode(tag: 'root');
  final stack = [root];
  final pattern = RegExp(
    r'\[(/?)(b|i|u|s|del|quote|code|mask|spoiler|url|img|size|color|align|center|left|right)(?:=([^\]]*))?\]',
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
    final rawTag = match.group(2)!.toLowerCase();
    final tag = rawTag == 'spoiler' ? 'mask' : rawTag;
    if (match.group(1) == '/') {
      final index = stack.lastIndexWhere((node) => node.tag == tag);
      // Crossing a style boundary must never implicitly reveal a spoiler.
      if (index > 0 &&
          !stack.skip(index + 1).any((node) => node.tag == 'mask')) {
        stack.removeRange(index, stack.length);
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
