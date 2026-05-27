#!/usr/bin/env bash
# Every anchor reference in SKILL.md (e.g. references/ownership.md#standard-detection) must
# correspond to a real heading in the target file. We slug headings the GitHub way:
#   lowercase, spaces -> '-', strip punctuation other than alphanumerics and '-'.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

ROOT="$ROOT" python3 - <<'PY'
import os, re, sys
from pathlib import Path

root = Path(os.environ["ROOT"])

def slugify(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r'[^\w\s-]', '', text, flags=re.UNICODE)
    text = re.sub(r'\s+', '-', text)
    return text

def headings(md_path: Path):
    out = set()
    in_code = False
    for line in md_path.read_text().splitlines():
        if line.strip().startswith('```'):
            in_code = not in_code
            continue
        if in_code:
            continue
        m = re.match(r'^(#{1,6})\s+(.+?)\s*#*\s*$', line)
        if m:
            out.add(slugify(m.group(2)))
    return out

cache = {}
def headings_for(p: Path):
    if p not in cache:
        cache[p] = headings(p)
    return cache[p]

dead = []
checked = 0

# Strip inline-code spans and fenced code blocks so example link syntax inside backticks
# is not treated as a real link.
fence_re = re.compile(r'^```.*?^```', re.MULTILINE | re.DOTALL)
inline_re = re.compile(r'`[^`\n]*`')

for md in root.rglob('*.md'):
    if '.git' in md.parts: continue
    if 'tests/_out' in str(md): continue
    text = md.read_text()
    text = fence_re.sub('', text)
    text = inline_re.sub('', text)
    for m in re.finditer(r'(?<!\\!)\[([^\]]+)\]\(([^)\s]+)\)', text):
        full = m.group(2)
        if '#' not in full:
            continue
        url, _, anchor = full.partition('#')
        if not anchor:
            continue
        if url.startswith(('http://', 'https://', 'mailto:')):
            continue
        if url == '':
            target = md
        else:
            target = (md.parent / url).resolve()
        if not target.exists() or target.is_dir():
            continue
        checked += 1
        if anchor not in headings_for(target):
            dead.append(f"{md.relative_to(root)}: anchor not found: {full} (target headings: {sorted(headings_for(target))[:5]}...)")

if dead:
    print("FAIL: anchor references with no matching heading:")
    for d in dead:
        print(f"  {d}")
    sys.exit(1)

print(f"PASS: {checked} anchor references resolve to real headings")
PY
