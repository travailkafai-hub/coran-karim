import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/riwaya.dart';

/// ChGPT: a paper page is not a verse number, particularly in Warsh.
/// Keep it separate from the existing reader's position and manual bookmark.
class MushafOpeningPosition {
  static String _key(Riwaya riwaya) => 'mushaf_opening_page_${riwaya.name}';

  static Future<int?> read(Riwaya riwaya, (int, int)? readerPosition) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(_key(riwaya));
    if (raw is! String) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['version'] != 1) return null;
      final page = data['page'];
      if (page is! int || page < 1 || page > 604) return null;
      // A later visit to the normal reader takes precedence over this page.
      if (data['readerSurah'] != readerPosition?.$1 ||
          data['readerAyah'] != readerPosition?.$2) {
        return null;
      }
      return page;
    } on FormatException {
      return null;
    }
  }

  static Future<void> save(
    Riwaya riwaya,
    int page,
    (int, int)? readerPosition,
  ) async {
    if (page < 1 || page > 604) return;
    final prefs = await SharedPreferences.getInstance();
    final value = jsonEncode({
      'version': 1,
      'page': page,
      'readerSurah': readerPosition?.$1,
      'readerAyah': readerPosition?.$2,
    });
    if (prefs.get(_key(riwaya)) != value) {
      await prefs.setString(_key(riwaya), value);
    }
  }
}
