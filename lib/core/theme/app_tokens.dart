import 'package:flutter/widgets.dart';

/// Corner radii. Tags use [sm], cards and fields [md], sheets and dialogs
/// [lg]; buttons and status chips are pills. Chart bars use [mark] so short
/// bars stay rectangular instead of becoming dots.
abstract final class AppRadius {
  static const mark = 4.0, sm = 8.0, md = 12.0, lg = 16.0, pill = 999.0;
  static const bar = BorderRadius.all(Radius.circular(mark));
  static const small = BorderRadius.all(Radius.circular(sm));
  static const medium = BorderRadius.all(Radius.circular(md));
  static const large = BorderRadius.all(Radius.circular(lg));
  static const round = BorderRadius.all(Radius.circular(pill));
}

/// Maximum content widths on wide windows.
abstract final class AppWidth {
  /// Settings, forms and long reading text.
  static const reading = 720.0;

  /// Lists, profiles and detail pages.
  static const content = 960.0;

  /// Dashboards, discovery grids and the BanJian console.
  static const wide = 1200.0;
}

/// Smallest text sizes. Captions go no lower than [caption]; [timestamp] is
/// reserved for times and counters beside other text.
abstract final class AppText {
  static const caption = 13.0, timestamp = 12.0;
}

/// Fixed colors that are not part of the color scheme. Scores use the
/// scheme's tertiary amber, not these.
abstract final class AppPalette {
  /// Home shortcut tiles: schedule, calendar, recommendations, discovery.
  static const shortcutSchedule = Color(0xFF7C6CE7);
  static const shortcutCalendar = Color(0xFFE95383);
  static const shortcutRecommend = Color(0xFFE38A3F);
  static const shortcutDiscover = Color(0xFF2CA69A);

  /// Something happening now, such as a round that is open for scores.
  static const live = Color(0xFF35A78A);

  /// Score movement, red for a rise and green for a fall.
  static Color rise(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFFF929B) : const Color(0xFFBB3044);
  static Color fall(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF80DDB5) : const Color(0xFF187650);

  /// Profile header wash behind the avatar.
  static const profileHeaderLight = [
    Color(0xFFF2DDE5),
    Color(0xFFE3E9F2),
    Color(0xFFEAF1EC),
  ];
  static const profileHeaderDark = [Color(0xFF393245), Color(0xFF283D43)];

  /// QR surfaces stay light on any theme so codes scan reliably.
  static const qrAvatar = Color(0xFFFFD6E4);

  /// Scan frame over the camera feed, which is always dark.
  static const scanAccent = Color(0xFFFF77A2);
}
