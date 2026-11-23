# Lessons: native-speaker review needed

English is final. Hindi and Chhattisgarhi text was machine-drafted and must be checked by a native speaker.

| File | Hindi (hi) | Chhattisgarhi (chh) |
|---|---|---|
| assets/lessons/otp.json | review | review (priority) |
| assets/lessons/atm_pin.json | review | review (priority) |
| assets/lessons/upi_pin.json | review | review (priority) |
| assets/lessons/qr.json | review | review (priority) |
| assets/quiz/otp.json | review | review (priority) |
| assets/quiz/atm_pin.json | review | review (priority) |
| assets/quiz/upi_pin.json | review | review (priority) |
| assets/quiz/qr.json | review | review (priority) |
| lib/features/lessons/lessons_strings.dart | review | review (priority) |
| lib/features/quiz/quiz_strings.dart | review | review (priority) |

Check that the Hindi uses simple everyday words, and that the Chhattisgarhi is short and natural
(for example: झन, नइ, घलो, तुरते, पइसा, सिरिफ). Also check the spelling of सुरक्छा / सुरक्छित.

Note: quiz JSON adds an `explain` field ({en,hi,chh}) to each question for the one-line feedback.
The lesson card colour is chosen in the app from the card's position (the lesson schema has no colour field).
