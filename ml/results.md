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
