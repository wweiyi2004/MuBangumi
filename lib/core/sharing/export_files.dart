import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ExportFiles {
  ExportFiles._();

  static Future<Directory> directory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      return Directory(path.join(docs.path, 'exports'));
    }
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return Directory(path.join(downloads.path, 'MuBangumi'));
      }
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    return Directory(path.join(docs.path, 'MuBangumi', 'exports'));
  }

  static Future<void> reveal(String filePath) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path.dirname(filePath)]);
      }
    } catch (_) {
      // Opening the file manager is optional after the export has succeeded.
    }
  }
}
