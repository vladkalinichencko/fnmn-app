from web import Web
from digest.store import Post


def web(text=lambda url: "", bytes=lambda url: b"", rendered=None) -> Web:
    """A Web made of plain functions; Chrome refuses unless a test supplies it."""
    def no_browser(url):
        raise OSError("no browser in tests")

    return Web(text=text, bytes=bytes, page=text, rendered=rendered or no_browser)


def post(post_id: str = "x/1", text: str | None = "A small model that reads the whole catalog.",
         folders: tuple[str, ...] = ("ml",)) -> Post:
    """A collected X post for the digest's build, refresh and store tests."""
    return Post(
        id=post_id,
        network="x",
        source="x/karpathy",
        author={"handle": "karpathy", "name": "Andrej Karpathy"},
        permalink=f"https://x.com/karpathy/status/{post_id.split('/')[-1]}",
        posted_at="2026-11-07T09:30:00Z",
        text=text,
        folders=list(folders),
    )
