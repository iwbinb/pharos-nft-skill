# Multicall3 Batch Operation Instructions

This file documents how to fold N independent read-only RPC calls into a single round trip via the canonical Multicall3 contract deployed at `0xcA11bde05977b3631167028862bE2a173976CA11` on both Pharos networks.

Use this pattern any time the same workflow would otherwise issue more than 3 sequential `cast call` invocations against the same RPC: standard detection across many collections, ownership checks for many wallets, tokenId-to-owner lookups for many tokenIds, or any mix of the above. One Multicall3 round trip is materially cheaper than N independent ones and avoids the rate-limit / sequencing issues that show up against public RPC endpoints.

> **Multicall3 address**: read from `assets/multicall.json` field `.deployedOn[$NET]`.
>
> **ABI**: `aggregate3((address target, bool allowFailure, bytes callData)[])(((bool success, bytes returnData))[])`.

---

## When To Use Multicall3 vs Native Batch Methods

- **ERC-1155 same-collection, many (holder, tokenId) pairs**: prefer the contract's native `balanceOfBatch(address[],uint256[])` (one RPC, no Multicall3 needed). See [`ownership.md`](ownership.md#erc-1155-balance-check).
- **Any other batching** (cross-collection, ERC-721 `balanceOf` of many wallets, ERC-721 `ownerOf` of many tokenIds, mixed read calls): use Multicall3 `aggregate3`.

---

## Command Template: aggregate3

```bash
SKILL_DIR=~/.claude/skills/pharos-nft-skill
NET=atlantic-testnet
RPC=$(jq -r --arg n "$NET" '.networks[] | select(.name==$n) | .rpcUrl' "$SKILL_DIR/assets/networks.json")
MC3=$(jq -r --arg n "$NET" '.deployedOn[$n]' "$SKILL_DIR/assets/multicall.json")

# Step 1: encode each individual call's calldata
CALLDATA_1=$(cast calldata "balanceOf(address)(uint256)" 0xWALLET_A)
CALLDATA_2=$(cast calldata "balanceOf(address)(uint256)" 0xWALLET_B)
CALLDATA_3=$(cast calldata "ownerOf(uint256)(address)" 42)

# Step 2: assemble the Call3 tuple array literal
CALLS="[(0xCOLLECTION_A,false,$CALLDATA_1),(0xCOLLECTION_A,false,$CALLDATA_2),(0xCOLLECTION_B,true,$CALLDATA_3)]"

# Step 3: execute the batch
RAW=$(cast call "$MC3" "aggregate3((address,bool,bytes)[])((bool,bytes)[])" "$CALLS" --rpc-url "$RPC")
echo "$RAW"
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `target` | address | Yes | Contract to call |
| `allowFailure` | bool | Yes | If `true`, the batch continues even if this sub-call reverts; if `false`, a single revert aborts the whole batch |
| `callData` | bytes | Yes | ABI-encoded function selector + arguments, produced by `cast calldata` |

`allowFailure=true` is the right default for surveys (snapshots, eligibility scans, holdings enumeration) where partial data is still useful. `allowFailure=false` is the right default for atomic precondition checks where partial results are misleading.

### Output Parsing

`aggregate3` returns `(bool,bytes)[]`. Each element corresponds positionally to the input `Call3`. Decode each `returnData` according to the underlying function's return type.

Example: a batch of 3 `balanceOf(address)(uint256)` calls returns three `(true, 0x000...001)` tuples; strip the wrapper and convert each `returnData` to a decimal uint256.

A practical helper:

```bash
# Decode the raw aggregate3 return into per-call (success, returnData) rows.
# Note: cast abi-decode requires a function-shape signature.
echo "$RAW" | cast abi-decode 'aggregate3()((bool,bytes)[])' | \
  jq -r '.[] | "\(.[0])\t\(.[1])"' | \
  while IFS=$'\t' read -r ok hex; do
    if [ "$ok" = "true" ]; then
      cast to-dec "$hex"
    else
      echo "REVERTED"
    fi
  done
