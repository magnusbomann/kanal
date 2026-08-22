#!/usr/bin/env python3
"""Compiles the string catalogs into .lproj resources.

SwiftPM copies a `.xcstrings` file verbatim — only Xcode's build system
compiles one. Relying on that would mean strings resolve in the shipping app
but not under `swift test`, so the catalogs stay the editable source of truth
and this produces the `.strings` and `.stringsdict` that both build systems
understand.

  python3 Scripts/build-localizations.py
"""
from __future__ import annotations

import json
import pathlib
import plistlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOGS = [
    (ROOT / "Localizations/KanalCore.xcstrings", ROOT / "Packages/KanalKit/Sources/KanalCore/Resources"),
    (ROOT / "Localizations/KanalUI.xcstrings", ROOT / "Packages/KanalKit/Sources/KanalUI/Resources"),
]

PLURAL_CATEGORIES = ["zero", "one", "two", "few", "many", "other"]


def escape(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )


def value_type(key: str) -> str:
    """The printf specifier a plural key counts on."""
    return "lld" if "%lld" in key else "@"


def build(catalog_path: pathlib.Path, output_root: pathlib.Path) -> list[str]:
    data = json.loads(catalog_path.read_text())
    strings = data["strings"]

    languages: set[str] = set()
    for entry in strings.values():
        languages.update(entry.get("localizations", {}).keys())

    written = []
    for language in sorted(languages):
        simple: dict[str, str] = {}
        plurals: dict[str, dict] = {}

        for key, entry in strings.items():
            localization = entry.get("localizations", {}).get(language)
            if localization is None:
                continue

            if "stringUnit" in localization:
                simple[key] = localization["stringUnit"]["value"]
            elif "variations" in localization:
                categories = localization["variations"]["plural"]
                plurals[key] = {
                    "NSStringLocalizedFormatKey": "%#@value@",
                    "value": {
                        "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                        "NSStringFormatValueTypeKey": value_type(key),
                        **{
                            name: categories[name]["stringUnit"]["value"]
                            for name in PLURAL_CATEGORIES
                            if name in categories
                        },
                    },
                }

        lproj = output_root / f"{language}.lproj"
        lproj.mkdir(parents=True, exist_ok=True)

        header = f"// Generated from {catalog_path.name}. Do not edit.\n\n"
        body = "".join(
            f'"{escape(key)}" = "{escape(value)}";\n' for key, value in sorted(simple.items())
        )
        (lproj / "Localizable.strings").write_text(header + body, encoding="utf-8")
        written.append(f"{language}: {len(simple)} strings")

        stringsdict = lproj / "Localizable.stringsdict"
        if plurals:
            stringsdict.write_bytes(plistlib.dumps(plurals))
            written[-1] += f", {len(plurals)} plurals"
        elif stringsdict.exists():
            stringsdict.unlink()

    return written


def copy_title_packs(languages: set[str]) -> list[str]:
    """Ships a title pack for every language the interface speaks — and only those.

    German alone is over 3 MB. Bundling every pack we have built would cost
    every user megabytes for languages whose interface is not even translated,
    so a pack ships when its language does. Anyone on another language still
    gets translated search; it just comes from the live provider instead.
    """
    source = ROOT / "Localizations/titles"
    destination = ROOT / "Packages/KanalKit/Sources/KanalCore/Resources/titles"
    destination.mkdir(parents=True, exist_ok=True)
    if not source.exists():
        return []

    # English needs no pack: it is the language the packs translate *into*.
    wanted = {language for language in languages if language != "en"}

    for stale in destination.glob("*.json"):
        if stale.stem not in wanted:
            stale.unlink()

    copied = []
    for language in sorted(wanted):
        pack = source / f"{language}.json"
        if not pack.exists():
            copied.append(f"{language} (no pack built yet)")
            continue
        target = destination / pack.name
        target.write_bytes(pack.read_bytes())
        copied.append(f"{language} ({target.stat().st_size // 1024} KB)")
    return copied


def main() -> int:
    languages: set[str] = set()
    for catalog_path, _ in CATALOGS:
        data = json.loads(catalog_path.read_text())
        for entry in data.get("strings", {}).values():
            languages.update(entry.get("localizations", {}).keys())

    for catalog_path, output_root in CATALOGS:
        if not catalog_path.exists():
            print(f"missing catalog: {catalog_path}", file=sys.stderr)
            return 1
        results = build(catalog_path, output_root)
        print(f"{catalog_path.stem}: " + "; ".join(results))

    packs = copy_title_packs(languages)
    if packs:
        print("title packs: " + ", ".join(packs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
