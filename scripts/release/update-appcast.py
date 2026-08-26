#!/usr/bin/env python3
"""Adds a release to appcast.xml, the feed Sparkle checks for updates.

The item is written by hand rather than through an XML library so the rest of
the file — every past release, its indentation and its signatures — is left
exactly as it was. Sparkle verifies the enclosure against `sparkle:edSignature`,
so an item is only worth adding once the signed archive exists.

Usage:
    update-appcast.py --version 0.3.0 --dmg build/ClaudePulse-0.3.0.dmg \\
        --url https://github.com/owner/repo/releases/download/v0.3.0/ClaudePulse-0.3.0.dmg \\
        --signature "$ED_SIGNATURE" --notes-file notes.html
"""

import argparse
import os
import re
import sys
from email.utils import format_datetime
from datetime import datetime, timezone

ITEM_TEMPLATE = """        <item>
            <title>Version {version}</title>
            <pubDate>{pub_date}</pubDate>
            <sparkle:version>{version}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{minimum_system}</sparkle:minimumSystemVersion>
            <description><![CDATA[
{notes}
            ]]></description>
            <enclosure
                url="{url}"
                length="{length}"
                type="application/octet-stream"
                sparkle:edSignature="{signature}"
            />
        </item>
"""


def indent(text: str, spaces: int = 16) -> str:
    pad = " " * spaces
    return "\n".join(pad + line if line.strip() else "" for line in text.splitlines())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", default="appcast.xml")
    parser.add_argument("--version", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--dmg", help="Archive the length is read from")
    parser.add_argument("--length", type=int, help="Archive size in bytes, when the file is not to hand")
    parser.add_argument("--notes-file", help="HTML release notes; a plain line is used otherwise")
    parser.add_argument("--minimum-system", default="14.0")
    args = parser.parse_args()

    length = args.length
    if length is None:
        if not args.dmg:
            parser.error("pass --dmg or --length")
        length = os.path.getsize(args.dmg)

    notes = "<ul>\n    <li>Maintenance release</li>\n</ul>"
    if args.notes_file:
        with open(args.notes_file, encoding="utf-8") as handle:
            notes = handle.read().strip() or notes

    with open(args.appcast, encoding="utf-8") as handle:
        feed = handle.read()

    if f"<sparkle:version>{args.version}</sparkle:version>" in feed:
        print(f"appcast.xml already has {args.version} — nothing to do.", file=sys.stderr)
        return 0

    item = ITEM_TEMPLATE.format(
        version=args.version,
        pub_date=format_datetime(datetime.now(timezone.utc)),
        minimum_system=args.minimum_system,
        notes=indent(notes),
        url=args.url,
        length=length,
        signature=args.signature,
    )

    # Newest first: in front of the item that is currently newest, or at the
    # end of an empty channel.
    match = re.search(r"[ \t]*<item>", feed)
    if match:
        feed = feed[: match.start()] + item + feed[match.start():]
    else:
        feed = feed.replace("    </channel>", item + "    </channel>", 1)

    with open(args.appcast, "w", encoding="utf-8") as handle:
        handle.write(feed)

    print(f"Added {args.version} to {args.appcast} ({length} bytes).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
