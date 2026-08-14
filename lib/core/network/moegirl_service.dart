import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../models/bangumi_models.dart';
import '../storage/community_cache.dart';
import 'bangumi_user_agent.dart';

class MoegirlEntry {
  const MoegirlEntry({
    required this.pageId,
    required this.title,
    required this.extract,
    required this.url,
    this.revisionId = 0,
    this.sections = const [],
  });

  final int pageId;
  final String title;
  final String extract;
  final String url;
  final int revisionId;
  final List<MoegirlSection> sections;

  factory MoegirlEntry.fromJson(Map<String, dynamic> json) => MoegirlEntry(
    pageId: _asInt(json['page_id']),
    title: json['title']?.toString() ?? '',
    extract: json['extract']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
    revisionId: _asInt(json['revision_id']),
    sections: json['sections'] is List
        ? [
            for (final section in json['sections'] as List)
              if (section is Map)
                MoegirlSection.fromJson(Map<String, dynamic>.from(section)),
          ]
        : const [],
  );

  Map<String, dynamic> toJson() => {
    'page_id': pageId,
    'title': title,
    'extract': extract,
    'url': url,
    'revision_id': revisionId,
    'sections': [for (final section in sections) section.toJson()],
  };
}

class MoegirlSection {
  const MoegirlSection({
    required this.title,
    required this.body,
    required this.level,
  });

  final String title;
  final String body;
  final int level;

  factory MoegirlSection.fromJson(Map<String, dynamic> json) => MoegirlSection(
    title: json['title']?.toString() ?? '',
    body: json['body']?.toString() ?? '',
    level: _asInt(json['level']).clamp(2, 6),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    'level': level,
  };
}

