import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

/// Lesson ids, in display order. Each has `assets/lessons/{id}.json` and `assets/quiz/{id}.json`.
const List<String> kLessonIds = ['otp', 'atm_pin', 'upi_pin', 'qr'];

Map<String, String> _locMap(dynamic m) =>
    (m as Map).map((k, v) => MapEntry(k.toString(), v.toString()));

/// Picks [lang] from a {en,hi,chh} map, falling back to English.
String pickLang(Map<String, String> m, String lang) => m[lang] ?? m['en'] ?? '';

class LessonCard {
  final String icon;
  final Map<String, String> text;
  const LessonCard({required this.icon, required this.text});

  factory LessonCard.fromJson(Map<String, dynamic> j) =>
      LessonCard(icon: j['icon'].toString(), text: _locMap(j['text']));
}

class Lesson {
  final String id;
  final Map<String, String> title;
  final List<LessonCard> cards;
  const Lesson({required this.id, required this.title, required this.cards});

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        id: j['id'].toString(),
        title: _locMap(j['title']),
        cards: (j['cards'] as List)
            .map((c) => LessonCard.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList(),
      );
}

class LessonRepository {
  static Future<Lesson> load(String id) async {
    final raw = await rootBundle.loadString('assets/lessons/$id.json');
    return Lesson.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  static Future<List<Lesson>> loadAll() => Future.wait(kLessonIds.map(load));
}

/// Lesson completion ticks stored in shared_preferences.
class LessonProgress {
  static String _key(String id) => 'lesson_done_$id';

  static Future<Set<String>> completed() async {
    try {
      final p = await SharedPreferences.getInstance();
      return kLessonIds.where((id) => p.getBool(_key(id)) ?? false).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> markDone(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key(id), true);
    } catch (_) {}
  }
}

const Map<String, IconData> _icons = {
  'sms': Icons.sms_rounded,
  'lock': Icons.lock_rounded,
  'phone_disabled': Icons.phone_disabled_rounded,
  'block': Icons.block_rounded,
  'support_agent': Icons.support_agent_rounded,
  'credit_card': Icons.credit_card_rounded,
  'visibility_off': Icons.visibility_off_rounded,
  'person_off': Icons.person_off_rounded,
  'edit_off': Icons.edit_off_rounded,
  'pin': Icons.pin_rounded,
  'call_received': Icons.call_received_rounded,
  'warning': Icons.warning_rounded,
  'voice_over_off': Icons.voice_over_off_rounded,
  'verified_user': Icons.verified_user_rounded,
  'qr_code_2': Icons.qr_code_2_rounded,
  'qr_code_scanner': Icons.qr_code_scanner_rounded,
  'storefront': Icons.storefront_rounded,
  'layers': Icons.layers_rounded,
};

IconData lessonCardIcon(String name) => _icons[name] ?? Icons.lightbulb_rounded;

const Map<String, IconData> _topicIcons = {
  'otp': Icons.sms_rounded,
  'atm_pin': Icons.credit_card_rounded,
  'upi_pin': Icons.pin_rounded,
  'qr': Icons.qr_code_2_rounded,
};

IconData lessonTopicIcon(String id) => _topicIcons[id] ?? Icons.school_rounded;

const Map<String, Color> _topicColors = {
  'otp': Color(0xFF00796B),
  'atm_pin': Color(0xFF0D47A1),
  'upi_pin': Color(0xFF6A1B9A),
  'qr': Color(0xFFE65100),
};

Color lessonTopicColor(String id) => _topicColors[id] ?? const Color(0xFF00796B);

/// Card colour blocks, chosen by card position (schema has no colour field).
const List<Color> kCardColors = [
  Color(0xFF00796B),
  Color(0xFF0D47A1),
  Color(0xFFC62828),
  Color(0xFF6A1B9A),
  Color(0xFF2E7D32),
];
