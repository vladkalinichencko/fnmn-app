"""Scores every collected post against the keyword topics from the app's digest settings.

The scorer is a zero-shot NLI model when `transformers` and the model are on the Mac, and a
token-overlap scorer when they are not, so a build never dies for want of a model. Tests
inject their own scorer; the live one is never loaded there.
"""

from __future__ import annotations

import re
from typing import Callable

from digest import settings as digest_settings
from digest.store import Post

MODEL = "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7"
Scorer = Callable[[str, list[str]], dict[str, float]]

_WORDS = re.compile(r"\w+", re.UNICODE)


def classify(posts: list[Post], settings: dict, scorer: Scorer | None = None) -> dict[str, float]:
    """Writes each post's topic folders and returns its best score, keyed by post id.

    A post keeps the topics that cleared the threshold; below it the folders stay empty and
    the magazine files the post under `Other`. With no topics configured at all the folders
    are left as the collector wrote them and every score is 0.
    """
    if not digest_settings.any_topics(settings):
        return {}
    score_of = scorer or default_scorer()
    threshold = settings.get("threshold", digest_settings.DEFAULT_THRESHOLD)
    best: dict[str, float] = {}
    for post in posts:
        topics = digest_settings.topics(settings, post.network, post.source)
        text = (post.text or "").strip()
        if not topics or not text:
            best[post.id] = 0.0
            continue
        scores = score_of(text, topics)
        matched = [topic for topic in topics if scores.get(topic, 0.0) >= threshold]
        post.folders = matched
        best[post.id] = max((scores.get(topic, 0.0) for topic in topics), default=0.0)
    return best


def cap(posts: list[Post], scores: dict[str, float], limit: int) -> tuple[list[Post], dict[str, str]]:
    """The delivery's post budget: the strongest posts by their best topic score, newest first
    on a tie, the rest consumed but not shipped."""
    if len(posts) <= limit:
        return posts, {}
    ranked = sorted(posts, key=lambda post: (scores.get(post.id, 0.0), post.posted_at), reverse=True)
    kept = {post.id for post in ranked[:limit]}
    return [post for post in posts if post.id in kept], {
        post.id: "over the digest limit" for post in posts if post.id not in kept
    }


def default_scorer() -> Scorer:
    try:
        return ZeroShot()
    except Exception:
        return lexical


class ZeroShot:
    """mDeBERTa NLI: each topic becomes the hypothesis "This post is about {topic}"."""

    def __init__(self, model: str = MODEL):
        from transformers import pipeline

        self._pipe = pipeline("zero-shot-classification", model=model)

    def __call__(self, text: str, topics: list[str]) -> dict[str, float]:
        hypotheses = {f"This post is about {topic}": topic for topic in topics}
        result = self._pipe(text, list(hypotheses), multi_label=True)
        return {hypotheses[label]: score for label, score in zip(result["labels"], result["scores"])}


def lexical(text: str, topics: list[str]) -> dict[str, float]:
    """The fallback: the share of a topic's words the post contains."""
    words = set(_WORDS.findall(text.lower()))
    scores = {}
    for topic in topics:
        terms = set(_WORDS.findall(topic.lower()))
        scores[topic] = len(words & terms) / len(terms) if terms else 0.0
    return scores
