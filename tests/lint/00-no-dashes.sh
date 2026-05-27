#!/usr/bin/env bash
# Forbid em-dash (U+2014) and en-dash (U+2013) in any tracked text file.
# Both are AI-generated-text tells per project house style.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

# Skip the tests/ directory: tests grep for forbidden characters by literal name, so they
# themselves legitimately contain them.
HITS=$(grep -rln $'—\|–' \
  --include='*.md' --include='*.json' --include='*.sol' --include='*.toml' --include='*.sh' \
  --exclude-dir=tests \
  . 2>/dev/null || true)

if [ -n "$HITS" ]; then
  echo "FAIL: em-dash or en-dash found in:"
  echo "$HITS" | sed 's/^/  /'
  echo ""
  echo "Offending lines:"
  grep -rn $'—\|–' \
    --include='*.md' --include='*.json' --include='*.sol' --include='*.toml' --include='*.sh' \
    --exclude-dir=tests \
    . 2>/dev/null | sed 's/^/  /'
  exit 1
fi

echo "PASS: no em-dash or en-dash in tracked text files"
