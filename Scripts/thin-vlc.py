#!/usr/bin/env python3
"""Trims the VLC XCFrameworks to what a shipping build actually needs.

Three things happen here, and the third one is the reason it is not simply
`rm -rf`:

  * Architectures no supported device can run are dropped. VideoLAN still
    ships armv7 and armv7s; nothing that can run Kanal can execute them.
  * Simulator debug symbols go. They are large and never appear in a crash
    report from a real device.
  * **Device debug symbols stay.** Removing them made every App Store upload
    warn "Upload Symbols Failed", and a warning that appears every single time
    is a warning nobody reads — which is how a real one gets missed. Keeping
    them also means a crash inside VLC arrives symbolicated.
"""
import pathlib
import plistlib
import shutil
import subprocess
import sys

KEEP_DEVICE = {"arm64"}
KEEP_SIM = {"arm64", "x86_64"}


def architectures(binary: pathlib.Path) -> set[str]:
    result = subprocess.run(["lipo", "-archs", str(binary)], capture_output=True, text=True)
    return set(result.stdout.split())


def thin(binary: pathlib.Path, keep: set[str]) -> list[str] | None:
    have = architectures(binary)
    wanted = sorted(have & keep)
    if not wanted or set(wanted) == have:
        return None

    arguments = ["lipo", str(binary)]
    for architecture in wanted:
        arguments += ["-extract", architecture]
    arguments += ["-output", f"{binary}.thin"]
    if subprocess.run(arguments, capture_output=True).returncode != 0:
        return None
    pathlib.Path(f"{binary}.thin").replace(binary)
    return wanted


def main() -> int:
    for name in sys.argv[1:]:
        root = pathlib.Path("Vendor") / f"{name}.xcframework"
        plist_path = root / "Info.plist"
        data = plistlib.loads(plist_path.read_bytes())

        for library in data.get("AvailableLibraries", []):
            identifier = library["LibraryIdentifier"]
            is_simulator = "simulator" in identifier
            keep = KEEP_SIM if is_simulator else KEEP_DEVICE

            binary = root / identifier / library["LibraryPath"] / name
            if binary.is_file():
                if kept := thin(binary, keep):
                    library["SupportedArchitectures"] = kept
                    print(f"  {identifier}: {', '.join(kept)}")
                subprocess.run(["strip", "-S", "-x", str(binary)], capture_output=True)

            symbols_path = library.get("DebugSymbolsPath")
            if not symbols_path:
                continue
            symbols = root / identifier / symbols_path

            if is_simulator:
                shutil.rmtree(symbols, ignore_errors=True)
                library.pop("DebugSymbolsPath", None)
                continue

            # Device symbols are kept, but only for architectures that ship.
            for dwarf in symbols.rglob("DWARF/*"):
                if dwarf.is_file():
                    thin(dwarf, keep)

        plist_path.write_bytes(plistlib.dumps(data))
        size = subprocess.run(["du", "-sm", str(root)], capture_output=True, text=True)
        print(f"{name}: {size.stdout.split()[0]} MB\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
