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


def main() -> int:
    for catalog_path, output_root in CATALOGS:
        if not catalog_path.exists():
            print(f"missing catalog: {catalog_path}", file=sys.stderr)
            return 1
        results = build(catalog_path, output_root)
        print(f"{catalog_path.stem}: " + "; ".join(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