class MoegirlException implements Exception {
  const MoegirlException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Read-only enrichment through Moegirlpedia's public MediaWiki Action API.
class MoegirlService {
  MoegirlService({Dio? dio, CommunityCache? cache, this.cacheEnabled = true})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://zh.moegirl.org.cn',
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 45),
              responseType: ResponseType.json,
              headers: const {
                'Accept': 'application/json',
                'User-Agent':
                    'MuBangumi/$muBangumiUaVersion (https://github.com/wweiyi2004/MuBangumi)',
              },
            ),
          ),
      _cache = cache ?? CommunityCache.shared;

  static final shared = MoegirlService();

  static const pageOrigin = 'https://zh.moegirl.org.cn';
  static const _cacheVersion = 2;
  static const _hitMaxAge = Duration(days: 30);
  static const _missMaxAge = Duration(days: 3);

  final Dio _dio;
  final CommunityCache _cache;
  final bool cacheEnabled;

  Future<MoegirlEntry?> findForSubject(
    Subject subject, {
    bool forceRefresh = false,
  }) async {
    final titles = _candidateTitles(subject);
    if (titles.isEmpty) return null;
    final fingerprint = titles.join('\n');
    if (!forceRefresh) {
      final cached = await _readCache(subject.id, fingerprint);
      if (cached != null) return cached.entry;
    }

    final exact = await _requestPages({
      'action': 'query',
      'titles': titles.join('|'),
      ..._fullExtractQuery,
    });
    var entry = _selectEntry(exact, subject, minimumScore: 90);

    if (entry == null) {
      final prefix = await _requestPages({
        'action': 'query',
        'generator': 'prefixsearch',
        'gpssearch': titles.first,
        'gpsnamespace': 0,
        'gpslimit': 6,
        ..._introExtractQuery,
      }, optional: true);
      entry = _selectEntry(prefix, subject, minimumScore: 100);
      if (entry != null) {
        final full = await _requestPages({
          'action': 'query',
          'titles': entry.title,
          ..._fullExtractQuery,
        });
        // The full re-fetch only enriches the entry; when it yields no usable
        // page, keep the prefix result instead of discarding a trusted match.
        entry = _selectEntry(full, subject, minimumScore: 90) ?? entry;
      }
    }

    await _writeCache(subject.id, fingerprint, entry);
    return entry;
  }

  static const Map<String, dynamic> _queryBase = {
    'prop': 'extracts|pageprops|info',
    'redirects': 1,
    'inprop': 'url',
    'format': 'json',
    'formatversion': 2,
    'origin': '*',
    'maxlag': 5,
  };

  static const Map<String, dynamic> _fullExtractQuery = {
    ..._queryBase,
    'exsectionformat': 'raw',
  };

  static const Map<String, dynamic> _introExtractQuery = {
    ..._queryBase,
    'exintro': 1,
    'explaintext': 1,
  };

  Future<_ApiPages> _requestPages(
    Map<String, dynamic> query, {
    bool optional = false,
    int attempt = 0,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api.php',
        queryParameters: query,
      );
      if ((response.statusCode ?? 500) >= 400) {
        throw MoegirlException('萌娘百科请求失败（HTTP ${response.statusCode}）');
      }
      final data = response.data;
      if (data is! Map) {
        throw const MoegirlException('萌娘百科返回了无法识别的数据');
      }
      final root = Map<String, dynamic>.from(data);
      final error = root['error'];
      if (error is Map) {
        final code = error['code']?.toString() ?? '';
        if (optional && code == 'action-notallowed') {
          return const _ApiPages();
        }
        final info = error['info']?.toString().trim() ?? '';
        throw MoegirlException(info.isEmpty ? '萌娘百科接口暂时不可用' : info);
      }
      final result = root['query'];
      if (result is! Map) return const _ApiPages();
      final resultMap = Map<String, dynamic>.from(result);
      final pages = resultMap['pages'];
      final redirects = resultMap['redirects'];
      return _ApiPages(
        pages: pages is List
            ? [
                for (final page in pages)
                  if (page is Map)
                    _MoegirlCandidate.fromApi(Map<String, dynamic>.from(page)),
              ]
            : const [],
        redirectedTitles: redirects is List
            ? [
                for (final redirect in redirects)
                  if (redirect is Map && redirect['to'] != null)
                    redirect['to'].toString(),
              ]
            : const [],
      );
    } on MoegirlException {
      rethrow;
    } on DioException catch (error) {
      if (attempt == 0 && _shouldRetry(error)) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return _requestPages(query, optional: optional, attempt: 1);
      }
      // Dio rejects 4xx/5xx responses before the status check above, so
      // classify HTTP failures here instead of reporting them as connection
      // errors (the check above still guards injected Dio instances with a
      // non-default validateStatus).
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        throw MoegirlException('萌娘百科请求失败（HTTP $statusCode）');
      }
      throw MoegirlException(switch (error.type) {
        DioExceptionType.connectionTimeout => '连接萌娘百科超时，请检查网络后重试',
        DioExceptionType.receiveTimeout => '萌娘百科响应超时，请稍后重试',
        DioExceptionType.connectionError => '无法连接萌娘百科，请检查网络或代理设置',
        _ => '无法连接萌娘百科：${error.message ?? error}',
      });
    }
  }

  bool _shouldRetry(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return true;
    }
    final status = error.response?.statusCode;
    return status == 429 || status == 502 || status == 503 || status == 504;
  }

  MoegirlEntry? _selectEntry(
    _ApiPages response,
    Subject subject, {
    required int minimumScore,
  }) {
    final matchTitles = {
      ..._candidateTitles(subject),
      ...response.redirectedTitles,
    };
    _MoegirlCandidate? best;
    var bestScore = -1;
    for (final candidate in response.pages) {
      if (!candidate.isUsable) continue;
      final score = _candidateScore(candidate, subject, matchTitles);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    if (best == null || bestScore < minimumScore) return null;
    return best.toEntry();
  }

  int _candidateScore(
    _MoegirlCandidate candidate,
    Subject subject,
    Set<String> matchTitles,
  ) {
    final normalizedMatches = matchTitles.map(_normalizeTitle).toSet();
    final normalizedTitle = _normalizeTitle(candidate.title);
    final normalizedBase = _normalizeTitle(_baseTitle(candidate.title));
    var score = 0;
    if (normalizedMatches.contains(normalizedTitle)) {
      score += 120;
    } else if (normalizedMatches.contains(normalizedBase)) {
      score += 75;
    } else if (normalizedMatches.any(
      (title) => title.length >= 2 && normalizedTitle.startsWith(title),
    )) {
      score += 20;
    }

    final normalizedExtract = _normalizeTitle(candidate.extract);
    final originalName = _normalizeTitle(subject.name);
    final chineseName = _normalizeTitle(subject.nameCn);
    if (originalName.length >= 2 && normalizedExtract.contains(originalName)) {
      score += 25;
    }
    if (chineseName.length >= 2 &&
        chineseName != originalName &&
        normalizedExtract.contains(chineseName)) {
      score += 15;
    }

    final qualifier = _titleQualifier(candidate.title);
    if (qualifier.isNotEmpty) {
      score += _qualifierMatches(subject.type, qualifier) ? 20 : -20;
    }
    if (!normalizedMatches.contains(normalizedTitle) &&
        matchTitles.any((title) => candidate.title.startsWith('$title/'))) {
      score -= 40;
    }
    return score;
  }

  Future<_CachedEntry?> _readCache(int subjectId, String fingerprint) async {
    if (!cacheEnabled) return null;
    final json = await _cache.readJson(_cacheKey(subjectId));
    if (json == null ||
        json['version'] != _cacheVersion ||
        json['fingerprint'] != fingerprint) {
      return null;
    }
    final savedAt = DateTime.tryParse(json['saved_at']?.toString() ?? '');
    if (savedAt == null) return null;
    final rawEntry = json['entry'];
    final maxAge = rawEntry is Map ? _hitMaxAge : _missMaxAge;
    if (DateTime.now().difference(savedAt) > maxAge) return null;
    if (rawEntry is! Map) return const _CachedEntry(null);
    final entry = MoegirlEntry.fromJson(Map<String, dynamic>.from(rawEntry));
    if (entry.title.isEmpty ||
        (entry.extract.isEmpty && entry.sections.isEmpty) ||
        entry.url.isEmpty) {
      return null;
    }
    return _CachedEntry(entry);
  }

  Future<void> _writeCache(
    int subjectId,
    String fingerprint,
    MoegirlEntry? entry,
  ) async {
    if (!cacheEnabled) return;
    await _cache.writeJson(_cacheKey(subjectId), {
      'version': _cacheVersion,
      'fingerprint': fingerprint,
      'saved_at': DateTime.now().toIso8601String(),
      'entry': entry?.toJson(),
    });
  }

  static String _cacheKey(int subjectId) => 'moegirl_subject:$subjectId';
}

