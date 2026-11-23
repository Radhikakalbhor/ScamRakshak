"""Augments train.csv only, tunes C with grouped CV on train, fits TF-IDF + LogisticRegression,
evaluates on test.csv, writes ml/results.md, saves ml/artifacts/model.joblib and exports the Dart model.
Run build_dataset.py first."""
import os
import random

import joblib
import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, make_scorer, precision_score, recall_score
from sklearn.model_selection import GridSearchCV, StratifiedGroupKFold
from sklearn.pipeline import Pipeline

import export_model
from preprocess import TOKEN_PATTERN, norm_key, preprocess, tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
ART = os.path.join(HERE, "artifacts")
R = random.Random(7)

HINGLISH_VARIANTS = {"hai": "h", "nahi": "nhi", "kya": "kia", "aapka": "apka", "aapke": "apke", "karo": "kro",
                     "kare": "kre", "please": "plz", "account": "acc", "jaldi": "jldi", "paise": "pese",
                     "turant": "turnt", "bhej": "bhejo", "raha": "rha", "message": "msg"}


def augment_one(text, lang):
    words = text.split()
    op = R.choice(["drop", "digits", "variant", "url"] if lang != "hi" else ["drop", "digits", "url"])
    if op == "drop" and len(words) > 5:
        i = R.randrange(len(words))
        words = words[:i] + words[i + 1:]
    elif op == "variant" and lang == "hinglish":
        words = [HINGLISH_VARIANTS.get(w.lower(), w) for w in words]
    elif op == "url":
        words = [w for w in words if "urltoken" not in preprocess(w)]
    else:
        words = ["".join(R.choice("0123456789") if c.isdigit() else c for c in w) for w in words]
    return " ".join(words)


def load_extra(test):
    """Hand-written extra TRAIN rows (not augmented). Drops exact matches and rows with token-set
    Jaccard >= 0.8 against any test.csv row."""
    path = os.path.join(DATA, "extra_train.csv")
    if not os.path.exists(path):
        return pd.DataFrame(columns=["text", "label", "lang", "source"])
    ex = pd.read_csv(path, encoding="utf-8")
    test_sets = [set(tokenize(t)) for t in test.text]
    test_texts = set(test.text)

    def ok(t):
        a = set(tokenize(t))
        if t in test_texts or not a:
            return False
        return all(len(a & b) / len(a | b) < 0.8 for b in test_sets if b)

    keep = ex.text.map(ok)
    print(f"extra_train: {len(ex)} rows, kept {int(keep.sum())}, dropped {int((~keep).sum())}")
    ex = ex[keep].copy()
    ex["lang"] = ["hi" if any("ऀ" <= c <= "ॿ" for c in t) else "en" for t in ex.text]
    ex["source"], ex["category"] = "extra", "extra"
    return ex


def make_pipeline(C=1.0):
    return Pipeline([
        ("tfidf", TfidfVectorizer(preprocessor=preprocess, token_pattern=TOKEN_PATTERN, ngram_range=(1, 2),
                                  min_df=2, norm="l2", sublinear_tf=False, lowercase=False)),
        ("lr", LogisticRegression(class_weight="balanced", C=C, max_iter=5000, solver="liblinear")),
    ])


def metrics(y, p):
    return {
        "n": len(y),
        "accuracy": accuracy_score(y, p),
        "precision": precision_score(y, p, pos_label="scam", zero_division=0),
        "recall": recall_score(y, p, pos_label="scam", zero_division=0),
        "f1": f1_score(y, p, pos_label="scam", zero_division=0),
        "cm": confusion_matrix(y, p, labels=["genuine", "scam"]),
    }


def md_block(title, m):
    cm = m["cm"]
    return (f"### {title} (n={m['n']})\n\n"
            f"| accuracy | precision | recall | F1 |\n|---|---|---|---|\n"
            f"| {m['accuracy']:.4f} | {m['precision']:.4f} | {m['recall']:.4f} | {m['f1']:.4f} |\n\n"
            f"| true \\ pred | genuine | scam |\n|---|---|---|\n"
            f"| genuine | {cm[0][0]} | {cm[0][1]} |\n| scam | {cm[1][0]} | {cm[1][1]} |\n\n")


