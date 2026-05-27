#!/usr/bin/env bash
# Smoke test: Pharos Atlantic testnet RPC is reachable and serves eth_blockNumber.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' "$ROOT/assets/networks.json")

RESP=$(curl -fsS --retry 2 --retry-all-errors --retry-delay 1 --max-time 10 "$RPC" -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' || true)

if [ -z "$RESP" ]; then
  echo "FAIL: RPC unreachable at $RPC"
  exit 1
fi

BN=$(echo "$RESP" | jq -r '.result // empty')
if [ -z "$BN" ] || [ "$BN" = "null" ]; then
  echo "FAIL: unexpected response: $RESP"
  exit 1
fi

BN_DEC=$(printf '%d' "$BN")
if [ "$BN_DEC" -lt 1000 ]; then
  echo "FAIL: implausible block number $BN_DEC"
  exit 1
fi

echo "PASS: RPC reachable, block number $BN_DEC"
