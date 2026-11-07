#!/usr/bin/env python3
"""The guards for a change, in one place. CI and the agent before a PR both run this file.

    python3 scripts/guards.py                 # diff checks, SwiftLint, lint self-test, swift test
    python3 scripts/guards.py --app           # also build the FNMN app for the iOS Simulator
    python3 scripts/guards.py --base origin/master

Diff checks read only the lines the change adds (against --base, committed or not), so code that was
already in the repository never fails them. Source-level rules live in .swiftlint.yml.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parent.parent
SCOPE = ["App", "Sources", "Tests", "AGENTS.md", ".swiftlint.yml", ".github"]
MAX_COMMENT_RUN = 4

CYRILLIC = re.compile(r"[\u0400-\u04FF]")
ONE_LINE_BLOCK = re.compile(
    r"^\s*(?:(?:public|private|fileprivate|internal|static|final|override|mutating|@ViewBuilder|@discardableResult)\s+)*"
    r"(?:func|var|if|else|guard|for|while|init)\b.*\{[^{}]*\}\s*$"
)
ELSE_ONE_LINE = re.compile(r"^\s*\}\s*else\b.*\{[^{}]*\}\s*$")
AMONG = re.compile(r"\bamong\s*:|\?\?\s*items\b")
# Generated trees that must never be tracked: the digest store's working files, browser profiles with the
# logged-in sessions, build products and Python caches.
RUNTIME_PATHS = ("/out/", "/profiles/", "/__pycache__/", "/.build/", "/.venv/")


def run(args, **kwargs):
    return subprocess.run(args, cwd=ROOT, text=True, capture_output=True, **kwargs)


def added_lines(base):
    """Yields (path, line number, text) for every line this change adds inside SCOPE."""
    diff = run(["git", "diff", "--unified=0", base, "--", *SCOPE])
    if diff.returncode != 0:
        sys.exit(f"git diff against {base} failed: {diff.stderr.strip()}")
    path, number = None, 0
    for line in diff.stdout.split("\n"):
        if line.startswith("+++ b/"):
            path = line[6:]
        elif line.startswith("@@"):
            number = int(re.search(r"\+(\d+)", line).group(1))
        elif line.startswith("+") and path:
            yield path, number, line[1:]
            number += 1
    untracked = run(["git", "ls-files", "--others", "--exclude-standard", "--", *SCOPE]).stdout.split()
    for path in untracked:
        for number, text in enumerate((ROOT / path).read_text().split("\n"), 1):
            yield path, number, text


def diff_violations(base):
    found = []
    comment_end = {}
    comment_length = {}
    for path, number, text in added_lines(base):
        is_swift = path.endswith(".swift")
        if CYRILLIC.search(text):
            found.append((path, number, "cyrillic", "Russian text in a change; the repository is written in English"))
        if is_swift and (ONE_LINE_BLOCK.match(text) or ELSE_ONE_LINE.match(text)):
            found.append((path, number, "one-line block", "block body on one line; put the statements on their own lines"))
        if is_swift and AMONG.search(text):
            found.append((path, number, "among parameter", "a second code path for a cached list; derive the cache once instead"))
        if text.strip().startswith("//"):
            length = comment_length.get(path, 0) + 1 if comment_end.get(path) == number - 1 else 1
            comment_end[path] = number
            comment_length[path] = length
            if length == MAX_COMMENT_RUN + 1:
                found.append((path, number, "comment block", f"more than {MAX_COMMENT_RUN} comment lines in a row"))
    return found


def python_shadowing(root=ROOT):
    """A module inside a server package whose name is also a module at the server root is reached by a bare
    `from <name> import` as the root one, so the package's own file can only be imported by its full name.
    That is how `digest/sources.py` silently read the article link classifier instead of its own contract."""
    server = root / "server"
    top_level = {path.name for path in server.glob("*.py") if path.name != "__init__.py"}
    problems = []
    for path in sorted(server.glob("*/**/*.py")):
        parts = path.relative_to(server).parts
        if parts[0] == "tests" or "__pycache__" in parts:
            continue
        if path.name in top_level:
            problems.append(f"{path.relative_to(root)} shares its name with server/{path.name}; a bare import reads the root one")
    return problems


def tracked_runtime_files(root=ROOT):
    """Generated files that git tracks: the working store, a logged-in browser profile, build products, caches.
    A profile in the repository would carry someone's sessions with it."""
    listed = subprocess.run(["git", "ls-files"], cwd=root, text=True, capture_output=True)
    if listed.returncode != 0:
        return []
    return [path for path in listed.stdout.splitlines() if any(part in f"/{path}" for part in RUNTIME_PATHS)]


