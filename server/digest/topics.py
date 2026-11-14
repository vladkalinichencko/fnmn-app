"""Scores every collected post against the keyword topics from the app's digest settings.

The scorer is a multilingual embedding model when `sentence-transformers` and the model are
on the Mac, then a zero-shot NLI model when `transformers` and its model are, and a
token-overlap scorer when neither is, so a build never dies for want of a model. Tests
inject their own scorer; the live ones are never loaded there.
"""

from __future__ import annotations

import re
from typing import Callable

from digest import settings as digest_settings
from digest.store import Post

EMBED_MODEL = "Qwen/Qwen3-Embedding-0.6B"
EMBED_QUERY = "Instruct: Classify the topic of this social media post.\nQuery: "
EMBED_PASSAGE = "passage: "
MODEL = "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7"
Scorer = Callable[[str, list[str]], dict[str, float]]

_WORDS = re.compile(r"\w+", re.UNICODE)


def classify(threads: list[list[Post]], settings: dict, scorer: Scorer | None = None) -> dict[str, float]:
    """Writes each post's topic folders and returns its best score, keyed by post id.

    A thread is scored once on its joined texts and every member keeps the verdict, so a
    story never splits across topics. A post keeps its single best topic when that score
    cleared the threshold; below it the folders stay empty and the magazine files the post
    under `Other`. With no topics configured at all the folders are left as the collector
    wrote them and every score is 0.
    """
    if not digest_settings.any_topics(settings):
        return {}
    score_of = scorer or default_scorer()
    best: dict[str, float] = {}
    for thread in threads:
        first = thread[0]
        topics = digest_settings.topics(settings, first.network, first.source)
        threshold = digest_settings.threshold(settings, first.network, first.source)
        text = "\n\n".join((post.text or "").strip() for post in thread if (post.text or "").strip())
        if not topics or not text:
            for post in thread:
                best[post.id] = 0.0
            continue
        scores = score_of(text, topics)
        top = max(topics, key=lambda topic: scores.get(topic, 0.0))
        ranked = sorted((scores.get(topic, 0.0) for topic in topics), reverse=True)
        best_score = ranked[0] - (sum(ranked[1:]) / len(ranked[1:]) if len(ranked) > 1 else 0.0)
        for post in thread:
            post.folders = [top] if best_score >= threshold else []
            best[post.id] = best_score
    return best


def cap(threads: list[list[Post]], scores: dict[str, float], limit: int) -> tuple[list[Post], dict[str, str]]:
    """The delivery's post budget: the strongest threads by their best topic score, newest
    first on a tie. A thread is kept or dropped whole; the rest is consumed but not shipped."""
    if sum(len(thread) for thread in threads) <= limit:
        return [post for thread in threads for post in thread], {}
    ranked = sorted(
        threads,
        key=lambda thread: (
            max(scores.get(post.id, 0.0) for post in thread),
            max(post.posted_at for post in thread),
        ),
        reverse=True,
    )
    kept: set[str] = set()
    over: dict[str, str] = {}
    count = 0
    for thread in ranked:
        if count + len(thread) <= limit:
            kept.update(post.id for post in thread)
            count += len(thread)
        else:
            over.update({post.id: "over the digest limit" for post in thread})
    return [post for thread in threads for post in thread if post.id in kept], over


def default_scorer() -> Scorer:
    for scorer in (Embedder, ZeroShot):
        try:
            return scorer()
        except Exception:
            continue
    return lexical


class Embedder:
    """Qwen3-Embedding: the post and each topic become vectors, and the score of a topic is
    the cosine between them.

    Topic vectors are encoded once per topic set and reused, so a build pays one encoding
    per post. `classify` reads the lead of the best topic over the mean of the rest as
    the confidence, so the threshold does not drift with the number of configured topics.
    The query carries an instruction and each topic a `passage:` prefix, the pair the
    model was evaluated with.
    """

    def __init__(self, model: str = EMBED_MODEL, encoder=None):
        if encoder is None:
            from sentence_transformers import SentenceTransformer

            encoder = SentenceTransformer(model)
        import numpy as np

        self._np = np
        self._encoder = encoder
        self._passages: dict[tuple[str, ...], object] = {}

    def __call__(self, text: str, topics: list[str]) -> dict[str, float]:
        key = tuple(topics)
        if key not in self._passages:
            self._passages[key] = self._np.asarray(
                self._encoder.encode([f"{EMBED_PASSAGE}{topic}" for topic in topics], normalize_embeddings=True)
            )
        vector = self._np.asarray(self._encoder.encode(f"{EMBED_QUERY}{text}", normalize_embeddings=True))
        sims = self._passages[key] @ vector
        return {topic: float(sim) for topic, sim in zip(topics, sims)}


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