class _ApiPages {
  const _ApiPages({this.pages = const [], this.redirectedTitles = const []});

  final List<_MoegirlCandidate> pages;
  final List<String> redirectedTitles;
}

class _MoegirlCandidate {
  const _MoegirlCandidate({
    required this.pageId,
    required this.title,
    required this.extract,
    required this.sections,
    required this.url,
    required this.revisionId,
    required this.isDisambiguation,
    required this.isMissing,
  });

  factory _MoegirlCandidate.fromApi(Map<String, dynamic> json) {
    final pageProps = json['pageprops'];
    final props = pageProps is Map
        ? Map<String, dynamic>.from(pageProps)
        : const <String, dynamic>{};
    final title = json['title']?.toString().trim() ?? '';
    final rawExtract = json['extract']?.toString() ?? '';
    final parsedExtract = rawExtract.contains(RegExp(r'<h[2-6]\b'))
        ? _parseNativeExtract(rawExtract)
        : _ParsedExtract(intro: _stripHtml(rawExtract));
    return _MoegirlCandidate(
      pageId: _asInt(json['pageid']),
      title: title,
      extract: parsedExtract.intro,
      sections: parsedExtract.sections,
      url: json['fullurl']?.toString().trim().isNotEmpty == true
          ? json['fullurl'].toString().trim()
          : Uri.https('zh.moegirl.org.cn', '/$title').toString(),
      revisionId: _asInt(json['lastrevid']),
      isDisambiguation: props.containsKey('disambiguation'),
      isMissing: json.containsKey('missing') || _asInt(json['pageid']) <= 0,
    );
  }

  final int pageId;
  final String title;
  final String extract;
  final List<MoegirlSection> sections;
  final String url;
  final int revisionId;
  final bool isDisambiguation;
  final bool isMissing;

  bool get isUsable =>
      !isMissing &&
      !isDisambiguation &&
      title.isNotEmpty &&
      (extract.isNotEmpty || sections.isNotEmpty);

  MoegirlEntry toEntry() => MoegirlEntry(
    pageId: pageId,
    title: title,
    extract: extract,
    url: url,
    revisionId: revisionId,
    sections: sections,
  );
}

class _CachedEntry {
  const _CachedEntry(this.entry);

  final MoegirlEntry? entry;
}

List<String> _candidateTitles(Subject subject) {
  final titles = <String>[];
  for (final raw in [subject.nameCn, subject.name]) {
    final title = raw.trim().replaceAll('|', ' ');
    if (title.isEmpty ||
        titles.any((item) => _normalizeTitle(item) == _normalizeTitle(title))) {
      continue;
    }
    titles.add(title);
  }
  return titles;
}