def source_checks():
    problems = python_shadowing() + [f"{path} is tracked but generated" for path in tracked_runtime_files()]
    for problem in problems:
        print(problem)
    if problems:
        sys.exit(f"FAILED: {len(problems)} source problem(s)")


def source_self_test():
    """The same checks, on a tree grown to break them: a shadowed module name and a tracked working file."""
    with TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "server" / "digest").mkdir(parents=True)
        (root / "server" / "package.py").write_text("")
        (root / "server" / "digest" / "package.py").write_text("")
        if not python_shadowing(root):
            sys.exit("FAILED: the shadowing check missed a module named like a root module")
    with TemporaryDirectory() as folder:
        root = Path(folder)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        working = root / "server" / "digest" / "out" / "posts.jsonl"
        working.parent.mkdir(parents=True)
        working.write_text("")
        subprocess.run(["git", "add", "-f", str(working)], cwd=root, check=True)
        if not tracked_runtime_files(root):
            sys.exit("FAILED: the runtime check missed a tracked working file")


def step(title, args, cwd=ROOT):
    print(f"==> {title}", flush=True)
    result = subprocess.run(args, cwd=cwd)
    if result.returncode != 0:
        sys.exit(f"FAILED: {title}")


def server_python() -> str:
    """The repository's server environment when it is there; CI installs the same packages for python3."""
    venv = ROOT / ".venv/bin/python"
    return str(venv) if venv.exists() else sys.executable


def lint_self_test():
    probe = ROOT / "App/FNMN/GuardProbe.swift"
    probe.write_text(
        "struct GuardProbe {\n    let count = LibraryQueries(LibrarySnapshot()).items.count\n}\n"
    )
    try:
        result = run(["swiftlint", "lint", "--quiet", str(probe)])
    finally:
        probe.unlink()
    if "snapshot_catalog_selector_in_view" not in result.stdout + result.stderr:
        sys.exit("FAILED: the lint rule did not catch a LibraryQueries( in App/")


def simulator_udid():
    """The first available iPhone simulator, for the app unit tests."""
    result = run(["xcrun", "simctl", "list", "devices", "available", "--json"])
    if result.returncode != 0:
        sys.exit(f"xcrun simctl failed: {result.stderr.strip()}")
    devices = json.loads(result.stdout).get("devices", {})
    for runtime in sorted(devices, reverse=True):
        for device in devices[runtime]:
            if device.get("isAvailable") and device["name"].startswith("iPhone"):
                return device["udid"]
    sys.exit("no available iPhone simulator for the app unit tests")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="master")
    parser.add_argument("--app", action="store_true")
    options = parser.parse_args()

    if run(["git", "rev-parse", "--verify", "--quiet", options.base]).returncode != 0:
        sys.exit(f"base {options.base!r} does not exist; fetch it or pass --base")

    print(f"==> diff checks against {options.base}", flush=True)
    violations = diff_violations(options.base)
    for path, number, rule, message in violations:
        print(f"{path}:{number}: {rule}: {message}")
    if violations:
        sys.exit(f"FAILED: {len(violations)} diff violation(s)")

    print("==> source checks", flush=True)
    source_checks()
    source_self_test()
    print("==> lint self-test", flush=True)
    lint_self_test()
    step("swiftlint --strict", ["swiftlint", "--strict"])
    step("swift test", ["swift", "test"])
    step(
        "server tests",
        [server_python(), "-m", "unittest", "discover", "-s", "tests"],
        cwd=ROOT / "server",
    )
    if options.app:
        step(
            "build FNMN app",
            [
                "xcodebuild", "-project", "App/FNMN.xcodeproj", "-scheme", "FNMN",
                "-destination", "generic/platform=iOS Simulator", "-configuration", "Debug",
                "build", "CODE_SIGNING_ALLOWED=NO",
            ],
        )
        step(
            "test FNMN app",
            [
                "xcodebuild", "-project", "App/FNMN.xcodeproj", "-scheme", "FNMN",
                "-destination", f"id={simulator_udid()}", "-configuration", "Debug",
                "-only-testing:FNMNTests", "test", "CODE_SIGNING_ALLOWED=NO",
            ],
        )
    print("All guards passed.")


if __name__ == "__main__":
    main()
