import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// key -> value for one language block of every `'en' | 'hi' | 'chh': { ... }` string map in lib/.
Map<String, Map<String, String>> _scan() {
  final out = <String, Map<String, String>>{'en': {}, 'hi': {}, 'chh': {}};
  final block = RegExp(r"^\s*'(en|hi|chh)'\s*:\s*\{", multiLine: true);
  final entry = RegExp(r"""^\s*'([A-Za-z0-9_]+)'\s*:\s*(?:\n\s*)?(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""",
      multiLine: true);
  final end = RegExp(r'^\s{0,6}\},?\s*$', multiLine: true);
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    final src = f.readAsStringSync();
    final blocks = block.allMatches(src).toList();
    for (var i = 0; i < blocks.length; i++) {
      final stop = i + 1 < blocks.length ? blocks[i + 1].start : src.length;
      var body = src.substring(blocks[i].end, stop);
      final e = end.firstMatch(body);
      if (e != null) body = body.substring(0, e.start);
      for (final m in entry.allMatches(body)) {
        out[blocks[i].group(1)]![m.group(1)!] = m.group(2) ?? m.group(3) ?? '';
      }
    }
  }
  return out;
}

void main() {
  test('every UI string exists in en, hi and chh, and hi/chh are translated (Devanagari)', () {
    final s = _scan();
    expect(s['en']!.length, greaterThan(300));
    for (final lang in ['hi', 'chh']) {
      final missing = s['en']!.keys.where((k) => !s[lang]!.containsKey(k)).toList()..sort();
      expect(missing, isEmpty, reason: 'missing in $lang');
      final extra = s[lang]!.keys.where((k) => !s['en']!.containsKey(k)).toList()..sort();
      expect(extra, isEmpty, reason: 'only in $lang');
      final untranslated = [
        for (final k in s['en']!.keys)
          if (s[lang]![k] == s['en']![k] &&
              RegExp('[a-z]{4,}').hasMatch(s['en']![k]!) &&
              !s['en']![k]!.contains('.gov.in'))
            k,
      ];
      expect(untranslated, isEmpty, reason: 'same as English in $lang');
    }
  });

  test('every literal t(\'key\') used in lib/ is defined', () {
    final defined = _scan()['en']!.keys.toSet();
    final used = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      used.addAll(RegExp(r"\.t\('([A-Za-z0-9_]+)'\)").allMatches(f.readAsStringSync()).map((m) => m.group(1)!));
    }
    expect(used.difference(defined).toList()..sort(), isEmpty);
  });

  test('every quiz topic has at least 5 questions with a valid answer', () {
    for (final f in Directory('assets/quiz').listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final qs = (jsonDecode(f.readAsStringSync()) as Map)['questions'] as List;
      expect(qs.length, greaterThanOrEqualTo(5), reason: f.path);
      for (final q in qs.cast<Map>()) {
        expect(q['answer'], lessThan(((q['options'] as Map)['en'] as List).length), reason: f.path);
      }
    }
  });

  test('lessons and quiz have en/hi/chh for every text and the same number of options', () {
    void walk(Object? o, String path, List<String> bad) {
      if (o is Map) {
        if (o.keys.any((k) => const {'en', 'hi', 'chh'}.contains(k))) {
          for (final l in ['en', 'hi', 'chh']) {
            final v = o[l];
            if (v == null || v == '' || (v is List && v.isEmpty)) bad.add('$path.$l');
          }
          if (o['en'] is List && {for (final l in ['en', 'hi', 'chh']) (o[l] as List?)?.length}.length != 1) {
            bad.add('$path options');
          }
          return;
        }
        o.forEach((k, v) => walk(v, '$path.$k', bad));
      } else if (o is List) {
        for (var i = 0; i < o.length; i++) {
          walk(o[i], '$path[$i]', bad);
        }
      }
    }

    for (final dir in ['assets/lessons', 'assets/quiz']) {
      for (final f in Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
        final bad = <String>[];
        walk(jsonDecode(f.readAsStringSync()), f.uri.pathSegments.last, bad);
        expect(bad, isEmpty, reason: f.path);
      }
    }
  });
}
