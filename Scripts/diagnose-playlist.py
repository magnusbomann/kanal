#!/usr/bin/env python3
"""Reports what a provider actually serves, and what Apple can play.

Run it on your own playlist without sharing the link with anyone:

    python3 Scripts/diagnose-playlist.py "<your m3u url>"

It prints how the entries break down by container, probes a few real VOD
URLs for their content type, and says plainly which of them AVPlayer can
open. Credentials are masked in everything it prints.
"""
from __future__ import annotations

import collections
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

UA = {"User-Agent": "Kanal/1.0 (AppleCoreMedia)"}

# What AVFoundation can actually decode on iOS and tvOS.
NATIVE = {"m3u8", "mp4", "m4v", "mov", "ts"}
# Common in IPTV catalogues, and unplayable without a third-party engine.
FOREIGN = {"mkv", "avi", "wmv", "flv", "webm", "mpg", "mpeg", "divx", "rmvb", "ogv"}


def mask(url: str) -> str:
    """Hides anything that identifies the subscription.

    Credentials appear in the path on some panels and in the query on others,
    and the hostname alone is enough to identify a provider — so all three go.
    """
    url = re.sub(r"(://)[^/:]+", r"\1<provider>", url)
    url = re.sub(r"(/(?:movie|series|live|vod)/)[^/]+/[^/]+/", r"\1***/***/", url)
    return re.sub(r"([?&](?:username|password|token)=)[^&]*", r"\1***", url)


def fetch(url: str) -> str:
    request = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read()
    for encoding in ("utf-8", "iso-8859-1"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def probe(url: str) -> str:
    """A ranged GET, because many panels reject HEAD outright."""
    request = urllib.request.Request(url, headers={**UA, "Range": "bytes=0-1023"})
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            kind = response.headers.get("Content-Type", "?")
            length = response.headers.get("Content-Length", "?")
            return f"{response.status} {kind} ({length} bytes in range)"
    except urllib.error.HTTPError as error:
        return f"{error.code} {error.reason}"
    except Exception as error:  # noqa: BLE001
        return f"failed: {type(error).__name__}"


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2

    text = fetch(sys.argv[1])
    entries: list[tuple[str, str]] = []
    title = ""
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("#EXTINF"):
            title = line.split(",", 1)[-1]
        elif line and not line.startswith("#"):
            entries.append((title, line))
            title = ""

    def container(url: str) -> str:
        path = urllib.parse.urlparse(url).path
        return (path.rsplit(".", 1)[-1].lower() if "." in path.rsplit("/", 1)[-1] else "(none)")

    def section(url: str) -> str:
        path = urllib.parse.urlparse(url).path
        for name in ("movie", "series", "live", "vod"):
            if f"/{name}/" in path:
                return name
        return "?"

    print(f"\n{len(entries)} entries\n")

    print("By URL section and container:")
    grid: dict[tuple[str, str], int] = collections.Counter()
    for _, url in entries:
        grid[(section(url), container(url))] += 1
    for (sec, ext), count in sorted(grid.items(), key=lambda item: -item[1]):
        if ext in NATIVE:
            verdict = "Apple plays this"
        elif ext in FOREIGN:
            verdict = "AVPlayer CANNOT play this"
        else:
            verdict = "unknown — probe below"
        print(f"  {sec:8s} .{ext:6s} {count:6d}   {verdict}")

    # Probe one real URL per non-live container.
    print("\nProbing one URL per VOD container:")
    seen: set[str] = set()
    for name, url in entries:
        ext = container(url)
        if section(url) == "live" or ext in seen:
            continue
        seen.add(ext)
        print(f"  .{ext:6s} {name[:38]:40s} {probe(url)}")
        print(f"          {mask(url)}")
        if len(seen) >= 5:
            break

    playable = sum(c for (sec, ext), c in grid.items() if ext in NATIVE)
    foreign = sum(c for (sec, ext), c in grid.items() if ext in FOREIGN)
    print(f"\nPlayable by AVPlayer: {playable}    needs another engine: {foreign}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
