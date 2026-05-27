#!/usr/bin/env bash
# Call Multicall3.aggregate3([]) and verify it returns the canonical empty-array encoding:
#   0x{32-byte offset to array}{32-byte array length = 0}
#   i.e. 0x0000...0020 0000...0000

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' "$ROOT/assets/networks.json")
MC3=$(jq -r '.deployedOn["atlantic-testnet"]' "$ROOT/assets/multicall.json")

# aggregate3 selector + empty dynamic array (offset 0x20, length 0)
DATA='0x82ad56cb00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000'

RESP=$(curl -fsS --retry 2 --retry-all-errors --retry-delay 1 --max-time 10 "$RPC" -X POST -H 'Content-Type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$MC3\",\"data\":\"$DATA\"},\"latest\"],\"id\":1}")
RES=$(echo "$RESP" | jq -r '.result // empty')

EXPECTED='0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000'

if [ "$RES" = "$EXPECTED" ]; then
  echo "PASS: aggregate3([]) returns canonical empty-array encoding"
else
  echo "FAIL: aggregate3 unexpected return"
  echo "  expected: $EXPECTED"
  echo "  got:      $RES"
  exit 1
fi
