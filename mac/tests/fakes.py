from web import Web


def web(text=lambda url: "", bytes=lambda url: b"", rendered=None) -> Web:
    """A Web made of plain functions; Chrome refuses unless a test supplies it."""
    def no_browser(url):
        raise OSError("no browser in tests")

    return Web(text=text, bytes=bytes, page=text, rendered=rendered or no_browser)
