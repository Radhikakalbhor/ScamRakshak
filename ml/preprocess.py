"""Shared preprocessing. Must stay byte-for-byte reproducible in Dart (see scam_model.json 'preprocessing')."""
import re

URL_PATTERN = (
    r"(?:https?://|www\.)[^\s]+"
    r"|(?<![a-z0-9.-])[a-z0-9-]+(?:\.[a-z0-9-]+)*\."
    r"(?:com|in|ly|xyz|top|link|info|net|org|co|me|site|online|app|club|live|cc|io|gl)"
    r"(?![a-z0-9])(?:/[^\s]*)?"
)
URL_REPLACEMENT = " urltoken "
TOKEN_PATTERN = r"[a-z0-9ऀ-ॿ]+"

_URL_RE = re.compile(URL_PATTERN)
_TOKEN_RE = re.compile(TOKEN_PATTERN)


def preprocess(text: str) -> str:
    """lowercase -> URLs to ' urltoken '. Tokenization is done by TOKEN_PATTERN."""
    return _URL_RE.sub(URL_REPLACEMENT, str(text).lower())


def tokenize(text: str):
    return _TOKEN_RE.findall(preprocess(text))


def norm_key(text: str) -> str:
    """Key used for de-duplication / leakage checks."""
    return " ".join(tokenize(text))
