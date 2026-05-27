#!/usr/bin/env bash
# SKILL.md must have a valid YAML-style frontmatter block with:
#   name, description, version, requires.anyBins (containing cast, forge, jq, curl)

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SKILL="$ROOT/SKILL.md"

if [ ! -f "$SKILL" ]; then
  echo "FAIL: SKILL.md missing"
  exit 1
fi

# Extract everything between the first two '---' lines.
FM=$(awk '/^---$/{c++; if(c==2)exit; next} c==1' "$SKILL")

if [ -z "$FM" ]; then
  echo "FAIL: SKILL.md has no '---' fenced frontmatter"
  exit 1
fi

require_key() {
  local key="$1"
  if ! grep -qE "^${key}:" <<< "$FM"; then
    echo "FAIL: SKILL.md frontmatter missing key: $key"
    exit 1
  fi
}

require_key name
require_key description
require_key version
require_key requires

# requires.anyBins block
for bin in cast forge jq curl; do
  if ! grep -qE "^\s+-\s+${bin}$" <<< "$FM"; then
    echo "FAIL: requires.anyBins missing entry: $bin"
    exit 1
  fi
done

# description folded scalar 'description: >' (multi-line)
if ! grep -qE "^description: >\s*$" <<< "$FM"; then
  echo "FAIL: description is not a folded scalar (expected 'description: >')"
  exit 1
fi

# description body length sanity
DESC_LEN=$(awk '/^description: >$/{flag=1; next} /^[a-z]/{flag=0} flag' <<< "$FM" | wc -c | tr -d ' ')
if [ "$DESC_LEN" -lt 400 ]; then
  echo "FAIL: description body too short ($DESC_LEN chars). Needs rich trigger keywords."
  exit 1
fi

echo "PASS: SKILL.md frontmatter valid (name, description ${DESC_LEN}c, version, requires.anyBins[cast,forge,jq,curl])"