```

### Error Handling

| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `Multicall3: call failed` | A sub-call reverted while `allowFailure=false` | Switch the offending entry to `allowFailure=true`, or fix the calldata |
| `query returned more than ...` | The batch exceeded the RPC's gas / return-size limit | Split the batch into chunks (see chunking section below) |
| Empty return on the Multicall3 itself | Wrong Multicall3 address for the current network | Re-read `assets/multicall.json` and confirm `$NET` |
| One sub-call returns empty `returnData` | Target address has no contract code, or `allowFailure=true` swallowed a revert | Inspect the `success` flag; if `false`, surface a per-index error to the user |

### Agent Guidelines

> **Always** assemble Multicall3 batches when the user's question would otherwise require ≥ 4 sequential `cast call` invocations. Default `allowFailure` to `true` for surveys, `false` for precondition checks. After execution, present results in the original input order so the user can map outputs back to their wallets / tokenIds without manual bookkeeping.

---

## Chunking Strategy

Public Pharos RPC endpoints enforce a per-call gas ceiling. A Multicall3 batch that loops `tokenOfOwnerByIndex` for a holder with 5,000 tokens will exceed that ceiling in a single call. Split:

- Default chunk size: **500 sub-calls per Multicall3 batch**.
- For unusually heavy sub-calls (`tokenURI`, methods that themselves loop), reduce to **100 per batch**.
- For unusually light sub-calls (pure-arithmetic getters), increase to **1000 per batch** if you have measured headroom.

Implementation pattern:

```bash
TOTAL=N
CHUNK=500
for ((i=0; i<TOTAL; i+=CHUNK)); do
  END=$((i + CHUNK))
  if [ $END -gt $TOTAL ]; then END=$TOTAL; fi
  # Assemble Call3[] for indices [i, END)
  # Invoke Multicall3
  # Append decoded results to running output
done
```

### Agent Guidelines

> Show the user a progress indicator when chunking: e.g. `chunk 3/12 done, 1500/6000 results in`. Snapshots of large collections can take 30+ seconds; silent waits are a worse user experience than verbose ones.

---

## Cross-Collection Holding Aggregation

Aggregating a single wallet's NFT count across many collections is a single Multicall3 batch.

```bash
SKILL_DIR=~/.claude/skills/pharos-nft-skill
NET=atlantic-testnet
RPC=$(jq -r --arg n "$NET" '.networks[] | select(.name==$n) | .rpcUrl' "$SKILL_DIR/assets/networks.json")
MC3=$(jq -r --arg n "$NET" '.deployedOn[$n]' "$SKILL_DIR/assets/multicall.json")
WALLET=0xUSER_WALLET

# Build one balanceOf call per registered collection on this network
CALLS="["
FIRST=1
while IFS= read -r col; do
  cd=$(cast calldata "balanceOf(address)(uint256)" "$WALLET")
  if [ $FIRST -eq 1 ]; then FIRST=0; else CALLS+=","; fi
  CALLS+="($col,true,$cd)"
done < <(jq -r --arg n "$NET" '.[$n][].address' "$SKILL_DIR/assets/collections.json")
CALLS+="]"

cast call "$MC3" "aggregate3((address,bool,bytes)[])((bool,bytes)[])" "$CALLS" --rpc-url "$RPC"
```

### Agent Guidelines

> Use this pattern when the user asks "what NFTs does wallet X hold across all my tracked collections?" Combine it with `tokenOfOwnerByIndex` follow-up batches (one per non-zero result) to escalate from counts to specific tokenIds. ERC-1155 collections in the same registry need to be handled separately because `balanceOf` has a different signature; partition the registry by `standard` field first.

---

## Many-Wallet Membership Check (Airdrop Snapshot)

Check whether each wallet in a large list holds ≥ 1 NFT from a target collection: the core primitive behind airdrop eligibility, gated whitelists, and DAO voting weight.

```bash
WALLETS_FILE=eligible-candidates.txt   # one address per line
COLLECTION=0xPHAROS_PUNKS

CALLS="["
FIRST=1
while IFS= read -r w; do
  cd=$(cast calldata "balanceOf(address)(uint256)" "$w")
  if [ $FIRST -eq 1 ]; then FIRST=0; else CALLS+=","; fi
  CALLS+="($COLLECTION,true,$cd)"
done < "$WALLETS_FILE"
CALLS+="]"

cast call "$MC3" "aggregate3((address,bool,bytes)[])((bool,bytes)[])" "$CALLS" --rpc-url "$RPC"
```

Combine with the chunking pattern when the wallet list exceeds the per-batch limit. The structured rule-driven version of this flow lives in [`eligibility.md`](eligibility.md).

### Agent Guidelines

> Strip duplicates and validate addresses with `cast --to-checksum-address` before assembling the batch. Surface the eligible-count summary first (`482 of 1000 wallets eligible`), then offer the full per-wallet result list as a follow-up.
