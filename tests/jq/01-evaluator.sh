#!/usr/bin/env bash
# Run the eligibility-DSL evaluator across (rule, holdings) pairs and check expected results.
# This pins the canonical jq expression for the evaluator. The same expression must appear
# verbatim in references/eligibility.md (verified by tests/jq/02-doc-evaluator-matches.sh).

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FIX="$ROOT/tests/jq/fixtures"

EVAL='
  def evalRule(r; h):
    r as $r | h as $h
    | if   $r | has("all_of")   then ($r.all_of   | map(evalRule(.; $h)) | all)
      elif $r | has("any_of")   then ($r.any_of   | map(evalRule(.; $h)) | any)
      elif $r | has("none_of")  then ($r.none_of  | map(evalRule(.; $h)) | any | not)
      elif $r | has("min_count")
        then ($r.min_count as $mc | ($h[$mc.collection] // []) | length >= $mc.n)
      else error("invalid rule node") end;
  evalRule($rule[0]; $h[0])
'

run_case() {
  local desc="$1"
  local rule="$2"
  local holdings="$3"
  local expected="$4"
  local got
  got=$(jq -n --slurpfile rule "$FIX/$rule" --slurpfile h "$FIX/$holdings" "$EVAL")
  if [ "$got" = "$expected" ]; then
    printf "  OK   %-60s -> %s\n" "$desc" "$got"
  else
    printf "  FAIL %-60s expected=%s got=%s\n" "$desc" "$expected" "$got"
    return 1
  fi
}

FAILED=0

run_case "alice + min_count(aaaa>=2)"  rule-min-count.json holdings-alice.json true  || FAILED=1
run_case "alice + and(aaaa>=1, bbbb>=2)" rule-and.json     holdings-alice.json true  || FAILED=1
run_case "alice + or(zzzz>=1, bbbb>=1)"  rule-or.json      holdings-alice.json true  || FAILED=1
run_case "alice + none(cccc>=1)"         rule-none.json    holdings-alice.json true  || FAILED=1
run_case "alice + nested"                rule-nested.json  holdings-alice.json true  || FAILED=1

run_case "bob + min_count(aaaa>=2)"    rule-min-count.json holdings-bob.json   false || FAILED=1
run_case "bob + and(aaaa>=1, bbbb>=2)"   rule-and.json     holdings-bob.json   false || FAILED=1
run_case "bob + or(zzzz>=1, bbbb>=1)"    rule-or.json      holdings-bob.json   false || FAILED=1
run_case "bob + none(cccc>=1)"           rule-none.json    holdings-bob.json   false || FAILED=1
run_case "bob + nested"                  rule-nested.json  holdings-bob.json   false || FAILED=1

run_case "empty + min_count(aaaa>=2)"  rule-min-count.json holdings-empty.json false || FAILED=1
run_case "empty + and(...)"              rule-and.json     holdings-empty.json false || FAILED=1
run_case "empty + or(...)"               rule-or.json      holdings-empty.json false || FAILED=1
run_case "empty + none(cccc>=1)"         rule-none.json    holdings-empty.json true  || FAILED=1
run_case "empty + nested"                rule-nested.json  holdings-empty.json false || FAILED=1

if [ $FAILED -eq 0 ]; then
  echo "PASS: 15/15 eligibility DSL cases"
else
  exit 1
fi
