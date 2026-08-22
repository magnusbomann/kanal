#!/usr/bin/env python3
"""Builds offline title packs from Wikidata.

The insight that makes this small: **only titles that differ from English are
worth storing.** "Ratatouille" and "Django Unchained" are spelled the same in
every language, and Kanal's local index already finds those. The only pairs
that need shipping are the ones where the viewer's name for a film is not the
name their provider used — "Løvenes konge" → "The Lion King".

That turns an unbounded translation problem into a small, static file per
language, which means the common case is answered instantly, offline, with no
API, no key and no rate limit. Live Wikidata stays as the long-tail fallback.

Run at build time, not on device:

    python3 Scripts/build-title-packs.py nb de sv

Wikidata's query service is a shared, free resource — this pages politely and
backs off rather than hammering it.
"""
from __future__ import annotations

import csv
import io
import json
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Localizations/titles"
ENDPOINT = "https://query.wikidata.org/sparql"
USER_AGENT = "Kanal/1.0 (https://github.com/magnusbomann/kanal; title-pack build)"

# Queried one type at a time, unsorted. `ORDER BY` with LIMIT/OFFSET makes the
# query service sort the whole result set on every page, which reliably earns a
# 504 — one cheap streaming query per type is what it is happy to serve.
TYPES = [
    ("Q11424", "film"),
    ("Q202866", "animated film"),
    ("Q5398426", "television series"),
    ("Q506240", "television film"),
    ("Q1259759", "miniseries"),
    ("Q29168811", "animated feature film"),
]

QUERY = """
SELECT ?loc ?en WHERE {{
  ?item wdt:P31 wd:{type} .
  ?item rdfs:label ?locL . FILTER(LANG(?locL) = "{lang}")
  ?item rdfs:label ?enL .  FILTER(LANG(?enL) = "en")
  BIND(STR(?locL) AS ?loc)
  BIND(STR(?enL) AS ?en)
  FILTER(?loc != ?en)
}}
"""


def fetch(query: str, attempt_budget: int = 6) -> str:
    url = ENDPOINT + "?" + urllib.parse.urlencode({"query": query})
    request = urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, "Accept": "text/csv"}
    )
    delay = 5.0
    for attempt in range(attempt_budget):
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                return response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504):
                raise
            retry_after = error.headers.get("Retry-After")
            wait = float(retry_after) if retry_after and retry_after.isdigit() else delay
            print(f"    rate limited ({error.code}), waiting {wait:.0f}s", flush=True)
            time.sleep(wait)
            delay = min(delay * 2, 120)
        except Exception as error:  # noqa: BLE001 — transport variety
            print(f"    {type(error).__name__}, retrying in {delay:.0f}s", flush=True)
            time.sleep(delay)
            delay = min(delay * 2, 120)
    raise RuntimeError("gave up after repeated failures")


def build(language: str) -> pathlib.Path:
    pairs: dict[str, str] = {}

    for entity, label in TYPES:
        body = fetch(QUERY.format(type=entity, lang=language))
        rows = list(csv.DictReader(io.StringIO(body)))

        added = 0
        for row in rows:
            localized = (row.get("loc") or "").strip()
            english = (row.get("en") or "").strip()
            if not localized or not english or localized == english:
                continue
            if pairs.setdefault(localized, english) == english:
                added += 1

        print(f"    {label}: {len(rows)} rows, +{added} pairs", flush=True)
        # Deliberate breathing room for a free, shared service.
        time.sleep(3.0)

    OUTPUT.mkdir(parents=True, exist_ok=True)
    path = OUTPUT / f"{language}.json"
    path.write_text(json.dumps(pairs, ensure_ascii=False, sort_keys=True), encoding="utf-8")
    return path


def main() -> int:
    languages = sys.argv[1:] or ["nb"]
    for language in languages:
        print(f"{language}:", flush=True)
        started = time.time()
        path = build(language)
        size = path.stat().st_size / 1024
        count = len(json.loads(path.read_text()))
        print(
            f"  {count} pairs, {size:.0f} KB, {time.time() - started:.0f}s -> "
            f"{path.relative_to(ROOT)}",
            flush=True,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
