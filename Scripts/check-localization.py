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
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Packages/KanalKit/Sources"
LANGUAGE_CONFIG = ROOT / "Localizations/languages.json"

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
# A negative look-behind matters: `%%lld` is a literal percent followed by
# text, not a valid `%lld` argument. It used to fool the simpler check.
PRINTF_ARGUMENT = re.compile(r"(?<!%)%(?:lld|@|%)")


def supported_languages() -> list[str]:
    data = json.loads(LANGUAGE_CONFIG.read_text())
    return [language["code"] for language in data["languages"]]


def declared_keys(strings_file: pathlib.Path) -> set[str]:
    """Keys named in LocalizedStringResource(...) calls in a Strings.swift."""
    source = strings_file.read_text()
    keys: set[str] = set()

    # Map each interpolated parameter to its printf specifier by reading the
    # declared Swift type. Guessing from the parameter's *name* was wrong the
    # first time a String argument was called something other than "name".
    types: dict[str, str] = {}
    for match in re.finditer(r"\b_?\s*(\w+):\s*(String|Int)\b", source):
        types[match.group(1)] = "%@" if match.group(2) == "String" else "%lld"

    # Two shapes: the `resource("key", "comment")` helper and full calls.
    for match in re.finditer(r'(?:resource|text)\(\s*"([^"]+)"', source):
        keys.add(match.group(1))
    for match in re.finditer(r'LocalizedStringResource\(\s*"([^"]+)"', source):
        raw = match.group(1)
        # `"count.channels \(count)"` extracts as `count.channels %lld`.
        def specifier(hit: re.Match[str]) -> str:
            return types.get(hit.group(1), "%lld")
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
    """Also covers the app targets — a literal there would ship untranslated
    just as readily as one in the package, and used to escape this check."""
    problems = []
    roots = [SOURCES, ROOT / "App"]
    files = sorted(f for root in roots if root.exists() for f in root.rglob("*.swift"))
    for path in files:
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
    languages = supported_languages()

    problems = []
    for plist in [ROOT / "App/iOS/Info.plist", ROOT / "App/tvOS/Info.plist"]:
        text = plist.read_text()
        missing = [
            language for language in languages
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


def info_plist_translations() -> list[str]:
    """Privacy permission prompts are user-facing too.

    They live in the application bundle rather than KanalUI, so the string
    catalogs cannot cover them. Each platform keeps an InfoPlist.strings in
    every supported language instead.
    """
    problems = []
    for platform in ("iOS", "tvOS"):
        plist_path = ROOT / f"App/{platform}/Info.plist"
        with plist_path.open("rb") as file:
            plist = plistlib.load(file)
        # Any future microphone, Bluetooth or photo permission prompt becomes
        # part of the contract automatically; no hard-coded list can forget it.
        keys = {"CFBundleDisplayName"}
        keys.update(key for key in plist if key.endswith("UsageDescription"))
        for language in supported_languages():
            path = ROOT / f"App/{platform}/Resources/{language}.lproj/InfoPlist.strings"
            if not path.exists():
                problems.append(
                    f"App/{platform}: {language}.lproj/InfoPlist.strings is missing"
                )
                continue
            text = path.read_text(encoding="utf-8")
            for key in sorted(keys):
                if f'"{key}"' not in text:
                    problems.append(f"{path.relative_to(ROOT)}: '{key}' is missing")
    return problems


def package_declares_languages() -> list[str]:
    """A generated `.lproj` is useless unless SwiftPM copies it twice.

    KanalCore and KanalUI are separate resource bundles, so each supported
    language must appear in both target resource declarations.
    """
    package = (ROOT / "Packages/KanalKit/Package.swift").read_text()
    problems = []
    for language in supported_languages():
        declaration = f'.copy("Resources/{language}.lproj")'
        if package.count(declaration) != 2:
            problems.append(
                f"Package.swift: {language}.lproj must be copied by KanalCore and KanalUI"
            )
    return problems


def main() -> int:
    failures: list[str] = []
    expected = set(supported_languages())

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
        if all_languages != expected:
            missing = expected - all_languages
            unexpected = all_languages - expected
            if missing:
                failures.append(f"{name}: catalog is missing language(s) {', '.join(sorted(missing))}")
            if unexpected:
                failures.append(f"{name}: catalog has unsupported language(s) {', '.join(sorted(unexpected))}")
        for key in sorted(present):
            missing = expected - languages[key]
            if missing:
                failures.append(f"{name}: '{key}' is not translated into {', '.join(sorted(missing))}")

        data = json.loads(catalog_file.read_text())
        for key, entry in data.get("strings", {}).items():
            source = entry.get("localizations", {}).get("en", {})
            source_values = localization_values(source)
            for language in sorted(expected):
                localized = entry.get("localizations", {}).get(language, {})
                localized_values = localization_values(localized)
                if not localized_values or not source_values:
                    continue
                # Plural languages may carry more grammatical forms, so compare
                # per form only when their form counts match. Every generated
                # form still has to preserve the key's format arguments.
                required_arguments = sorted(
                    token for token in PRINTF_ARGUMENT.findall(key) if token != "%%"
                )
                source_literal_percents = max(
                    (PRINTF_ARGUMENT.findall(value).count("%%") for value in source_values),
                    default=0,
                )
                if any(
                    sorted(token for token in PRINTF_ARGUMENT.findall(value) if token != "%%")
                    != required_arguments
                    or (
                        PRINTF_ARGUMENT.findall(value).count("%%")
                        + value.count("٪")
                    ) != source_literal_percents
                    for value in localized_values
                ):
                    failures.append(
                        f"{name}: '{key}' has a damaged format placeholder in {language}"
                    )

        # The catalog is the source; the .lproj files are what actually ship.
        # Drift between them would translate in Xcode and not under SwiftPM.
        for language in supported_languages():
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
    failures.extend(info_plist_translations())
    failures.extend(package_declares_languages())

    if failures:
        print(f"Localization check failed — {len(failures)} problem(s):\n")
        for failure in failures:
            print(f"  {failure}")
        return 1

    total = sum(len(catalog_keys(catalog)[0]) for _, _, catalog, _ in MODULES)
    print(f"Localization check passed — {total} keys, every one declared and translated.")
    return 0


def localization_values(localization: dict) -> list[str]:
    if "stringUnit" in localization:
        return [localization["stringUnit"].get("value", "")]
    plural = localization.get("variations", {}).get("plural", {})
    return [unit.get("stringUnit", {}).get("value", "") for unit in plural.values()]


if __name__ == "__main__":
    sys.exit(main())
