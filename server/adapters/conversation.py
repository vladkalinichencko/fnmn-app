"""A shared chat as the reader's document: the prompt is a quoted plate, the answer plain paragraphs."""

_PROMPT = {"user", "human"}


def turn(role: str, body: str) -> str:
    if role not in _PROMPT:
        return body
    return "\n".join("> " + line if line.strip() else ">" for line in body.split("\n"))
