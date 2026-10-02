import unittest

from adapters.html_markdown import article_markdown


PAGE = "https://example.com/post/"
SAMPLE = """
<html><body>
<article>
  <h1>Momentum</h1>
  <p>A <strong>ball</strong> on a <a href="https://example.com/hill">hill</a>.</p>
  <p>See <img alt="slope" src="assets/slope.gif">.</p>
  <video src="assets/roll.mp4"></video>
  <p>Inline <script type="math/tex">x^2</script> and a line.</p>
  <script type="math/tex; mode=display">E = mc^2</script>
  <script src="assets/page.js"></script>
  <figure>
    <canvas></canvas>
    <script>draw()</script>
  </figure>
  <figure id="mount"><div id="plot"></div></figure>
  <iframe src="https://videos.example/embed/1"></iframe>
  <ul><li>First</li><li>Second</li></ul>
</article>
</body></html>
"""


LOOSE_TEXT = """
<html><body>
<div class="article-body">
  LSTM was proposed by <a href="https://example.com/juergen">Jürgen Schmidhuber</a> and colleagues.
  <h3>Forget gates</h3>
  The gate reads the state <em>C<sub>t-1</sub></em> and decides what to keep,
  so the cell forgets <em>f<sub>t</sub></em> of it.
  <ul><li>First</li></ul>
  After the list the text goes on, long enough to count as the article's prose.
</div>
</body></html>
"""


