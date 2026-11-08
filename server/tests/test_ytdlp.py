import unittest

from collect import ytdlp


class CommandTests(unittest.TestCase):
    def test_a_flat_listing_reads_json_lines_with_the_cookies(self):
        args = ytdlp.command("https://x", cookies_from_browser="chrome", cookies_file="c.txt")
        self.assertEqual(args[0], "yt-dlp")
        self.assertIn("--flat-playlist", args)
        self.assertIn("--dump-json", args)
        self.assertLess(args.index("--cookies-from-browser"), args.index("https://x"))
        self.assertLess(args.index("--cookies"), args.index("https://x"))

    def test_a_single_page_keeps_its_entries(self):
        args = ytdlp.command("https://x", dump="--dump-single-json", flat=False)
        self.assertNotIn("--flat-playlist", args)
        self.assertIn("--dump-single-json", args)

    def test_a_print_template_comes_before_the_address(self):
        args = ytdlp.command("https://x", dump="--print", flat=False, extra=["%(id)s"])
        self.assertEqual(args[-1], "https://x")
        self.assertEqual(args[-2], "%(id)s")


class ParsingTests(unittest.TestCase):
    def test_entries_keep_only_json_objects(self):
        text = '{"id": "a"}\nnot json\n[1, 2]\n{"id": "b"}\n'
        self.assertEqual(ytdlp.parse_entries(text), [{"id": "a"}, {"id": "b"}])

    def test_last_line_skips_blank_lines(self):
        self.assertEqual(ytdlp.last_line("one\n\ntwo\n"), "two")
        self.assertEqual(ytdlp.last_line(""), "")
