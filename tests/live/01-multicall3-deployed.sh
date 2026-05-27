#!/usr/bin/env bash
# Verify Multicall3 is deployed at the canonical address on Atlantic testnet.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' "$ROOT/assets/networks.json")
MC3=$(jq -r '.deployedOn["atlantic-testnet"]' "$ROOT/assets/multicall.json")

RESP=$(curl -fsS --retry 2 --retry-all-errors --retry-delay 1 --max-time 10 "$RPC" -X POST -H 'Content-Type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$MC3\",\"latest\"],\"id\":1}")
CODE=$(echo "$RESP" | jq -r '.result // empty')

if [ -z "$CODE" ] || [ "$CODE" = "0x" ] || [ "$CODE" = "null" ]; then
  echo "FAIL: Multicall3 not deployed at $MC3 on Atlantic testnet"
  echo "  Response: $RESP"
  exit 1
fi

LEN=${#CODE}
# Bytecode for canonical Multicall3 is ~5KB hex; sanity check it's substantial.
if [ "$LEN" -lt 1000 ]; then
  echo "FAIL: bytecode at $MC3 too small ($LEN hex chars), probably not Multicall3"
  exit 1
fi

# Sanity check: contains the 'Multicall3:' error prefix string.
if ! echo "$CODE" | grep -q "4d756c746963616c6c33"; then
  # That's "Multicall3" in hex. Absence is suspicious but not fatal (could be a fork).
  echo "WARN: bytecode at $MC3 does not contain 'Multicall3' string. Continuing."
fi

echo "PASS: Multicall3 deployed at $MC3 (bytecode $LEN hex chars)"
