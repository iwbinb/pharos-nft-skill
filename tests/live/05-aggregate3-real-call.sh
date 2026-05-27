#!/usr/bin/env bash
# Hand-encode a real aggregate3 call with one sub-call (balanceOf on USDC). Confirms the
# tuple/array encoding template used in references/batch.md actually decodes correctly when
# the contract executes it.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' "$ROOT/assets/networks.json")
MC3=$(jq -r '.deployedOn["atlantic-testnet"]' "$ROOT/assets/multicall.json")

# Layout (hex bytes, "0x" prefix added at the end):
#   selector:                 82ad56cb
#   offset to outer array:    0000...0020
#   outer array length:       0000...0001
#   offset to tuple[0] (rel): 0000...0020
#   tuple[0].target:          USDC padded
#   tuple[0].allowFailure:    0000...0001 (true)
#   tuple[0].callData offset: 0000...0060
#   tuple[0].callData length: 0000...0024 (36 bytes)
#   tuple[0].callData:        70a08231 + 32-byte address (padded to next 32-byte boundary)

USDC_PAD=000000000000000000000000E0BE08c77f415F577A1B3A9aD7a1Df1479564ec8
ADDR_001_PAD=0000000000000000000000000000000000000000000000000000000000000001
CALLDATA="70a08231$ADDR_001_PAD"
# callData length in bytes = (4 + 32) = 36 = 0x24. Pad with 28 zero bytes to next 32-byte boundary.
CALLDATA_PADDED="${CALLDATA}00000000000000000000000000000000000000000000000000000000"

DATA="0x82ad56cb"
DATA="${DATA}0000000000000000000000000000000000000000000000000000000000000020"  # outer array offset
DATA="${DATA}0000000000000000000000000000000000000000000000000000000000000001"  # outer array length
DATA="${DATA}0000000000000000000000000000000000000000000000000000000000000020"  # tuple[0] offset
DATA="${DATA}${USDC_PAD}"                                                         # tuple[0].target
DATA="${DATA}0000000000000000000000000000000000000000000000000000000000000001"  # tuple[0].allowFailure
DATA="${DATA}0000000000000000000000000000000000000000000000000000000000000060"  # tuple[0].callData offset
DATA="${DATA}0000000000000000000000000000000000000000000000000000000000000024"  # tuple[0].callData length
DATA="${DATA}${CALLDATA_PADDED}"                                                  # tuple[0].callData

RESP=$(curl -fsS --retry 2 --retry-all-errors --retry-delay 1 --max-time 15 "$RPC" -X POST -H 'Content-Type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$MC3\",\"data\":\"$DATA\"},\"latest\"],\"id\":1}")
RES=$(echo "$RESP" | jq -r '.result // empty')

if [ -z "$RES" ] || [ "$RES" = "null" ]; then
  ERR=$(echo "$RESP" | jq -r '.error // empty')
  echo "FAIL: aggregate3 single-call returned no result"
  echo "  error: $ERR"
  echo "  raw:   $RESP"
  exit 1
fi

# Sanity: return must be at least the outer array offset + length + 1 tuple struct (5 words).
LEN=${#RES}
if [ "$LEN" -lt $((2 + 5*64)) ]; then
  echo "FAIL: aggregate3 return too short ($LEN hex chars)"
  echo "  raw: $RES"
  exit 1
fi

# Expect tuple[0].success = true (last 32 bytes of the tuple's first word).
# Outer offset + length + tuple offset + success-word
SUCCESS_WORD_START=$((2 + 64 + 64 + 64))  # skip 0x, outer-offset, outer-length, tuple-offset
SUCCESS=${RES:$SUCCESS_WORD_START:64}

if [[ "$SUCCESS" != *"01" ]]; then
  echo "FAIL: aggregate3 sub-call success != 1"
  echo "  success word: $SUCCESS"
  echo "  raw:          $RES"
  exit 1
fi

echo "PASS: aggregate3 with 1 sub-call (USDC.balanceOf) returns success=true"
