#!/usr/bin/env bash
# Test the trait-match helper from references/metadata.md. Given metadata JSON and a trait
# filter, the helper returns "true" if every filter key matches the metadata attributes.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

# Canonical helper expression (must match metadata.md).
match() {
  local meta="$1"
  local filter="$2"
  echo "$meta" | jq --argjson traits "$filter" '
    [.attributes // [] | .[] | {(.trait_type): .value}] | add // {}
    | . as $attrs
    | $traits
    | to_entries
    | all(
        .value as $want
        | $attrs[.key] as $have
        | if ($want | type) == "array"
          then $want | any(. == $have)
          else $want == $have
          end
      )
  '
}

META_LEGENDARY='{"name":"Test","attributes":[{"trait_type":"rarity","value":"legendary"},{"trait_type":"background","value":"red"}]}'
META_COMMON='{"name":"Test","attributes":[{"trait_type":"rarity","value":"common"}]}'
META_NO_ATTRS='{"name":"Test"}'

FAILED=0

expect() {
  local desc="$1"
  local got="$2"
  local want="$3"
  if [ "$got" = "$want" ]; then
    printf "  OK   %-45s -> %s\n" "$desc" "$got"
  else
    printf "  FAIL %-45s expected=%s got=%s\n" "$desc" "$want" "$got"
    FAILED=1
  fi
}

expect "legendary item, filter rarity=legendary"    "$(match "$META_LEGENDARY" '{"rarity":"legendary"}')"   true
expect "legendary item, filter rarity=common"       "$(match "$META_LEGENDARY" '{"rarity":"common"}')"      false
expect "legendary item, filter rarity in [...]"     "$(match "$META_LEGENDARY" '{"rarity":["legendary","epic"]}')" true
expect "legendary item, AND filter rarity+bg"       "$(match "$META_LEGENDARY" '{"rarity":"legendary","background":"red"}')" true
expect "legendary item, AND filter rarity+bg blue"  "$(match "$META_LEGENDARY" '{"rarity":"legendary","background":"blue"}')" false
expect "common item, filter rarity=legendary"       "$(match "$META_COMMON" '{"rarity":"legendary"}')"     false
expect "no-attr item, any filter"                   "$(match "$META_NO_ATTRS" '{"rarity":"legendary"}')"   false
expect "no-attr item, empty filter (vacuous true)"  "$(match "$META_NO_ATTRS" '{}')"                        true

if [ $FAILED -eq 0 ]; then
  echo "PASS: 8/8 trait-match cases"
else
  exit 1
fi
