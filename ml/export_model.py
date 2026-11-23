"""Exports the trained sklearn pipeline to assets/models/scam_model.json (+ parity_samples.json) for the Dart engine.
Standalone: python ml/export_model.py  (loads ml/artifacts/model.joblib and ml/data/test.csv)."""
import json
import math
import os
import re

import joblib
import pandas as pd

from preprocess import TOKEN_PATTERN, URL_PATTERN, URL_REPLACEMENT

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "models")


def reference_score(m, text):
    """Pure-python scorer that uses ONLY the exported JSON; this is what Dart must replicate."""
    p = m["preprocessing"]
    s = re.sub(p["url_regex"], p["url_replacement"], text.lower())
    toks = re.findall(p["token_regex"], s)
    grams = toks + [toks[i] + " " + toks[i + 1] for i in range(len(toks) - 1)]
    tf = {}
    for g in grams:
        j = m["vocab"].get(g)
        if j is not None:
            tf[j] = tf.get(j, 0) + 1
    w = {j: c * m["idf"][j] for j, c in tf.items()}
    nrm = math.sqrt(sum(v * v for v in w.values()))
    z = m["intercept"] + (sum(v * m["coef"][j] for j, v in w.items()) / nrm if nrm > 0 else 0.0)
    return 1.0 / (1.0 + math.exp(-z))


def export(model, test):
    vec, lr = model.named_steps["tfidf"], model.named_steps["lr"]
    classes = [str(c) for c in lr.classes_]
    assert classes == ["genuine", "scam"]
    vocab = {t: int(i) for t, i in sorted(vec.vocabulary_.items(), key=lambda kv: kv[1])}
    m = {
        "version": 1,
        "labels": {"0": "genuine", "1": "scam"},
        "positive_label": "scam",
        "preprocessing": {
            "steps": ["lowercase", "url_replace", "tokenize", "ngrams", "tf_raw_count", "times_idf", "l2_normalize",
                      "dot_coef_plus_intercept", "sigmoid"],
            "lowercase": True,
            "url_regex": URL_PATTERN,
            "url_replacement": URL_REPLACEMENT,
            "token_regex": TOKEN_PATTERN,
            "ngram_range": [1, 2],
            "ngram_joiner": " ",
            "sublinear_tf": False,
            "norm": "l2",
            "note": "score = sigmoid(intercept + sum_j x_j*coef_j), x = l2norm(count_j*idf_j) over in-vocab n-grams; "
                    "score is P(scam)",
        },
        "vocab": vocab,
        "idf": [round(float(x), 8) for x in vec.idf_],
        "coef": [round(float(x), 8) for x in lr.coef_[0]],
        "intercept": round(float(lr.intercept_[0]), 8),
    }
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "scam_model.json"), "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, separators=(",", ":"))

    # 50 parity samples: all-language / both-label mix, hand-written first
    t = test.copy()
    t["hw"] = (t.source == "handwritten").astype(int)
    picks = t.sort_values("hw", ascending=False, kind="stable").groupby(["lang", "label"]).head(8)
    picks = pd.concat([picks, t.drop(picks.index).sample(50 - len(picks), random_state=1)]).head(50)
    probs = model.predict_proba(picks.text)[:, 1]
    samples = [{"text": tx, "lang": lg, "label": lb, "scam_prob": round(float(p), 8)}
               for tx, lg, lb, p in zip(picks.text, picks.lang, picks.label, probs)]
    max_diff = max(abs(reference_score(m, s["text"]) - s["scam_prob"]) for s in samples)
    assert len(samples) == 50 and max_diff < 1e-6, f"parity failure n={len(samples)} diff={max_diff}"
    with open(os.path.join(OUT, "parity_samples.json"), "w", encoding="utf-8") as f:
        json.dump({"tolerance": 1e-4, "samples": samples}, f, ensure_ascii=False, indent=1)
    print(f"exported vocab={len(vocab)} parity_samples={len(samples)} max_diff={max_diff:.2e}")


if __name__ == "__main__":
    export(joblib.load(os.path.join(HERE, "artifacts", "model.joblib")),
           pd.read_csv(os.path.join(HERE, "data", "test.csv"), encoding="utf-8"))
