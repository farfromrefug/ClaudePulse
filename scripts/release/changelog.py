#!/usr/bin/env python3
"""Builds a release's notes from the commits and pull requests behind it.

Conventional commit subjects decide the section a change lands in; a squashed
or merged pull request keeps its number so the notes link back to the
discussion. Housekeeping that says nothing to a user — the release commits
themselves, version bumps, generated project churn — is left out.

Usage:
    changelog.py [--range v0.2.7..HEAD] [--format markdown|html]
"""

import argparse
import re
import subprocess
import sys

SECTIONS = [
    ("feat", "Features"),
    ("fix", "Fixes"),
    ("perf", "Performance"),
    ("refactor", "Under the hood"),
    ("docs", "Documentation"),
    ("build", "Build"),
    ("ci", "Build"),
    ("test", "Tests"),
]
OTHER = "Other changes"

# `release:` and `chore(release):` are this script's own footprints.
SKIP_TYPES = {"release"}
SKIP_SUBJECTS = re.compile(r"^(chore\(release\)|release):|^Merge branch ", re.IGNORECASE)

CONVENTIONAL = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?(?P<breaking>!)?:\s*(?P<summary>.+)$")
PR_SUFFIX = re.compile(r"\s*\(#(?P<number>\d+)\)\s*$")
# A trailer on a line of its own. Prose that merely names it — a commit
# explaining what the marker does, say — is not a breaking change.
BREAKING_TRAILER = re.compile(r"^BREAKING[ -]CHANGE:", re.MULTILINE)


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def commits(rev_range: str) -> list[tuple[str, str]]:
    """(subject, body) for every commit in the range, newest first.

    Merge commits are skipped: a merge brings its branch's own commits along
    with it, so counting the merge as well says everything twice. A squashed
    pull request is not a merge commit — it keeps its `(#123)` suffix and is
    read like any other commit.
    """
    raw = git("log", "--no-merges", "--pretty=format:%H%x1f%s%x1f%b%x1e", rev_range)
    entries = []
    for record in raw.split("\x1e"):
        record = record.strip("\n")
        if not record:
            continue
        _, subject, body = record.split("\x1f", 2)
        entries.append((subject, body))
    return entries


def classify(subject: str) -> tuple[str, str, int | None, bool]:
    """(section, summary, pull request number, breaking) for one subject."""
    number = None
    pr = PR_SUFFIX.search(subject)
    if pr:
        number = int(pr.group("number"))
        subject = subject[: pr.start()].strip()

    match = CONVENTIONAL.match(subject)
    if not match:
        return OTHER, subject, number, False

    kind = match.group("type")
    summary = match.group("summary").strip()
    scope = match.group("scope")
    if scope:
        summary = f"**{scope}**: {summary}"
    breaking = bool(match.group("breaking"))
    section = dict(SECTIONS).get(kind, OTHER)
    if kind in SKIP_TYPES:
        section = ""
    return section, summary, number, breaking


def build(rev_range: str) -> tuple[dict[str, list[str]], list[str]]:
    grouped: dict[str, list[str]] = {}
    breaking: list[str] = []
    seen: set[str] = set()

    for subject, body in commits(rev_range):
        if SKIP_SUBJECTS.match(subject):
            continue
        section, summary, number, marked = classify(subject)
        if not section or not summary:
            continue
        # A squash and its branch commits say the same thing twice.
        key = summary.lower()
        if key in seen:
            continue
        seen.add(key)

        entry = summary[0].upper() + summary[1:]
        if number:
            entry += f" (#{number})"
        grouped.setdefault(section, []).append(entry)
        if marked or BREAKING_TRAILER.search(body):
            breaking.append(entry)

    return grouped, breaking


def ordered(grouped: dict[str, list[str]]) -> list[tuple[str, list[str]]]:
    order = [title for _, title in SECTIONS]
    order.append(OTHER)
    seen = []
    for title in order:
        if title in grouped and title not in [t for t, _ in seen]:
            seen.append((title, grouped[title]))
    return seen


def as_markdown(grouped: dict[str, list[str]], breaking: list[str]) -> str:
    lines: list[str] = []
    if breaking:
        lines.append("### Breaking changes")
        lines += [f"- {entry}" for entry in breaking]
        lines.append("")
    for title, entries in ordered(grouped):
        lines.append(f"### {title}")
        lines += [f"- {entry}" for entry in entries]
        lines.append("")
    return "\n".join(lines).strip() or "- Maintenance release"


def escape(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def as_html(grouped: dict[str, list[str]], breaking: list[str]) -> str:
    """The appcast's description body, in the shape Sparkle renders."""
    lines: list[str] = []
    if breaking:
        lines.append("<p><strong>Breaking changes</strong></p>")
        lines.append("<ul>")
        lines += [f"    <li>{escape(entry)}</li>" for entry in breaking]
        lines.append("</ul>")
    for title, entries in ordered(grouped):
        lines.append(f"<p><strong>{escape(title)}</strong></p>")
        lines.append("<ul>")
        lines += [f"    <li>{escape(entry)}</li>" for entry in entries]
        lines.append("</ul>")
    if not lines:
        lines = ["<ul>", "    <li>Maintenance release</li>", "</ul>"]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--range", dest="rev_range", default="HEAD")
    parser.add_argument("--format", choices=["markdown", "html"], default="markdown")
    args = parser.parse_args()

    grouped, breaking = build(args.rev_range)
    print(as_markdown(grouped, breaking) if args.format == "markdown" else as_html(grouped, breaking))
    return 0


if __name__ == "__main__":
    sys.exit(main())
