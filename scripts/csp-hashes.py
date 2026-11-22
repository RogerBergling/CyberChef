#!/usr/bin/env python3
"""Print a Content-Security-Policy script-src value for CyberChef's index.html.

The CyberChef page contains three inline bootstrap scripts. A hash-based CSP
allows those exact scripts without enabling 'unsafe-inline' for scripts.
Re-run this after updating the CyberChef release.
"""

from __future__ import annotations

import base64
import hashlib
import re
import sys
from pathlib import Path

SCRIPT_RE = re.compile(
    r"<script(?![^>]*\bsrc\s*=)[^>]*>(.*?)</script>",
    re.IGNORECASE | re.DOTALL,
)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} INDEX_HTML", file=sys.stderr)
        return 2

    html = Path(sys.argv[1]).read_text(encoding="utf-8")
    hashes = []
    for script in SCRIPT_RE.findall(html):
        digest = hashlib.sha256(script.encode("utf-8")).digest()
        hashes.append("'sha256-" + base64.b64encode(digest).decode("ascii") + "'")

    if not hashes:
        print("no inline scripts found", file=sys.stderr)
        return 1

    # CyberChef uses a small WebAssembly module for 64-bit arithmetic.
    # 'wasm-unsafe-eval' permits WASM compilation but not JavaScript eval.
    print("'self' 'wasm-unsafe-eval' " + " ".join(hashes))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
