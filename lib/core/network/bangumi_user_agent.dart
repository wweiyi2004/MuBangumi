/// Centralized User-Agent versioning.
///
/// Update [muBangumiUaVersion] on every release so all outbound services
/// identify the same app version (Bangumi API, community P1, OAuth, RSS,
/// netaba.re, moegirl). Per-service suffixes stay local to each caller.
library;

const muBangumiUaVersion = '2.1.1';

/// Default UA used by the official Bangumi API and community clients.
const muBangumiUserAgent =
    'MuBangumi/$muBangumiUaVersion (Flutter; personal Bangumi client)';
