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
        self.assertEqual(prefs["limit"], 100)
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
            topics.classify([scored], settings.load(Path(folder)), self.scorer)
            self.assertEqual(scored.folders, ["llms"])

    def test_a_post_below_the_threshold_lands_in_other(self):
        prefs = self.prefs(networks={"x": {"topics": ["cooking"]}})
        scored = post("x/1", text="A post about llms")
        topics.classify([scored], prefs, self.scorer)
        self.assertEqual(scored.folders, [])

    def test_without_topics_the_folders_stay_as_collected(self):
        scored = post("x/1", folders=("ml",))
        topics.classify([scored], {"threshold": 0.5}, self.scorer)
        self.assertEqual(scored.folders, ["ml"])

    def test_the_cap_keeps_the_strongest_posts_and_names_the_rest(self):
        posts = [post(f"x/{index}") for index in range(5)]
        scores = {"x/0": 0.1, "x/1": 0.9, "x/2": 0.5, "x/3": 0.7, "x/4": 0.2}
        kept, dropped = topics.cap(posts, scores, 2)
        self.assertEqual([item.id for item in kept], ["x/1", "x/3"])
        self.assertEqual(set(dropped), {"x/0", "x/2", "x/4"})

    def test_the_cap_under_the_limit_drops_nothing(self):
        posts = [post("x/1")]
        kept, dropped = topics.cap(posts, {}, 100)
        self.assertEqual(kept, posts)
        self.assertEqual(dropped, {})


if __name__ == "__main__":
    unittest.main()
