/// Official Bangumi `(bgmNN)` smile packs hosted on lain.bgm.tv.
class BangumiSmilePart {
  const BangumiSmilePart._({this.text = '', this.imageUrl});

  final String text;
  final String? imageUrl;

  bool get isImage => imageUrl != null && imageUrl!.isNotEmpty;
}

class BangumiSmiles {
  BangumiSmiles._();

  static final token = RegExp(
    r'\((bgm|musume_|blake_)(\d{1,3})\)',
    caseSensitive: false,
  );

  static String? imageUrl(String raw) {
    final match = token.firstMatch(raw.trim());
    if (match == null || match.start != 0 || match.end != raw.trim().length) {
      return null;
    }
    return urlFor(match.group(1)!, int.parse(match.group(2)!));
  }

  static String? urlFor(String kind, int id) {
    final pack = kind.toLowerCase();
    if (pack == 'musume_') {
      return 'https://lain.bgm.tv/img/smiles/musume/musume_${_pad(id)}.gif';
    }
    if (pack == 'blake_') {
      return 'https://lain.bgm.tv/img/smiles/blake/blake_${_pad(id)}.gif';
    }
    if (id >= 1 && id <= 23) {
      final ext = id == 11 || id == 23 ? 'gif' : 'png';
      return 'https://lain.bgm.tv/img/smiles/bgm/${_pad(id)}.$ext';
    }
    if (id >= 24 && id <= 125) {
      return 'https://lain.bgm.tv/img/smiles/tv/${_pad(id - 23)}.gif';
    }
    if (id >= 200 && id <= 238) {
      return 'https://lain.bgm.tv/img/smiles/tv_vs/bgm_$id.png';
    }
    if (id >= 500 && id <= 529) {
      return 'https://lain.bgm.tv/img/smiles/tv_500/bgm_$id.gif';
    }
    return null;
  }

  static List<BangumiSmilePart> split(String text) {
    if (text.isEmpty) return const [];
    final parts = <BangumiSmilePart>[];
    var cursor = 0;
    for (final match in token.allMatches(text)) {
      if (match.start > cursor) {
        parts.add(
          BangumiSmilePart._(text: text.substring(cursor, match.start)),
        );
      }
      final url = urlFor(match.group(1)!, int.parse(match.group(2)!));
      if (url == null) {
        parts.add(BangumiSmilePart._(text: match.group(0)!));
      } else {
        parts.add(BangumiSmilePart._(text: match.group(0)!, imageUrl: url));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      parts.add(BangumiSmilePart._(text: text.substring(cursor)));
    }
    return parts;
  }

  static String _pad(int id) => id.toString().padLeft(2, '0');
}

class BangumiReactionOption {
  const BangumiReactionOption({required this.value, required this.smileId});

  final int value;
  final int smileId;

  String get token => '(bgm$smileId)';
  String get imageUrl => BangumiSmiles.urlFor('bgm', smileId)!;
}

/// Reaction values accepted by Bangumi's group/subject reply like endpoints.
/// API values are historical database ids rather than the visible bgm smile id.
class BangumiReactions {
  BangumiReactions._();

  static const options = <BangumiReactionOption>[
    BangumiReactionOption(value: 0, smileId: 67),
    BangumiReactionOption(value: 79, smileId: 63),
    BangumiReactionOption(value: 54, smileId: 38),
    BangumiReactionOption(value: 140, smileId: 124),
    BangumiReactionOption(value: 62, smileId: 46),
    BangumiReactionOption(value: 122, smileId: 106),
    BangumiReactionOption(value: 104, smileId: 88),
    BangumiReactionOption(value: 80, smileId: 64),
    BangumiReactionOption(value: 141, smileId: 125),
    BangumiReactionOption(value: 88, smileId: 72),
    BangumiReactionOption(value: 85, smileId: 69),
    BangumiReactionOption(value: 90, smileId: 74),
  ];

  static BangumiReactionOption? optionFor(int value) {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return null;
  }

  static bool accepts(int value) => optionFor(value) != null;
}
