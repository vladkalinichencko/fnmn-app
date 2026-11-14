import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from digest import settings, topics
from tests.fakes import post


class SettingsTests(unittest.TestCase):
    def test_a_missing_file_reads_as_the_defaults(self):
        with TemporaryDirectory() as folder:
            prefs = settings.load(Path(folder))
        self.assertTrue(prefs["enabled"])
        self.assertEqual(prefs["hours"], [8, 20])
        self.assertEqual(prefs["threshold"], 0.5)
        self.assertEqual(prefs["limit"], 40)
        self.assertFalse(settings.any_topics(prefs))

    def test_topics_join_the_network_words_and_the_source_words(self):
        prefs = {
            "networks": {"x": {"topics": ["llms", "agents"]}},
            "sources": {"x/karpathy": {"topics": ["llms", "own notes"]}},
        }
        self.assertEqual(settings.topics(prefs, "x", "x/karpathy"), ["llms", "agents", "own notes"])
        self.assertEqual(settings.topics(prefs, "telegram", "telegram/durov"), [])
        self.assertTrue(settings.any_topics(prefs))

    def test_recommendations_only_for_the_networks_that_have_a_feed(self):
        prefs = {"networks": {"x": {"recommendations": True}, "telegram": {"recommendations": True}}}
        self.assertTrue(settings.recommendations(prefs, "x"))
        self.assertFalse(settings.recommendations(prefs, "telegram"))


class ClassifyTests(unittest.TestCase):
    def prefs(self, **overrides):
        prefs = {"threshold": 0.5, "networks": {"x": {"topics": ["llms", "cooking"]}}, "sources": {}}
        prefs.update(overrides)
        return prefs

    def scorer(self, text, words):
        return {word: 0.9 if word == "llms" else 0.1 for word in words}

    def test_a_post_keeps_the_topics_over_the_threshold(self):
        with TemporaryDirectory() as folder:
            Path(folder, "digest-settings.json").write_text(json.dumps(self.prefs()))
            scored = post("x/1", text="A post about llms")
            topics.classify([[scored]], settings.load(Path(folder)), self.scorer)
            self.assertEqual(scored.folders, ["llms"])

    def test_a_post_keeps_only_its_best_topic_over_the_threshold(self):
        def two_scores(text, words):
            return {"llms": 0.9, "cooking": 0.3}

        scored = post("x/1", text="A post about llms")
        topics.classify([[scored]], self.prefs(), two_scores)
        self.assertEqual(scored.folders, ["llms"])

    def test_topics_too_close_to_call_land_in_other(self):
        def tied_scores(text, words):
            return {"llms": 0.9, "cooking": 0.85}

        scored = post("x/1", text="A post about llms")
        topics.classify([[scored]], self.prefs(), tied_scores)
        self.assertEqual(scored.folders, [])

    def test_a_post_below_the_threshold_lands_in_other(self):
        prefs = self.prefs(networks={"x": {"topics": ["cooking"]}})
        scored = post("x/1", text="A post about llms")
        topics.classify([[scored]], prefs, self.scorer)
        self.assertEqual(scored.folders, [])

    def test_without_topics_the_folders_stay_as_collected(self):
        scored = post("x/1", folders=("ml",))
        topics.classify([[scored]], {"threshold": 0.5}, self.scorer)
        self.assertEqual(scored.folders, ["ml"])

    def test_the_cap_keeps_the_strongest_posts_and_names_the_rest(self):
        posts = [post(f"x/{index}") for index in range(5)]
        scores = {"x/0": 0.1, "x/1": 0.9, "x/2": 0.5, "x/3": 0.7, "x/4": 0.2}
        kept, dropped = topics.cap([[item] for item in posts], scores, 2)
        self.assertEqual([item.id for item in kept], ["x/1", "x/3"])
        self.assertEqual(set(dropped), {"x/0", "x/2", "x/4"})

    def test_the_cap_under_the_limit_drops_nothing(self):
        posts = [post("x/1")]
        kept, dropped = topics.cap([[item] for item in posts], {}, 100)
        self.assertEqual(kept, posts)
        self.assertEqual(dropped, {})

    def test_a_thread_is_scored_once_and_every_member_keeps_the_verdict(self):
        texts = []

        def recording(text, words):
            texts.append(text)
            return self.scorer(text, words)

        first = post("x/1", text="first part")
        second = post("x/2", text="second part")
        topics.classify([[first, second]], self.prefs(), recording)
        self.assertEqual(len(texts), 1)
        self.assertIn("first part", texts[0])
        self.assertIn("second part", texts[0])
        self.assertEqual(first.folders, ["llms"])
        self.assertEqual(second.folders, ["llms"])

    def test_the_cap_never_splits_a_thread(self):
        story = [post(f"x/{index}") for index in range(3)]
        solo = [post("x/9")]
        scores = {"x/0": 0.9, "x/1": 0.9, "x/2": 0.9, "x/9": 0.1}
        kept, dropped = topics.cap([story, solo], scores, 3)
        self.assertEqual([item.id for item in kept], ["x/0", "x/1", "x/2"])
        self.assertEqual(dropped, {"x/9": "over the digest limit"})


class EmbedderTests(unittest.TestCase):
    class Encoder:
        def __init__(self):
            self.calls = []

        def encode(self, texts, normalize_embeddings=True):
            self.calls.append(texts)
            vectors = {
                topics.EMBED_QUERY + "about llms": [1.0, 0.0],
                topics.EMBED_PASSAGE + "llms": [1.0, 0.0],
                topics.EMBED_PASSAGE + "cooking": [0.0, 1.0],
            }
            if isinstance(texts, str):
                return vectors.get(texts, [0.5, 0.5])
            return [vectors.get(text, [0.5, 0.5]) for text in texts]

    def test_the_score_is_the_cosine_against_each_topic(self):
        encoder = self.Encoder()
        scores = topics.Embedder(encoder=encoder)("about llms", ["llms", "cooking"])
        self.assertAlmostEqual(scores["llms"], 1.0, places=4)
        self.assertAlmostEqual(scores["cooking"], 0.0, places=4)

    def test_the_topic_vectors_encode_once_per_topic_set(self):
        encoder = self.Encoder()
        embedder = topics.Embedder(encoder=encoder)
        embedder("about llms", ["llms", "cooking"])
        embedder("more llms", ["llms", "cooking"])
        embedder("supper", ["cooking"])
        passage_calls = [call for call in encoder.calls if isinstance(call, list)]
        self.assertEqual(len(passage_calls), 2)
        self.assertEqual(passage_calls[0], ["passage: llms", "passage: cooking"])
        self.assertEqual(passage_calls[1], ["passage: cooking"])


if __name__ == "__main__":
    unittest.main()