class HtmlMarkdownTests(unittest.TestCase):
    def test_text_directly_in_a_container_reads_as_paragraphs_between_its_blocks(self):
        markdown, _ = article_markdown(LOOSE_TEXT, PAGE)
        self.assertEqual(
            markdown.split("\n\n"),
            [
                "LSTM was proposed by [Jürgen Schmidhuber](https://example.com/juergen) and colleagues.",
                "### Forget gates",
                "The gate reads the state *Ct-1* and decides what to keep,\n  so the cell forgets *ft* of it.",
                "- First",
                "After the list the text goes on, long enough to count as the article's prose.",
            ],
        )

    def test_spaces_at_the_edges_of_bold_stay_outside_its_marks(self):
        page = "<html><body><article><p><b>Eyes: </b>green, <b>and </b>a long enough sentence of the article prose.</p></article></body></html>"
        markdown, _ = article_markdown(page, PAGE)
        self.assertIn("**Eyes:** green, **and** a long", markdown)

    def test_spaces_at_the_edges_of_spans_and_links_stay_between_words(self):
        page = (
            '<html><body><article><p><span>The contest </span><a href="https://example.com/aimo"><span>AIMO</span></a>'
            "<span>, with a prize of </span><b><strong>1 million dollars</strong></b><span>. "
            '</span><a href="https://example.com/paper"><span>DeepSeekMath </span></a><span>– a long enough sentence of the article prose.</span></p>'
            "</article></body></html>"
        )
        markdown, _ = article_markdown(page, PAGE)
        self.assertEqual(
            markdown,
            "The contest [AIMO](https://example.com/aimo), with a prize of **1 million dollars**. "
            "[DeepSeekMath](https://example.com/paper) – a long enough sentence of the article prose.",
        )

    def test_text_stays_markdown_and_figures_point_at_the_live_page(self):
        markdown, downloads = article_markdown(SAMPLE, PAGE)
        self.assertIn("# Momentum", markdown)
        self.assertIn("**ball**", markdown)
        self.assertIn("[hill](https://example.com/hill)", markdown)
        self.assertIn("$x^2$", markdown)
        self.assertIn("$$\nE = mc^2\n$$", markdown)
        self.assertIn("- First", markdown)
        self.assertNotIn("draw()", markdown)
        self.assertNotIn("page.js", markdown)
        self.assertIn("```fnmn-interactive\nhttps://example.com/post/\nbody:nth-of-type(1) > article:nth-of-type(1) > figure:nth-of-type(1)\n```", markdown)
        self.assertIn("```fnmn-interactive\nhttps://example.com/post/\n#mount\n```", markdown)
        self.assertIn("```fnmn-interactive\nhttps://videos.example/embed/1\n```", markdown)
        self.assertTrue(any(url.endswith("slope.gif") for url in downloads.values()))
        self.assertTrue(any(url.endswith("roll.mp4") for url in downloads.values()))
        self.assertFalse(any(url.endswith("page.js") for url in downloads.values()))
        self.assertIn("```fnmn-video\n", markdown)

    def test_a_widget_with_states_in_templates_is_live_and_its_states_are_not_text(self):
        source = """
        <html><body><article>
          <p>Before the examples, a sentence long enough to be prose.</p>
          <div id="swap">
            <button>Echo</button><button>Astra</button>
            <div class="templates"><template><p>Reply from Echo.</p></template><template><p>Reply from Astra.</p></template></div>
          </div>
          <p>After the examples, another sentence long enough to be prose.</p>
        </article></body></html>
        """
        markdown, _ = article_markdown(source, PAGE)
        self.assertIn("```fnmn-interactive\nhttps://example.com/post/\n#swap\n```", markdown)
        self.assertNotIn("Reply from", markdown)
        self.assertNotIn("Echo", markdown)
        self.assertIn("Before the examples", markdown)
        self.assertIn("After the examples", markdown)

    def test_a_captioned_figure_is_live_and_a_picture_figure_stays_a_file(self):
        source = """
        <html><body><article>
          <figure id="plot"><figcaption>A curve.</figcaption></figure>
          <figure><img alt="slope" src="pic.png"><figcaption>Slope.</figcaption></figure>
        </article></body></html>
        """
        markdown, downloads = article_markdown(source, PAGE)
        self.assertIn("```fnmn-interactive\nhttps://example.com/post/\n#plot\n```", markdown)
        self.assertNotIn("A curve.", markdown)
        self.assertTrue(any(url.endswith("pic.png") for url in downloads.values()))
        self.assertIn("![slope](", markdown)
        self.assertEqual(markdown.count("```fnmn-interactive"), 1)

    def test_a_cover_figure_whose_picture_was_dropped_is_not_a_live_figure(self):
        source = """
        <html><head><title>Transformers and what comes after them</title></head><body><main>
          <figure class="relative"><img alt="" src="/_next/image?url=cover.png">
            <figcaption><h1>Transformers and what comes after them</h1><p>05.11.2024</p></figcaption></figure>
          <p>Transformers are the gold standard of neural networks today, and of large language models above all.</p>
          <p>They were the first architecture that scales: more data and parameters give a better model every time.</p>
        </main></body></html>
        """
        markdown, _ = article_markdown(source, PAGE)
        self.assertNotIn("fnmn-interactive", markdown)
        self.assertIn("gold standard", markdown)

    def test_article_wins_by_score_and_formula_comes_from_the_annotation(self):
        source = """
        <html><body>
          <div class="sidebar"><p>Related, related, related, related, related notes and more related notes.</p></div>
          <div class="content">
            <h1>Notes</h1>
            <p>We begin with gradient descent, the long way around, and then another clause, so this block is the article.</p>
            <p>Inline <span class="katex"><span class="katex-mathml"><math><semantics><mi>x</mi><annotation encoding="application/x-tex">x^2</annotation></semantics></math></span><span class="katex-html">x²</span></span> here.</p>
            <span class="katex-display"><span class="katex"><span class="katex-mathml"><math display="block"><semantics><mi>E</mi><annotation encoding="application/x-tex">E = mc^2</annotation></semantics></math></span><span class="katex-html">E</span></span></span>
            <widget-math><span class="katex"><span class="katex-mathml"><math><semantics><mi>a</mi><annotation encoding="application/x-tex">a+b</annotation></semantics></math></span><span class="katex-html">ab</span></span></widget-math>
          </div>
        </body></html>
        """
        markdown, _downloads = article_markdown(source, PAGE)
        self.assertIn("# Notes", markdown)
        self.assertIn("gradient descent", markdown)
        self.assertNotIn("Related, related", markdown)
        self.assertIn("$x^2$", markdown)
        self.assertNotIn("x²", markdown)
        self.assertIn("$$\nE = mc^2\n$$", markdown)
        self.assertIn("$a+b$", markdown)
        self.assertNotIn("ab", markdown)


if __name__ == "__main__":
    unittest.main()
