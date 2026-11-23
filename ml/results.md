# Scam classifier results
Before extra_train.csv: full test acc 0.9838 / F1 0.9671 (C=100); hand-written acc 0.8971 / F1 0.8955 (EN 0.8333, HI 0.9545, Hinglish 0.9091).

Extra hand-written train rows added (no augmentation): 175.
TF-IDF (1,2)-grams, min_df=2, l2 + LogisticRegression(class_weight='balanced'), C=100 (5-fold StratifiedGroupKFold CV on train, scam-F1 0.9765).
Train rows after augmentation: 7673 (pre-aug 5881); vocabulary: 19709.
Positive class = scam. Test set = 20% stratified hold-out (split before augmentation) + hand-written messages.

CV scam-F1 by C: C=0.3: 0.9629, C=1: 0.9700, C=3: 0.9732, C=10: 0.9744, C=30: 0.9756, C=100: 0.9765

## Full test.csv

### All (n=1539)

| accuracy | precision | recall | F1 |
|---|---|---|---|
| 0.9864 | 0.9712 | 0.9738 | 0.9725 |

| true \ pred | genuine | scam |
|---|---|---|
| genuine | 1147 | 11 |
| scam | 10 | 371 |

### English (n=1139)

| accuracy | precision | recall | F1 |
|---|---|---|---|
| 0.9816 | 0.9402 | 0.9454 | 0.9428 |

| true \ pred | genuine | scam |
|---|---|---|
| genuine | 945 | 11 |
| scam | 10 | 173 |

### Hindi (Devanagari) (n=200)

| accuracy | precision | recall | F1 |
|---|---|---|---|
| 1.0000 | 1.0000 | 1.0000 | 1.0000 |

| true \ pred | genuine | scam |
|---|---|---|
| genuine | 101 | 0 |
| scam | 0 | 99 |

### Hinglish (n=200)

| accuracy | precision | recall | F1 |
|---|---|---|---|
| 1.0000 | 1.0000 | 1.0000 | 1.0000 |

| true \ pred | genuine | scam |
|---|---|---|
| genuine | 101 | 0 |
| scam | 0 | 99 |

## Hand-written subset only (most realistic; templated test rows share templates with train)

### Hand-written, all (n=68)

| accuracy | precision | recall | F1 |
|---|---|---|---|
| 0.9853 | 1.0000 | 0.9706 | 0.9851 |

| true \ pred | genuine | scam |
|---|---|---|
| genuine | 34 | 0 |
| scam | 1 | 33 |

### Hand-written, English (n=24)

| accuracy | precision | recall | F1 |
|---|---|---|---|
| 0.9583 | 1.0000 | 0.9167 | 0.9565 |

| true \ pred | genuine | scam |
|---|---|---|
| genuine | 12 | 0 |
| scam | 1 | 11 |

### Hand-written, Hindi (Devanagari) (n=22)

| accuracy | precision | recall | F1 |
|---|---|---|---|
| 1.0000 | 1.0000 | 1.0000 | 1.0000 |

| true \ pred | genuine | scam |
|---|---|---|
| genuine | 11 | 0 |
| scam | 0 | 11 |

### Hand-written, Hinglish (n=22)

| accuracy | precision | recall | F1 |
|---|---|---|---|
| 1.0000 | 1.0000 | 1.0000 | 1.0000 |

| true \ pred | genuine | scam |
|---|---|---|
| genuine | 11 | 0 |
| scam | 0 | 11 |

### Hand-written errors

| label | pred | text |
|---|---|---|
| scam | genuine | Hi, I am calling from HDFC credit card desk. A code has come on your phone just now, please read it out so we can stop the annual charge |

## Held-out 2026 (clean, unseen) - the number to quote

