#!/usr/bin/env python3
"""Checks every App Store field in metadata.md against Apple's limits."""
import re, sys, pathlib
text = pathlib.Path(__file__).with_name("metadata.md").read_text()
LIMITS = {"Promotional text": 170, "Description": 4000, "Keywords": 100, "Notes": 4000}
ok = True
for section in re.split(r"\n## ", text):
    locale = section.splitlines()[0]
    for field, limit in LIMITS.items():
        m = re.search(rf"### {field}[^\n]*\n+```\n(.*?)\n```", section, re.S)
        if not m: continue
        n = len(m.group(1))
        flag = "OK " if n <= limit else "TOO LONG"
        ok &= n <= limit
        print(f"{flag} {locale[:24]:24} {field:17} {n:5}/{limit}")
for label, limit in (("Name", 30), ("Subtitle", 30)):
    for m in re.finditer(rf"\| {label} \((.*?)\) \| (.*?) \|", text):
        n = len(m.group(2)); ok &= n <= limit
        print(f"{'OK ' if n <= limit else 'TOO LONG'} {m.group(1):24} {label:17} {n:5}/{limit}")
sys.exit(0 if ok else 1)
