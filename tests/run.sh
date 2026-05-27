#!/usr/bin/env bash
# Top-level test runner. Runs all suites in order: lint, jq, live (optional).
#
# Usage:
#   tests/run.sh              # lint + jq (no network)
#   tests/run.sh --with-live  # lint + jq + live RPC smoke tests against Atlantic testnet
#   tests/run.sh --only lint  # only the lint suite

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

ONLY=""
WITH_LIVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --with-live) WITH_LIVE=1; shift ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done

PASS=0
FAIL=0
FAILED_TESTS=()

run_suite() {
  local suite="$1"
  echo ""
  echo "=== suite: $suite ==="
  for t in "$ROOT/tests/$suite"/*.sh; do
    [ -e "$t" ] || continue
    local name=$(basename "$t" .sh)
    printf "  [%s] " "$name"
    if bash "$t" > "$ROOT/tests/_out/${suite}_${name}.log" 2>&1; then
      echo "OK"
      PASS=$((PASS+1))
    else
      echo "FAIL"
      sed 's/^/      /' "$ROOT/tests/_out/${suite}_${name}.log"
      FAIL=$((FAIL+1))
      FAILED_TESTS+=("${suite}/${name}")
    fi
  done
}

mkdir -p "$ROOT/tests/_out"

if [ -z "$ONLY" ] || [ "$ONLY" = "lint" ]; then
  run_suite lint
fi
if [ -z "$ONLY" ] || [ "$ONLY" = "jq" ]; then
  run_suite jq
fi
if [ "$WITH_LIVE" = 1 ] && { [ -z "$ONLY" ] || [ "$ONLY" = "live" ]; }; then
  run_suite live
fi

echo ""
echo "================================"
echo "  $PASS passed, $FAIL failed"
echo "================================"
if [ $FAIL -gt 0 ]; then
  printf "Failed tests:\n"
  printf "  %s\n" "${FAILED_TESTS[@]}"
  exit 1
fi