`ml/data/heldout_2026.csv`: 108 new hand-written messages (36 English, 36 Hindi in Devanagari, 36 Hinglish;
half scam, half genuine), written after the model was frozen. They were never used for training, C tuning, or
the `extra_train.csv` additions, and the model was **not** changed after seeing these results.
`test/engine/heldout_eval_test.dart` checks that no message equals, or has token-set Jaccard >= 0.8 with, any row
in `train.csv`, `test.csv`, `extra_train.csv`, `hindi_hinglish.csv`, `indian_english.csv`, the older hand-written
set or the in-app examples. It then scores the **shipped Dart model** (`assets/models/scam_model.json`, threshold
0.5) and fails if the numbers below differ.

Why these differ from the figures above: the earlier hand-written set (`ml/handwritten_test.py`) was looked at
while adding `extra_train.csv`, and the templated rows in `test.csv` share templates with train, so those numbers
are optimistic. English is the weakest language: scams without the usual keywords (wrong-transfer refund,
"install TeamViewer", APK invitations) are missed, and ordinary delivery or bank-alert texts are sometimes flagged.
### Held-out 2026, all (n=108)

| accuracy | precision | recall | F1 |
|---|---|---|---|
| 0.8981 | 0.8772 | 0.9259 | 0.9009 |

| true \ pred | genuine | scam |
|---|---|---|
| genuine | 47 | 7 |
| scam | 4 | 50 |

### Held-out 2026, English (n=36)

| accuracy | precision | recall | F1 |
|---|---|---|---|
| 0.7778 | 0.7778 | 0.7778 | 0.7778 |

| true \ pred | genuine | scam |
|---|---|---|
| genuine | 14 | 4 |
| scam | 4 | 14 |

### Held-out 2026, Hindi (Devanagari) (n=36)

| accuracy | precision | recall | F1 |
|---|---|---|---|
| 0.9167 | 0.8571 | 1.0000 | 0.9231 |

| true \ pred | genuine | scam |
|---|---|---|
| genuine | 15 | 3 |
| scam | 0 | 18 |

### Held-out 2026, Hinglish (n=36)

| accuracy | precision | recall | F1 |
|---|---|---|---|
| 1.0000 | 1.0000 | 1.0000 | 1.0000 |

| true \ pred | genuine | scam |
|---|---|---|
| genuine | 18 | 0 |
| scam | 0 | 18 |

### Held-out 2026 errors

| label | pred | score | lang | text |
|---|---|---|---|---|
| scam | genuine | 0.12 | en | Hello sir, I accidentally transferred 4500 to your Paytm. I am a poor student, please return it to my number, check your balance |
| scam | genuine | 0.02 | en | Your Amazon order refund of Rs 3,299 failed. Our support agent will call you; install TeamViewer so he can process it |
| scam | genuine | 0.49 | en | Hi dear, I saw your profile and want to video chat. Click here and pay 99 to unlock my private photos |
| scam | genuine | 0.25 | en | Wedding invitation from Rahul and Priya. Open the attached file invitation.apk to see the card and venue details |
| genuine | scam | 0.95 | en | Your SBI debit card ending 4421 was used for Rs 1,250 at a fuel station on 12-Nov. Not you? Call 1800 1234 (SBI toll free) |
| genuine | scam | 0.73 | en | Your order of 2 kg atta and oil from BigBasket has been delivered. Rate your experience in the app. |
| genuine | scam | 0.54 | en | Rs 1,000 has been credited to your account under Mahtari Vandan Yojana for November. - Govt of Chhattisgarh |
| genuine | scam | 0.56 | en | Your Flipkart return pickup is scheduled for tomorrow between 9 am and 1 pm. Keep the product packed with tags. |
| genuine | scam | 0.88 | hi | आपका राशन इस महीने 5 तारीख से उचित मूल्य दुकान पर मिलेगा। |
| genuine | scam | 0.60 | hi | दीदी, आज स्कूल की छुट्टी जल्दी हो गई, मैं मौसी के घर पर हूँ |
| genuine | scam | 0.77 | hi | आपकी पेंशन 1,500 रुपये आपके डाकघर खाते में जमा कर दी गई है। |
