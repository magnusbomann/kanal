#!/usr/bin/env python3
"""Fails if any user-facing string could escape translation.

Discipline does not scale to sixty files. This is the check that makes
"did we miss anything?" answerable by a machine:

  1. Every key declared in a Strings.swift exists in its string catalog.
  2. Every catalog key is actually declared — no orphans sent to translators.
  3. Every catalog entry is translated into every language the catalog carries.
  4. No user-facing string literal is written directly in a view.

Run from anywhere:  python3 Scripts/check-localization.py
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Packages/KanalKit/Sources"

MODULES = [
    ("KanalCore", SOURCES / "KanalCore/Strings.swift",
     ROOT / "Localizations/KanalCore.xcstrings", SOURCES / "KanalCore/Resources"),
    ("KanalUI", SOURCES / "KanalUI/Strings.swift",
     ROOT / "Localizations/KanalUI.xcstrings", SOURCES / "KanalUI/Resources"),
]

# SwiftUI initialisers that localise their argument. A literal in any of these
# is a string that will ship untranslated.
LITERAL_PATTERN = re.compile(
    r'(?<![\w.])(?:Text|Button|Label|Section|Toggle|Picker|TextField|SecureField|'
    r'navigationTitle|accessibilityLabel|LabeledContent)\(\s*"([^"]{2,})"'
)

# Interpolations become printf specifiers in the extracted key.
INTERPOLATION = re.compile(r"\\\((.*?)\)")


def declared_keys(strings_file: pathlib.Path) -> set[str]:
    """Keys named in LocalizedStringResource(...) calls in a Strings.swift."""
    source = strings_file.read_text()
    keys: set[str] = set()

    # Two shapes: the `resource("key", "comment")` helper and full calls.
    for match in re.finditer(r'(?:resource|text)\(\s*"([^"]+)"', source):
        keys.add(match.group(1))
    for match in re.finditer(r'LocalizedStringResource\(\s*"([^"]+)"', source):
        raw = match.group(1)
        # `"count.channels \(count)"` extracts as `count.channels %lld`.
        def specifier(hit: re.Match[str]) -> str:
            name = hit.group(1)
            return "%@" if name.endswith(("name", "host", "title", "relative", "date")) else "%lld"
        keys.add(INTERPOLATION.sub(specifier, raw))
    return keys


def catalog_keys(catalog_file: pathlib.Path) -> tuple[set[str], dict[str, set[str]]]:
    data = json.loads(catalog_file.read_text())
    strings = data.get("strings", {})
    languages: dict[str, set[str]] = {}
    for key, entry in strings.items():
        languages[key] = set(entry.get("localizations", {}).keys())
    return set(strings), languages


def stray_literals() -> list[str]:
    problems = []
    for path in sorted(SOURCES.rglob("*.swift")):
        if path.name == "Strings.swift":
            continue
        for number, line in enumerate(path.read_text().splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            for match in LITERAL_PATTERN.finditer(line):
                problems.append(
                    f"{path.relative_to(ROOT)}:{number}: literal "
                    f'"{match.group(1)[:48]}" — move it to Strings.swift'
                )
    return problems


def app_declares_languages() -> list[str]:
    """The app bundle must list every language its packages translate into.

    iOS resolves the app's language against `CFBundleLocalizations` in the main
    bundle. A package can carry perfect translations and still never be asked
    for them.
    """
    languages: set[str] = set()
    for _, _, catalog_file, _ in MODULES:
        _, per_key = catalog_keys(catalog_file)
        for entry in per_key.values():
            languages.update(entry)

    problems = []
    for plist in [ROOT / "App/iOS/Info.plist", ROOT / "App/tvOS/Info.plist"]:
        text = plist.read_text()
        missing = [
            language for language in sorted(languages)
            if f"<string>{language}</string>" not in text
        ]
        if "CFBundleLocalizations" not in text:
            problems.append(f"{plist.relative_to(ROOT)}: no CFBundleLocalizations key")
        elif missing:
            problems.append(
                f"{plist.relative_to(ROOT)}: CFBundleLocalizations is missing "
                f"{', '.join(missing)}"
            )
    return problems


def main() -> int:
    failures: list[str] = []

    for name, strings_file, catalog_file, resources in MODULES:
        if not catalog_file.exists():
            failures.append(f"{name}: no string catalog at {catalog_file.relative_to(ROOT)}")
            continue

        declared = declared_keys(strings_file)
        present, languages = catalog_keys(catalog_file)

        for key in sorted(declared - present):
            failures.append(f"{name}: '{key}' is declared in Swift but missing from the catalog")
        for key in sorted(present - declared):
            failures.append(f"{name}: '{key}' is in the catalog but nothing declares it")

        all_languages = set().union(*languages.values()) if languages else set()
        for key in sorted(present):
            missing = all_languages - languages[key]
            if missing:
                failures.append(f"{name}: '{key}' is not translated into {', '.join(sorted(missing))}")

        # The catalog is the source; the .lproj files are what actually ship.
        # Drift between them would translate in Xcode and not under SwiftPM.
        for language in sorted(all_languages):
            compiled = resources / f"{language}.lproj/Localizable.strings"
            if not compiled.exists():
                failures.append(
                    f"{name}: {language}.lproj is missing — run Scripts/build-localizations.py"
                )
                continue
            text = compiled.read_text(encoding="utf-8")
            for key in sorted(present):
                simple = "stringUnit" in json.loads(catalog_file.read_text())["strings"][key]["localizations"][language]
                if simple and f'"{key}"' not in text.replace("\\", ""):
                    failures.append(
                        f"{name}: '{key}' is missing from {language}.lproj — "
                        "run Scripts/build-localizations.py"
                    )

    failures.extend(stray_literals())
    failures.extend(app_declares_languages())

    if failures:
        print(f"Localization check failed — {len(failures)} problem(s):\n")
        for failure in failures:
            print(f"  {failure}")
        return 1

    total = sum(len(catalog_keys(catalog)[0]) for _, _, catalog, _ in MODULES)
    print(f"Localization check passed — {total} keys, every one declared and translated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
