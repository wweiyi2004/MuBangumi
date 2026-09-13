import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../models/rss_models.dart';
import 'bangumi_user_agent.dart';

class RssFetchResult {
  const RssFetchResult({
    required this.entries,
    this.etag = '',
    this.lastModified = '',
    this.notModified = false,
  });

  final List<RssFeedEntry> entries;
  final String etag;
  final String lastModified;
  final bool notModified;
}

/// Fetches and parses RSS 2.0 / Atom feeds (torrent-site friendly).
class RssFetcher {
  RssFetcher({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              headers: const {
                'User-Agent':
                    'MuBangumi/$muBangumiUaVersion (RSS reminder; +local)',
                'Accept':
                    'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
              },
              // Raw bytes: dio's default transformer always assumes UTF-8,
              // which silently mangles GBK/GB2312 feeds into replacement
              // characters. Decoding happens in decodeFeedBytes.
              responseType: ResponseType.bytes,
              validateStatus: (code) =>
                  code != null && code >= 200 && code < 400,
            ),
          );

  final Dio _dio;

  /// Public for unit tests.
  ///
  /// Decodes raw feed bytes with the charset declared by the HTTP
  /// `Content-Type` header, then the feed's own XML declaration, then UTF-8.
  /// Without this a GBK/GB2312 feed decodes to U+FFFD replacement characters,
  /// every keyword match fails, and the source silently yields no entries.
  static String decodeFeedBytes(List<int> bytes, {String? contentType}) {
    final encoding = _feedEncoding(bytes, contentType);
    // Keep the long-standing lenient behaviour for the UTF-8 default; a
    // declared legacy encoding must decode with its own codec, strictly, so a
    // genuinely broken feed reports an error instead of yielding mojibake.
    if (identical(encoding, utf8)) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    return encoding.decode(bytes);
  }

  static final _httpCharset = RegExp(
    r'charset\s*=\s*"?([A-Za-z0-9_\-]+)',
    caseSensitive: false,
  );

  static final _declaredEncoding = RegExp(
    r'''encoding\s*=\s*["']([A-Za-z0-9_-]+)["']''',
    caseSensitive: false,
  );

  static Encoding _feedEncoding(List<int> bytes, String? contentType) {
    if (contentType != null) {
      final declared = _httpCharset.firstMatch(contentType)?.group(1);
      final resolved = declared == null ? null : Charset.getByName(declared);
      if (resolved != null) return resolved;
    }
    // The declaration must sit in the ASCII head of the document.
    final head = latin1.decode(
      bytes.length > 256 ? bytes.sublist(0, 256) : bytes,
      allowInvalid: true,
    );
    final sniffed = _declaredEncoding.firstMatch(head)?.group(1);
    final resolved = sniffed == null ? null : Charset.getByName(sniffed);
    return resolved ?? utf8;
  }

  Future<RssFetchResult> fetch(
    String url, {
    String etag = '',
    String lastModified = '',
  }) async {
    final headers = <String, dynamic>{};
    if (etag.isNotEmpty) headers['If-None-Match'] = etag;
    if (lastModified.isNotEmpty) headers['If-Modified-Since'] = lastModified;

    final response = await _dio.get<List<int>>(
      url,
      options: Options(headers: headers),
    );

    if (response.statusCode == 304) {
      return RssFetchResult(
        entries: const [],
        etag: etag,
        lastModified: lastModified,
        notModified: true,
      );
    }

    final body = decodeFeedBytes(
      response.data ?? const <int>[],
      contentType: response.headers.value('content-type'),
    );
    if (body.trim().isEmpty) {
      throw Exception('RSS 内容为空');
    }

    final responseEtag = response.headers.value('etag') ?? etag;
    final responseLm = response.headers.value('last-modified') ?? lastModified;

    return RssFetchResult(
      entries: parseFeedXml(body),
      etag: responseEtag,
      lastModified: responseLm,
    );
  }

  /// Public for unit tests.
  static List<RssFeedEntry> parseFeedXml(String body) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException {
      throw const FormatException('RSS 源返回了无法解析的内容');
    }
    final root = document.rootElement;
    final name = root.name.local.toLowerCase();

