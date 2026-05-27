#!/usr/bin/env bash
# eth_call balanceOf(address) on the testnet USDC contract. This is the exact calldata
# shape the skill uses for ERC-721 balanceOf and ERC-20 balanceOf alike.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' "$ROOT/assets/networks.json")

# USDC on Atlantic testnet (from pharos-skill-engine tokens.json).
USDC=0xE0BE08c77f415F577A1B3A9aD7a1Df1479564ec8

# balanceOf(0x000...0001): selector 0x70a08231 + 32-byte address
DATA='0x70a082310000000000000000000000000000000000000000000000000000000000000001'

RESP=$(curl -fsS --retry 2 --retry-all-errors --retry-delay 1 --max-time 10 "$RPC" -X POST -H 'Content-Type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$USDC\",\"data\":\"$DATA\"},\"latest\"],\"id\":1}")
RES=$(echo "$RESP" | jq -r '.result // empty')

if [ -z "$RES" ] || [ "$RES" = "null" ]; then
  echo "FAIL: eth_call returned null"
  echo "  Response: $RESP"
  exit 1
fi

# Result must be exactly 0x + 64 hex chars (a uint256 word).
if ! [[ "$RES" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
  echo "FAIL: result is not a 32-byte word: $RES"
  exit 1
fi

echo "PASS: eth_call balanceOf shape returns uint256 ($RES)"