String _normalizeTitle(String value) => value.toLowerCase().replaceAll(
  RegExp(r'[\s　·・:：!！?？,，.。;；「」『』《》〈〉【】\[\]()（）_\-—–~～/\\]'),
  '',
);

String _baseTitle(String title) =>
    title.replaceFirst(RegExp(r'[\(（][^\)）]+[\)）]\s*$'), '').trim();

String _titleQualifier(String title) =>
    RegExp(r'[\(（]([^\)）]+)[\)）]\s*$').firstMatch(title)?.group(1)?.trim() ??
    '';

bool _qualifierMatches(SubjectType type, String qualifier) {
  final allowed = switch (type) {
    SubjectType.anime => const ['动画', '漫画', '轻小说', '小说', '作品'],
    SubjectType.book => const ['漫画', '轻小说', '小说', '书籍', '绘本'],
    SubjectType.music => const ['歌曲', '音乐', '专辑'],
    SubjectType.game => const ['游戏'],
    SubjectType.real => const ['电视剧', '电影', '真人', '特摄'],
  };
  return allowed.any(qualifier.contains);
}

class _ParsedExtract {
  const _ParsedExtract({required this.intro, this.sections = const []});

  final String intro;
  final List<MoegirlSection> sections;
}

/// Strips block-level HTML out of a heading-less extract, keeping paragraph
/// breaks and decoding entity references (e.g. `&amp;`).
String _stripHtml(String source) {
  final fragment = html_parser.parseFragment(source);
  final blocks = <String>[
    for (final node in fragment.nodes)
      if (node is Element) _nativeBlockText(node),
  ].where((block) => block.isNotEmpty);
  if (blocks.isNotEmpty) return _compactText(blocks.join('\n\n'));
  // No block elements (e.g. plain text): decode entities via the DOM text.
  return _compactText(fragment.text ?? '');
}

_ParsedExtract _parseNativeExtract(String source) {
  final fragment = html_parser.parseFragment(source);
  final intro = <String>[];
  final sections = <MoegirlSection>[];
  String? currentTitle;
  var currentLevel = 2;
  var currentBlocks = <String>[];

  void flushSection() {
    final title = currentTitle;
    final body = _compactText(currentBlocks.join('\n\n'));
    if (title != null && title.isNotEmpty && body.isNotEmpty) {
      sections.add(
        MoegirlSection(title: title, body: body, level: currentLevel),
      );
    }
    currentBlocks = <String>[];
  }

  for (final node in fragment.nodes) {
    if (node is! Element) continue;
    final headingMatch = RegExp(r'^h([2-6])$').firstMatch(node.localName ?? '');
    if (headingMatch != null) {
      flushSection();
      currentTitle = _compactText(node.text);
      currentLevel = int.parse(headingMatch.group(1)!);
      continue;
    }
    final block = _nativeBlockText(node);
    if (block.isEmpty) continue;
    if (currentTitle == null) {
      intro.add(block);
    } else {
      currentBlocks.add(block);
    }
  }
  flushSection();
  return _ParsedExtract(
    intro: _compactText(intro.join('\n\n')),
    sections: sections,
  );
}

String _nativeBlockText(Element element) {
  switch (element.localName) {
    case 'p':
    case 'blockquote':
      return _compactText(element.text);
    case 'ul':
    case 'ol':
      final ordered = element.localName == 'ol';
      final items = element.children
          .where((child) => child.localName == 'li')
          .toList(growable: false);
      return [
        for (var index = 0; index < items.length; index++)
          '${ordered ? '${index + 1}.' : '•'} ${_compactText(items[index].text)}',
      ].where((line) => line.trim().length > 2).join('\n');
    case 'dl':
      return element.children
          .where((child) => child.localName == 'dt' || child.localName == 'dd')
          .map((child) => _compactText(child.text))
          .where((text) => text.isNotEmpty)
          .join('\n');
    case 'table':
      return element
          .querySelectorAll('tr')
          .map((row) {
            return row
                .querySelectorAll('th, td')
                .map((cell) => _compactText(cell.text))
                .where((text) => text.isNotEmpty)
                .join(' · ');
          })
          .where((row) => row.isNotEmpty)
          .join('\n');
    default:
      return '';
  }
}

String _compactText(String value) {
  final compact = value
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  final runes = compact.runes.toList(growable: false);
  if (runes.length <= 12000) return compact;
  return '${String.fromCharCodes(runes.take(12000)).trimRight()}…';
}

int _asInt(dynamic value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? 0,
};
