#!/usr/bin/env python3
"""Prepare CyberChef's index.html for the hardened container.

Adds the runtime theme/branding hooks, resolves the release ZIP checksum,
replaces the favicon and moves the inline loader SVG into a same-origin file
so the Content-Security-Policy can keep object-src at 'self'.
"""

from __future__ import annotations

import base64
import re
import sys
from pathlib import Path

OBJECT_RE = re.compile(
    r'<object\b'
    r'((?:"[^"]*"|\'[^\']*\'|[^>])*?)'
    r'\bdata="data:image/svg\+xml;base64,([^"]+)"'
    r'((?:"[^"]*"|\'[^\']*\'|[^>])*)>'
    r'</object>',
    re.IGNORECASE | re.DOTALL,
)


def require(condition: bool, message: str) -> None:
    if not condition:
        print(f"prepare-index: {message}", file=sys.stderr)
        raise SystemExit(1)


def main() -> int:
    if len(sys.argv) != 3:
        print(
            f"usage: {Path(sys.argv[0]).name} INDEX_HTML ZIP_SHA256",
            file=sys.stderr,
        )
        return 2

    path = Path(sys.argv[1])
    zip_sha256 = sys.argv[2]
    require(re.fullmatch(r"[0-9a-f]{64}", zip_sha256) is not None, "invalid ZIP SHA-256")
    html = path.read_text(encoding="utf-8")

    require("DOWNLOAD_HASH_PLACEHOLDER" in html, "download hash placeholder not found")
    html = html.replace("DOWNLOAD_HASH_PLACEHOLDER", zip_sha256, 1)

    marker = "<script type=application/javascript>"
    require(html.count(marker) == 1, "unexpected inline bootstrap script layout")
    html = html.replace(
        marker,
        '<script src="config.js"></script>' + marker,
        1,
    )

    css = "<link href=assets/main.css rel=stylesheet>"
    require(html.count(css) == 1, "main stylesheet link not found")
    html = html.replace(
        css,
        css + "<link href=brand.css rel=stylesheet>",
        1,
    )

    favicon = (
        "<link rel=icon type=image/ico "
        "href=assets/aecc661b69309290f600.ico>"
    )
    require(html.count(favicon) == 1, "favicon link not found")
    html = html.replace(
        favicon,
        '<link rel=icon href=favicon.svg>',
        1,
    )

    match = OBJECT_RE.search(html)
    require(match is not None, "loader SVG object not found")
    svg = base64.b64decode(match.group(2), validate=True)
    require(b"<svg" in svg[:500], "loader is not an SVG")
    images = path.parent / "images"
    images.mkdir(exist_ok=True)
    (images / "bombe.svg").write_bytes(svg)
    # Use an <img> rather than an <object> so frame-src can stay 'none'.
    replacement = f'<img{match.group(1)}src="images/bombe.svg"{match.group(3)}>'
    html = html[: match.start()] + replacement + html[match.end():]

    path.write_text(html, encoding="utf-8")
    print(f"prepared {path}; extracted images/bombe.svg ({len(svg)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
