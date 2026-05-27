#!/usr/bin/env bash
# eth_getLogs over a small window (1000 blocks) targeting USDC, filtered on the canonical
# Transfer topic. The test validates the request shape, not the result count (testnet
# activity is variable).

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' "$ROOT/assets/networks.json")
USDC=0xE0BE08c77f415F577A1B3A9aD7a1Df1479564ec8
TRANSFER=0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef

LATEST=$(curl -fsS --retry 2 --retry-all-errors --retry-delay 1 --max-time 10 "$RPC" -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result')
LATEST_DEC=$(printf '%d' "$LATEST")
FROM_DEC=$((LATEST_DEC - 1000))
FROM_HEX=$(printf '0x%x' $FROM_DEC)

RESP=$(curl -fsS --retry 2 --retry-all-errors --retry-delay 1 --max-time 15 "$RPC" -X POST -H 'Content-Type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"$USDC\",\"fromBlock\":\"$FROM_HEX\",\"toBlock\":\"$LATEST\",\"topics\":[\"$TRANSFER\"]}],\"id\":1}")

ERR=$(echo "$RESP" | jq -r '.error // empty')
if [ -n "$ERR" ] && [ "$ERR" != "null" ] && [ "$ERR" != "" ]; then
  echo "FAIL: eth_getLogs returned error"
  echo "  $RESP"
  exit 1
fi

COUNT=$(echo "$RESP" | jq -r '.result | length')
if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
  echo "FAIL: malformed result"
  echo "  $RESP"
  exit 1
fi

echo "PASS: eth_getLogs accepts request shape (1000-block window, $COUNT events)"
