#!/usr/bin/env bash
# Every relative markdown link [text](path) must resolve to an existing file or directory.
# Skips http(s) and mailto.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

ROOT="$ROOT" python3 - <<'PY'
import re, os, sys
from pathlib import Path

root = Path(os.environ["ROOT"])
dead = []
checked = 0

# Strip inline-code spans and fenced code blocks before scanning so example link syntax
# in docs (e.g. ` [text](path) `) is not treated as a real link.
fence_re = re.compile(r'^```.*?^```', re.MULTILINE | re.DOTALL)
inline_re = re.compile(r'`[^`\n]*`')

for md in root.rglob('*.md'):
    if '.git' in md.parts: continue
    if 'tests/_out' in str(md): continue
    text = md.read_text()
    text = fence_re.sub('', text)
    text = inline_re.sub('', text)
    for m in re.finditer(r'(?<!\\!)\[([^\]]+)\]\(([^)\s]+)\)', text):
        url = m.group(2).split('#')[0].strip()
        if url.startswith(('http://', 'https://', 'mailto:')) or url == '':
            continue
        checked += 1
        target = (md.parent / url).resolve()
        if not target.exists():
            dead.append(f"{md.relative_to(root)}: link target missing: {url}")

if dead:
    print("FAIL: dead markdown links:")
    for d in dead:
        print(f"  {d}")
    sys.exit(1)

print(f"PASS: {checked} relative markdown links resolve")
PY
