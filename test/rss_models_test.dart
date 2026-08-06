import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/network/rss_fetcher.dart';
import 'package:mubangumi/models/rss_models.dart';

void main() {
  test('binding matches title with keywords and excludes', () {
    const binding = RssBinding(
      id: 1,
      sourceId: 1,
      subjectId: 12,
      subjectName: '迷宫饭',
      matchKeywords: '迷宫饭',
      excludeKeywords: '合集,SP',
    );
    expect(binding.matchesTitle('[组] 迷宫饭 - 05 [1080p]'), isTrue);
    expect(binding.matchesTitle('[组] 迷宫饭 合集'), isFalse);
    expect(binding.matchesTitle('[组] 别的番 - 01'), isFalse);
  });

  test('parse RSS 2.0 items', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Test</title>
    <item>
      <title>[Sub] Dungeon Meshi - 05</title>
      <link>https://example.com/a</link>
      <guid>g-1</guid>
      <pubDate>Mon, 02 Jan 2006 15:04:05 +0000</pubDate>
    </item>
    <item>
      <title>Second</title>
      <enclosure url="https://example.com/b.torrent" type="application/x-bittorrent"/>
      <guid>g-2</guid>
    </item>
  </channel>
</rss>
''';
    final entries = RssFetcher.parseFeedXml(xml);
    expect(entries, hasLength(2));
    expect(entries.first.title, contains('Dungeon Meshi'));
    expect(entries.first.link, 'https://example.com/a');
    expect(entries[1].link, 'https://example.com/b.torrent');
  });

  test('parse Atom entries', () {
    const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Feed</title>
  <entry>
    <title>Atom Show 01</title>
    <id>atom-1</id>
    <link href="https://example.com/atom" rel="alternate"/>
    <updated>2026-01-02T12:00:00Z</updated>
  </entry>
</feed>
''';
    final entries = RssFetcher.parseFeedXml(xml);
    expect(entries, hasLength(1));
    expect(entries.first.guid, 'atom-1');
    expect(entries.first.link, 'https://example.com/atom');
  });
}
