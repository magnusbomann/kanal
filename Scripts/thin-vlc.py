"""Removes architectures no supported device can run."""
import pathlib, plistlib, subprocess, sys

KEEP_DEVICE = {"arm64"}
KEEP_SIM = {"arm64", "x86_64"}

for name in sys.argv[1:]:
    root = pathlib.Path(f"Vendor/{name}.xcframework")
    plist_path = root / "Info.plist"
    data = plistlib.loads(plist_path.read_bytes())

    for library in data.get("AvailableLibraries", []):
        identifier = library["LibraryIdentifier"]
        binary = root / identifier / library["LibraryPath"] / name
        if not binary.is_file():
            continue
        have = set(subprocess.run(["lipo", "-archs", str(binary)],
                                  capture_output=True, text=True).stdout.split())
        keep = sorted(have & (KEEP_SIM if "simulator" in identifier else KEEP_DEVICE))
        if not keep or set(keep) == have:
            continue

        args = ["lipo", str(binary)]
        for arch in keep:
            args += ["-extract", arch]
        args += ["-output", str(binary) + ".thin"]
        if subprocess.run(args, capture_output=True).returncode != 0:
            print(f"  {identifier}: lipo failed, left as is")
            continue
        pathlib.Path(str(binary) + ".thin").replace(binary)
        library["SupportedArchitectures"] = keep
        print(f"  {identifier}: {sorted(have)} -> {keep}")

    plist_path.write_bytes(plistlib.dumps(data))
    size = subprocess.run(["du", "-sm", str(root)], capture_output=True, text=True).stdout.split()[0]
    print(f"{name}: {size} MB\n")
