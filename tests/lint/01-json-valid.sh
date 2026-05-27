#!/usr/bin/env bash
# Every .json file in the repo (outside .git and tests/_out) must parse cleanly with jq.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

FAIL=0
COUNT=0
while IFS= read -r -d '' f; do
  COUNT=$((COUNT+1))
  if jq empty "$f" 2>/dev/null; then
    :
  else
    echo "FAIL: invalid JSON: $f"
    jq empty "$f" 2>&1 | sed 's/^/  /' || true
    FAIL=1
  fi
done < <(find . -type f -name '*.json' -not -path './.git/*' -not -path './tests/_out/*' -print0)

if [ $FAIL -eq 0 ]; then
  echo "PASS: $COUNT JSON files parse cleanly"
fi

exit $FAIL
