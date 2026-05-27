#!/usr/bin/env bash
# Test the wallet holdings diff snippet from references/snapshot.md.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/tests/_out"
mkdir -p "$OUT"

# Two holdings expressed as token-id arrays (the diff snippet operates on flat arrays, not the
# per-collection holdings shape used by the eligibility evaluator).
echo '["1","2","3","4"]' > "$OUT/a.json"
echo '["3","4","5","6"]' > "$OUT/b.json"

RESULT=$(jq -n --slurpfile a "$OUT/a.json" --slurpfile b "$OUT/b.json" '
  ($a[0] | map(tostring) | unique) as $A
  | ($b[0] | map(tostring) | unique) as $B
  | {
      onlyA: ($A - $B),
      onlyB: ($B - $A),
      both:  ($A - ($A - $B))
    }
')

EXPECTED='{"onlyA":["1","2"],"onlyB":["5","6"],"both":["3","4"]}'
GOT=$(echo "$RESULT" | jq -c '.')

if [ "$GOT" = "$EXPECTED" ]; then
  echo "PASS: holdings diff correctly splits A/B/both"
else
  echo "FAIL: holdings diff"
  echo "  expected: $EXPECTED"
  echo "  got:      $GOT"
  exit 1
fi
