import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/rss_fetcher.dart';

/// Regression guard: dio's default transformer always assumes UTF-8 and never
/// consults the response charset, so a GBK/GB2312 feed used to decode to
/// U+FFFD replacement characters. Every keyword match then failed and the
/// source silently produced no entries and no reminders.
void main() {
  const title = '【字幕组】葬送的芙莉莲 第01话 [1080p]';

  String feed({String? declaredEncoding}) {
    final declaration = declaredEncoding == null
        ? ''
        : ' encoding="$declaredEncoding"';
    return '<?xml version="1.0"$declaration?>'
        '<rss version="2.0"><channel><item>'
        '<title>$title</title>'
        '<link>https://example.test/1</link>'
        '<guid>ep-1</guid>'
        '</item></channel></rss>';
  }

  test('decodes a GBK feed declared in the XML declaration', () {
    final bytes = gbk.encode(feed(declaredEncoding: 'gb2312'));

    // The pre-fix behaviour, asserted so this test cannot pass vacuously.
    expect(utf8.decode(bytes, allowMalformed: true), contains('�'));

    final body = RssFetcher.decodeFeedBytes(bytes);
    expect(body, contains(title));

    final entries = RssFetcher.parseFeedXml(body);
    expect(entries, hasLength(1));
    expect(entries.single.title, title);
    expect(entries.single.guid, 'ep-1');
  });

  test('decodes a GBK feed declared only by the HTTP Content-Type header', () {
    final bytes = gbk.encode(feed());
    expect(utf8.decode(bytes, allowMalformed: true), contains('�'));

    final body = RssFetcher.decodeFeedBytes(
      bytes,
      contentType: 'application/rss+xml; charset=gb2312',
    );
    expect(RssFetcher.parseFeedXml(body).single.title, title);
  });

  test('accepts a quoted charset parameter', () {
    final bytes = gbk.encode(feed());
    final body = RssFetcher.decodeFeedBytes(
      bytes,
      contentType: 'text/xml; charset="GBK"',
    );
    expect(body, contains(title));
  });

  test('leaves UTF-8 feeds untouched', () {
    final bytes = utf8.encode(feed(declaredEncoding: 'utf-8'));
    final body = RssFetcher.decodeFeedBytes(
      bytes,
      contentType: 'application/rss+xml; charset=utf-8',
    );
    expect(body, contains(title));
    expect(RssFetcher.parseFeedXml(body).single.title, title);
  });

  test('falls back to UTF-8 when nothing declares an encoding', () {
    final bytes = utf8.encode(feed());
    expect(RssFetcher.decodeFeedBytes(bytes), contains(title));
  });

  test('tolerates malformed bytes in an undeclared UTF-8 feed', () {
    // Preserves the long-standing lenient default decoding.
    final body = RssFetcher.decodeFeedBytes(const [0x3C, 0x61, 0xFF, 0x3E]);
    expect(body, contains('�'));
  });
}
