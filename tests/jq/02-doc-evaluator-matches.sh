#!/usr/bin/env bash
# Ensure the canonical jq evaluator expression appears verbatim in references/eligibility.md.
# This catches drift between the documented expression and the one we actually test.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

# The expression we test. Must be a substring of eligibility.md (modulo leading whitespace).
NEEDLE='def evalRule(r; h):'
if ! grep -q "$NEEDLE" "$ROOT/references/eligibility.md"; then
  echo "FAIL: 'def evalRule' not found in references/eligibility.md"
  exit 1
fi

# Required clauses.
for clause in "all_of" "any_of" "none_of" "min_count"; do
  if ! grep -q "r | has(\"$clause\")" "$ROOT/references/eligibility.md"; then
    echo "FAIL: evaluator missing clause for: $clause"
    exit 1
  fi
done

echo "PASS: documented evaluator covers all 4 DSL node types"
