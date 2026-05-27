#!/usr/bin/env bash
# Extract every fenced ```bash block from markdown files in the repo, run `bash -n` on each
# to catch syntax errors. Skips blocks marked 'bash skip-lint' which contain template
# placeholders that intentionally break shell quoting.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/tests/_out/bash-blocks"
mkdir -p "$OUT"
rm -f "$OUT"/*.sh

ROOT="$ROOT" OUT="$OUT" python3 - <<'PY'
import os, re, sys
from pathlib import Path

root = Path(os.environ["ROOT"])
out = Path(os.environ["OUT"])

block_id = 0
saved = []

# Reference docs use angle-bracket placeholders like <wallet>, <collection>, <rpc>. Bash would
# parse those as input/output redirects and fail syntax check. For lint purposes we substitute
# every such placeholder with a safe token, keeping the structure of the surrounding command
# intact. This trades a small loss of fidelity for the ability to syntax-check at all.
PLACEHOLDER_RE = re.compile(r'<([A-Za-z_][A-Za-z0-9_]*)>')

def neutralize(body: str) -> str:
    return PLACEHOLDER_RE.sub(r'PH_\1', body)

for md in root.rglob('*.md'):
    if '.git' in md.parts: continue
    if 'tests/_out' in str(md): continue
    text = md.read_text()
    # Match fenced bash blocks. Allow 'bash' or 'sh'. Tag-skip if first line is '# skip-lint'.
    fence = chr(0x60) * 3
    pattern = r'^' + fence + r'(?:bash|sh)\s*\n(.*?)\n' + fence
    for m in re.finditer(pattern, text, re.MULTILINE | re.DOTALL):
        body = m.group(1)
        if body.strip().startswith('# skip-lint'):
            continue
        block_id += 1
        out_path = out / f"{md.stem}_{block_id:03}.sh"
        out_path.write_text(neutralize(body))
        saved.append((md.relative_to(root), out_path))

print(f"Extracted {len(saved)} bash blocks", file=sys.stderr)
for src, p in saved:
    print(p)
PY

FAIL=0
COUNT=0
ERR_LOG="$ROOT/tests/_out/bash-syntax-errors.log"
: > "$ERR_LOG"

for f in "$OUT"/*.sh; do
  [ -e "$f" ] || continue
  COUNT=$((COUNT+1))
  if bash -n "$f" 2>>"$ERR_LOG"; then
    :
  else
    echo "FAIL: bash syntax error in $(basename "$f")"
    echo "  --- start of block ---"
    sed -n '1,30p' "$f" | sed 's/^/  /'
    echo "  --- end of block ---"
    FAIL=1
  fi
done

if [ $FAIL -eq 0 ]; then
  echo "PASS: $COUNT bash blocks pass 'bash -n' syntax check"
else
  echo ""
  echo "Errors log: $ERR_LOG"
fi
exit $FAIL