    if (name == 'rss' || name == 'rdf') {
      return _parseRss(document);
    }
    if (name == 'feed') {
      return _parseAtom(document);
    }
    // Some feeds wrap oddly; try both.
    final rssItems = _parseRss(document);
    if (rssItems.isNotEmpty) return rssItems;
    return _parseAtom(document);
  }

  static List<RssFeedEntry> _parseRss(XmlDocument document) {
    final items = document.findAllElements('item');
    final result = <RssFeedEntry>[];
    for (final item in items) {
      final title = _text(item, 'title');
      final link = _firstLink(item) ?? _text(item, 'link');
      final guid = _text(item, 'guid').isNotEmpty
          ? _text(item, 'guid')
          : (link.isNotEmpty ? link : title);
      if (title.isEmpty && link.isEmpty) continue;
      result.add(
        RssFeedEntry(
          guid: guid.isEmpty ? _stableGuid(title) : guid,
          title: title,
          link: link,
          publishedAt:
              _parseDate(_text(item, 'pubDate')) ??
              _parseDate(_text(item, 'date')),
        ),
      );
    }
    return result;
  }

  static List<RssFeedEntry> _parseAtom(XmlDocument document) {
    final entries = document.findAllElements('entry');
    final result = <RssFeedEntry>[];
    for (final entry in entries) {
      final title = _text(entry, 'title');
      final link = _atomLink(entry);
      final id = _text(entry, 'id');
      final guid = id.isNotEmpty ? id : (link.isNotEmpty ? link : title);
      if (title.isEmpty && link.isEmpty) continue;
      result.add(
        RssFeedEntry(
          guid: guid.isEmpty ? _stableGuid(title) : guid,
          title: title,
          link: link,
          publishedAt:
              _parseDate(_text(entry, 'updated')) ??
              _parseDate(_text(entry, 'published')),
        ),
      );
    }
    return result;
  }

  static String _text(XmlElement parent, String localName) {
    for (final child in parent.childElements) {
      if (child.name.local == localName) {
        return child.innerText.trim();
      }
    }
    return '';
  }

  static String? _firstLink(XmlElement item) {
    // enclosure often holds the torrent URL on tracker feeds.
    for (final child in item.childElements) {
      if (child.name.local == 'enclosure') {
        final url = child.getAttribute('url');
        if (url != null && url.isNotEmpty) return url.trim();
      }
    }
    for (final child in item.childElements) {
      if (child.name.local == 'link') {
        final href = child.getAttribute('href');
        if (href != null && href.isNotEmpty) return href.trim();
        final text = child.innerText.trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  /// Stable 32-bit FNV-1a digest so dedup GUIDs survive Dart runtime
  /// upgrades (unlike String.hashCode) without pulling in a crypto package.
  static String _stableGuid(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  static String _atomLink(XmlElement entry) {
    String alternate = '';
    String any = '';
    for (final child in entry.childElements) {
      if (child.name.local != 'link') continue;
      final href = child.getAttribute('href')?.trim() ?? '';
      if (href.isEmpty) continue;
      final rel = child.getAttribute('rel') ?? 'alternate';
      if (rel == 'alternate' && alternate.isEmpty) alternate = href;
      if (any.isEmpty) any = href;
      // Prefer enclosure / related for torrent feeds when present.
      if (rel == 'enclosure' || rel == 'related') return href;
    }
    return alternate.isNotEmpty ? alternate : any;
  }

  static DateTime? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      // RFC 822-ish: "Mon, 02 Jan 2006 15:04:05 +0000"
      try {
        return HttpDate.parse(raw);
      } catch (_) {
        return null;
      }
    }
  }
}

/// Minimal HTTP-date parser for RSS pubDate without dart:io dependency issues on web.
class HttpDate {
  static DateTime parse(String date) {
    // Fallback: strip weekday and use DateTime.tryParse after reformatting is hard;
    // use a simple regex for common torrent RSS dates.
    final match = RegExp(
      r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})'
      r'(?:\s+(UTC|GMT|([+-])(\d{2})(\d{2})))?',
    ).firstMatch(date);
    if (match == null) {
      throw FormatException('Bad HTTP date', date);
    }
    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final month = months[match.group(2)!];
    if (month == null) throw FormatException('Bad month', date);
    final base = DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
    // Respect explicit timezone offsets (e.g. "+0800") so non-UTC feeds are
    // not shifted by up to ±12h; RFC 822 dates without a zone stay UTC.
    final zone = match.group(7);
    if (zone == null || zone == 'UTC' || zone == 'GMT') return base;
    final sign = match.group(8) == '-' ? -1 : 1;
    final offset = Duration(
      hours: sign * int.parse(match.group(9)!),
      minutes: sign * int.parse(match.group(10)!),
    );
    return base.subtract(offset);
  }
}
