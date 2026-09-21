import unittest

from html_markdown import article_markdown


SAMPLE = """
<html><body>
<article>
  <h1>Momentum</h1>
  <p>A <strong>ball</strong> on a <a href="https://example.com/hill">hill</a>.</p>
  <p>See <img alt="slope" src="assets/slope.gif">.</p>
  <video src="assets/roll.mp4"></video>
  <p>Inline <script type="math/tex">x^2</script> and a line.</p>
  <script type="math/tex; mode=display">E = mc^2</script>
  <figure>
    <canvas></canvas>
    <script>draw()</script>
  </figure>
  <ul><li>First</li><li>Second</li></ul>
</article>
</body></html>
"""


class HtmlMarkdownTests(unittest.TestCase):
    def test_text_becomes_markdown_and_the_figure_becomes_one_island(self):
        markdown, islands = article_markdown(SAMPLE)
        self.assertIn("# Momentum", markdown)
        self.assertIn("**ball**", markdown)
        self.assertIn("[hill](https://example.com/hill)", markdown)
        self.assertIn("![slope](assets/slope.gif)", markdown)
        self.assertIn("```fnmn-video\nassets/roll.mp4\n```", markdown)
        self.assertIn("$x^2$", markdown)
        self.assertIn("$$\nE = mc^2\n$$", markdown)
        self.assertIn("```fnmn-interactive\ninteractive/1.html\n```", markdown)
        self.assertIn("- First", markdown)
        self.assertNotIn("draw()", markdown)
        fragment = islands["interactive/1.html"]
        self.assertIn("<canvas", fragment)
        self.assertIn("fnmn-height", fragment)
        self.assertEqual(len(islands), 1)


if __name__ == "__main__":
    unittest.main()
