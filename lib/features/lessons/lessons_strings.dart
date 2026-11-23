import '../../core/strings.dart';

/// Lesson feature strings. Call [LessonsStrings.ensure] before using the keys.
class LessonsStrings {
  static bool _registered = false;

  static void ensure() {
    if (_registered) return;
    _registered = true;
    S.register(_map);
  }

  static const Map<String, Map<String, String>> _map = {
    'en': {
      'lessons_title': 'Safety Lessons',
      'lessons_intro': 'Tap a lesson. Swipe the cards to learn.',
      'lessons_progress': 'lessons done',
      'lessons_cards': 'cards',
      'lessons_done': 'Done',
      'lesson_prev': 'Back',
      'lesson_next': 'Next',
      'lesson_finish': 'Finish',
      'lesson_completed': 'Lesson complete! Well done.',
      'lessons_load_error': 'Could not open the lesson.',
    },
    'hi': {
      'lessons_title': 'सुरक्षा पाठ',
      'lessons_intro': 'पाठ चुनें। कार्ड सरकाकर सीखें।',
      'lessons_progress': 'पाठ पूरे',
      'lessons_cards': 'कार्ड',
      'lessons_done': 'पूरा',
      'lesson_prev': 'पीछे',
      'lesson_next': 'आगे',
      'lesson_finish': 'पूरा करें',
      'lesson_completed': 'पाठ पूरा हुआ! शाबाश।',
      'lessons_load_error': 'पाठ नहीं खुल पाया।',
    },
    'chh': {
      'lessons_title': 'सुरक्छा के पाठ',
      'lessons_intro': 'पाठ चुन। कार्ड ल सरका के सीख।',
      'lessons_progress': 'पाठ पूरा',
      'lessons_cards': 'कार्ड',
      'lessons_done': 'पूरा',
      'lesson_prev': 'पाछू',
      'lesson_next': 'आगू',
      'lesson_finish': 'पूरा कर',
      'lesson_completed': 'पाठ पूरा होगे! साबास।',
      'lessons_load_error': 'पाठ नइ खुलिस।',
    },
  };
}