def main():
    train = pd.read_csv(os.path.join(DATA, "train.csv"), encoding="utf-8")
    test = pd.read_csv(os.path.join(DATA, "test.csv"), encoding="utf-8")
    train["group"] = np.arange(len(train))

    # augment train only: 1 variant per non-UCI row and per UCI scam row
    aug_src = train[(train.source != "uci") | (train.label == "scam")]
    aug = aug_src.copy()
    aug["text"] = [augment_one(t, l) for t, l in zip(aug_src.text, aug_src.lang)]
    aug["source"] = aug_src.source + "_aug"
    extra = load_extra(test)
    extra["group"] = np.arange(len(train), len(train) + len(extra))
    full = pd.concat([train, aug, extra], ignore_index=True)
    full["key"] = full.text.map(norm_key)
    test_keys = set(test.text.map(norm_key))
    full = full[(full.key != "") & (~full.key.isin(test_keys))].drop_duplicates("key")
    assert not (set(full.key) & test_keys), "test leakage"

    cv = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)
    grid = GridSearchCV(make_pipeline(), {"lr__C": [0.3, 1, 3, 10, 30, 100]}, cv=cv,
                        scoring=make_scorer(f1_score, pos_label="scam"), n_jobs=-1)
    grid.fit(full.text, full.label, groups=full.group)
    best_C = grid.best_params_["lr__C"]
    model = make_pipeline(best_C).fit(full.text, full.label)

    pred = model.predict(test.text)
    test["pred"] = pred
    out = ["# Scam classifier results\n",
           "Before extra_train.csv: full test acc 0.9838 / F1 0.9671 (C=100); hand-written acc 0.8971 / "
           "F1 0.8955 (EN 0.8333, HI 0.9545, Hinglish 0.9091).\n\n",
           f"Extra hand-written train rows added (no augmentation): {len(extra)}.\n",
           f"TF-IDF (1,2)-grams, min_df=2, l2 + LogisticRegression(class_weight='balanced'), "
           f"C={best_C} (5-fold StratifiedGroupKFold CV on train, scam-F1 {grid.best_score_:.4f}).\n",
           f"Train rows after augmentation: {len(full)} (pre-aug {len(train)}); "
           f"vocabulary: {len(model.named_steps['tfidf'].vocabulary_)}.\n",
           "Positive class = scam. Test set = 20% stratified hold-out (split before augmentation) "
           "+ hand-written messages.\n\n",
           "CV scam-F1 by C: " + ", ".join(f"C={p['lr__C']}: {s:.4f}" for p, s in
                                          zip(grid.cv_results_["params"], grid.cv_results_["mean_test_score"]))
           + "\n\n## Full test.csv\n\n",
           md_block("All", metrics(test.label, test.pred))]
    names = {"en": "English", "hi": "Hindi (Devanagari)", "hinglish": "Hinglish"}
    for lang in ["en", "hi", "hinglish"]:
        s = test[test.lang == lang]
        out.append(md_block(names[lang], metrics(s.label, s.pred)))
    hw = test[test.source == "handwritten"]
    out.append("## Hand-written subset only (most realistic; templated test rows share templates with train)\n\n")
    out.append(md_block("Hand-written, all", metrics(hw.label, hw.pred)))
    for lang in ["en", "hi", "hinglish"]:
        s = hw[hw.lang == lang]
        out.append(md_block(f"Hand-written, {names[lang]}", metrics(s.label, s.pred)))
    wrong = hw[hw.label != hw.pred]
    if len(wrong):
        out.append("### Hand-written errors\n\n| label | pred | text |\n|---|---|---|\n")
        out += [f"| {r.label} | {r.pred} | {r.text.replace('|', '/')} |\n" for r in wrong.itertuples()]
    # Keep the clean held-out section (scored by test/engine/heldout_eval_test.dart on the shipped Dart model).
    # After retraining, that test fails until the section is updated with the new, honest numbers.
    results_path = os.path.join(HERE, "results.md")
    if os.path.exists(results_path):
        with open(results_path, encoding="utf-8") as f:
            old = f.read()
        i = old.find("## Held-out 2026")
        if i >= 0:
            out.append("\n" + old[i:])
    with open(results_path, "w", encoding="utf-8") as f:
        f.write("".join(out))

    os.makedirs(ART, exist_ok=True)
    joblib.dump(model, os.path.join(ART, "model.joblib"))
    export_model.export(model, test)
    m = metrics(test.label, test.pred)
    mh = metrics(hw.label, hw.pred)
    print(f"C={best_C} test acc={m['accuracy']:.4f} f1={m['f1']:.4f} | handwritten acc={mh['accuracy']:.4f} "
          f"f1={mh['f1']:.4f}")


if __name__ == "__main__":
    main()
