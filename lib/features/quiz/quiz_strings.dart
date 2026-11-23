import '../../core/strings.dart';

/// Quiz feature strings. Call [QuizStrings.ensure] before using the keys.
class QuizStrings {
  static bool _registered = false;

  static void ensure() {
    if (_registered) return;
    _registered = true;
    S.register(_map);
  }

  static const Map<String, Map<String, String>> _map = {
    'en': {
      'quiz_title': 'Safety Quiz',
      'quiz_intro': '20 short questions on OTP, ATM PIN, UPI PIN and QR codes.',
      'quiz_start': 'Start Quiz',
      'quiz_latest': 'Your last score',
      'quiz_question': 'Question',
      'quiz_correct': 'Correct!',
      'quiz_wrong': 'Wrong',
      'quiz_next': 'Next',
      'quiz_see_result': 'See my score',
      'quiz_score_title': 'Digital Financial Literacy Score',
      'quiz_level': 'Level',
      'quiz_breakdown': 'Topic-wise result',
      'quiz_revise': 'Revise this lesson',
      'quiz_retry': 'Try again',
      'quiz_all_correct': 'All topics perfect! You are a Champion.',
      'quiz_load_error': 'Could not open the quiz.',
      'level_beginner': 'Beginner',
      'level_aware': 'Aware',
      'level_safe': 'Safe',
      'level_champion': 'Champion',
      'quiz_topic_otp': 'OTP',
      'quiz_topic_atm_pin': 'ATM PIN',
      'quiz_topic_upi_pin': 'UPI PIN',
      'quiz_topic_qr': 'QR code',
    },
    'hi': {
      'quiz_title': 'सुरक्षा प्रश्नोत्तरी',
      'quiz_intro': 'OTP, ATM PIN, UPI PIN और QR कोड पर 20 छोटे सवाल।',
      'quiz_start': 'शुरू करें',
      'quiz_latest': 'आपका पिछला स्कोर',
      'quiz_question': 'सवाल',
      'quiz_correct': 'सही!',
      'quiz_wrong': 'गलत',
      'quiz_next': 'आगे',
      'quiz_see_result': 'मेरा स्कोर देखें',
      'quiz_score_title': 'डिजिटल वित्तीय साक्षरता स्कोर',
      'quiz_level': 'स्तर',
      'quiz_breakdown': 'विषय के अनुसार नतीजा',
      'quiz_revise': 'यह पाठ दोबारा पढ़ें',
      'quiz_retry': 'फिर से खेलें',
      'quiz_all_correct': 'सभी विषय पूरे सही! आप चैंपियन हैं।',
      'quiz_load_error': 'प्रश्नोत्तरी नहीं खुल पाई।',
      'level_beginner': 'शुरुआती',
      'level_aware': 'जागरूक',
      'level_safe': 'सुरक्षित',
      'level_champion': 'चैंपियन',
      'quiz_topic_otp': 'OTP',
      'quiz_topic_atm_pin': 'ATM PIN',
      'quiz_topic_upi_pin': 'UPI PIN',
      'quiz_topic_qr': 'QR कोड',
    },
    'chh': {
      'quiz_title': 'सुरक्छा सवाल-जवाब',
      'quiz_intro': 'OTP, ATM PIN, UPI PIN अउ QR कोड ऊपर 20 छोटे सवाल।',
      'quiz_start': 'सुरू कर',
      'quiz_latest': 'तोर पिछला स्कोर',
      'quiz_question': 'सवाल',
      'quiz_correct': 'सही!',
      'quiz_wrong': 'गलत',
      'quiz_next': 'आगू',
      'quiz_see_result': 'मोर स्कोर देखा',
      'quiz_score_title': 'डिजिटल पइसा समझ स्कोर',
      'quiz_level': 'स्तर',
      'quiz_breakdown': 'बिसय के हिसाब ले नतीजा',
      'quiz_revise': 'ए पाठ ल फेर पढ़',
      'quiz_retry': 'फेर खेल',
      'quiz_all_correct': 'जम्मो बिसय सही! तैं चैंपियन अस।',
      'quiz_load_error': 'सवाल-जवाब नइ खुलिस।',
      'level_beginner': 'नवसिखिया',
      'level_aware': 'जागरूक',
      'level_safe': 'सुरक्छित',
      'level_champion': 'चैंपियन',
      'quiz_topic_otp': 'OTP',
      'quiz_topic_atm_pin': 'ATM PIN',
      'quiz_topic_upi_pin': 'UPI PIN',
      'quiz_topic_qr': 'QR कोड',
    },
  };
}
