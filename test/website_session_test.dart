import 'package:flutter_test/flutter_test.dart';
import 'package:mubangumi/core/auth/website_session.dart';

void main() {
  test('parseDocumentCookie splits name/value pairs', () {
    final cookies = WebsiteSessionSnapshot.parseDocumentCookie(
      'chii_sid=abc; chii_auth=xyz; theme=dark',
    );
    expect(cookies, hasLength(3));
    expect(cookies.first.name, 'chii_sid');
    expect(cookies.first.value, 'abc');
    expect(cookies[1].looksLikeSession, isTrue);
    expect(cookies[2].looksLikeSession, isFalse);
  });

  test('snapshot detects session cookies and builds header', () {
    final snapshot = WebsiteSessionSnapshot(
      cookies: const [
        WebsiteCookie(name: 'chii_sid', value: 's1'),
        WebsiteCookie(name: 'theme', value: 'dark'),
      ],
      syncedAt: DateTime.parse('2026-08-11T12:00:00Z'),
    );
    expect(snapshot.hasSessionCookies, isTrue);
    expect(snapshot.cookieHeader, 'chii_sid=s1; theme=dark');

    final restored = WebsiteSessionSnapshot.fromJson(snapshot.toJson());
    expect(restored.cookies, hasLength(2));
    expect(restored.cookies.first.name, 'chii_sid');
    expect(restored.hasSessionCookies, isTrue);
  });

  test('empty snapshot is not treated as synced', () {
    final snapshot = WebsiteSessionSnapshot(
      cookies: const [],
      syncedAt: DateTime.now(),
    );
    expect(snapshot.hasSessionCookies, isFalse);
    expect(snapshot.isEmpty, isTrue);
  });
}
