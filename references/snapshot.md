# Snapshot and History Operation Instructions

This file documents the event-log primitives that power three high-value NFT workflows:

1. **Full collection holder snapshot** at a specific block height — "who owns what right now (or at block N)?"
2. **Wallet holdings enumeration via log scan** — the fallback path for collections that do not implement ERC-721 Enumerable.
3. **TokenId transfer history reconstruction** — the chain of custody for one specific NFT.

A complementary section covers **wallet holdings diff** — purely a jq operation on top of two enumerations.

All of these are read-only and never require a private key.

> **RPC log limits**: read the per-network `logScanMaxBlocks` from `assets/networks.json`. Default 10,000 blocks per `cast logs` request. Public Pharos endpoints reject larger ranges with `query returned more than ...` or `range too large`.

---

## ERC-721 Transfer Event Reference

The canonical signature is:

```
Transfer(address indexed from, address indexed to, uint256 indexed tokenId)
```

| Topic Index | Field | Notes |
|-------------|-------|-------|
| topic0 | event hash | `0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef` |
| topic1 | from (indexed) | Zero address = mint |
| topic2 | to (indexed) | Zero address = burn |
| topic3 | tokenId (indexed) | Filter on this for tokenId-specific history |

The ERC-721 standard mandates that `tokenId` be indexed. A handful of pre-standard collections (e.g. early CryptoPunks-style) omit the index, in which case topic3 is empty and you must filter by decoded data instead. Detect this by inspecting the first event returned.

---

## ERC-1155 Transfer Event Reference

Two events:

```
TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value)
TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values)
```

`id` and `value(s)` are **not** indexed — they live in the data field. This means you cannot pre-filter by tokenId at the RPC layer; you must fetch the full window and filter client-side with jq.

---

## Full Collection Snapshot

Reconstruct the complete holder map of a collection at block `N` by replaying every `Transfer` event from the deploy block up to `N` and folding the from/to pairs into a running ownership table.

### Procedure

1. Read the collection's `deployBlock` from `assets/collections.json` (or accept a user-supplied lower bound).
2. Read `logScanMaxBlocks` from `networks.json` (call it `W`).
3. Split the range `[deployBlock, snapshotBlock]` into chunks of width `W`.
4. For each chunk, call `cast logs` against the Transfer signature, filtered by the collection address.
5. Sort the combined event list by `(blockNumber, logIndex)` ascending — order matters because the same tokenId can transfer multiple times.
6. For ERC-721: maintain `owner[tokenId] = to` updated in event order. After the replay, `owner[tokenId]` is the holder at `snapshotBlock`. Drop entries where `owner[tokenId] == 0x0` (burnt).
7. For ERC-1155: maintain `balance[holder][tokenId]` — add `value` on `to`, subtract on `from`. After the replay, emit `(holder, tokenId, balance)` triples with `balance > 0`.

### Command Template (ERC-721, single chunk)

```bash
SKILL_DIR=~/.claude/skills/pharos-nft-skill
NET=atlantic-testnet
RPC=$(jq -r --arg n "$NET" '.networks[] | select(.name==$n) | .rpcUrl' "$SKILL_DIR/assets/networks.json")
COLLECTION=0xCOLLECTION
FROM=1000000
TO=1010000

cast logs "Transfer(address,address,uint256)" \
  --from-block $FROM --to-block $TO \
  --address "$COLLECTION" \
  --rpc-url "$RPC" \
  --json > chunk_${FROM}_${TO}.json
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<collection>` | string | Yes | NFT contract address |
| `--from-block` | uint | Yes | Lower bound block, usually deployBlock for full snapshot |
| `--to-block` | uint | Yes | Upper bound block; use `latest` for current state |
| `--json` | flag | recommended | Emit machine-readable output for jq processing |

### Output Parsing (per chunk)

`cast logs --json` emits one JSON object per event:

```json
{
  "address": "0xCOLLECTION",
  "topics": [
    "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
    "0x000...sender",
    "0x000...recipient",
    "0x000...tokenId"
  ],
  "data": "0x",
  "blockNumber": "0x...",
  "transactionHash": "0x...",
  "logIndex": "0x..."
}
```

Fold with jq:

```bash
# Concatenate chunks, sort by block and logIndex, fold into owner map
cat chunk_*.json | jq -s '
  flatten
  | sort_by([.blockNumber | tonumber, .logIndex | tonumber])
  | reduce .[] as $e ({};
      ($e.topics[3] | tonumber) as $tid
      | ($e.topics[2] | sub("^0x0+"; "0x")) as $to
      | .[$tid | tostring] = $to
    )
  | with_entries(select(.value != "0x0000000000000000000000000000000000000000"))
'
```

Wrap that in a chunked driver script — see `assets/scripts/snapshot.sh` for the full reference implementation (the script is not required; everything above is reproducible from these templates alone).

### Error Handling

| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `query returned more than X results` | Chunk range too large | Halve the chunk width, retry |
| `range too large` | Same as above | Same as above |
| `no logs found` | Empty chunk | Normal for low-activity ranges, continue to next chunk |
| Inconsistent owner result (`ownerOf(tid)` disagrees with replay) | Reorg, missed event, or proxy-mediated transfer that didn't emit `Transfer` | Spot-check with on-chain `ownerOf` for the disputed tokenId, prefer the on-chain truth |

### Agent Guidelines

> Snapshots are computationally bounded by event volume, not collection size. A 10,000-supply collection with low velocity scans faster than a 100-supply collection that has churned 50,000 times. Cache results aggressively keyed by `(collection, snapshotBlock)` — they are immutable once produced. Always announce the snapshot block to the user; "current snapshot" without a block height is ambiguous on a live chain.

---

## TokenId Transfer History

The transfer history of a single tokenId in an ERC-721 collection is a filtered log scan with `tokenId` as topic3.

### Command Template

```bash
SKILL_DIR=~/.claude/skills/pharos-nft-skill
NET=atlantic-testnet
RPC=$(jq -r --arg n "$NET" '.networks[] | select(.name==$n) | .rpcUrl' "$SKILL_DIR/assets/networks.json")
COLLECTION=0xCOLLECTION
TOKEN_ID=42

# Encode tokenId as a 32-byte topic
TOKEN_TOPIC=$(cast --to-uint256 $TOKEN_ID)

cast logs "Transfer(address,address,uint256)" \
  --from-block 0 --to-block latest \
  --address "$COLLECTION" \
  "" "" "$TOKEN_TOPIC" \
  --rpc-url "$RPC" \
  --json
```

The three positional arguments after the signature are topic1, topic2, topic3 filters respectively; empty string means "match any". Filtering on topic3 alone is server-side and very fast.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<collection>` | string | Yes | NFT contract address |
| `<tokenId>` | uint256 | Yes | The specific tokenId to trace |
| `<rpc>` | string | Yes | RPC endpoint URL |

### Output Parsing

A chronologically sorted list of Transfer events, one per change of ownership. Pair adjacent events to derive `(blockNumber, from, to, txHash)` rows. The first event with `from = 0x0` is the mint.

```bash
cast logs ... --json | jq -s '
  sort_by([.[0].blockNumber | tonumber, .[0].logIndex | tonumber])
  | .[]
  | {
      block: (.blockNumber | tonumber),
      from: (.topics[1] | sub("^0x0+"; "0x")),
      to:   (.topics[2] | sub("^0x0+"; "0x")),
      tx:   .transactionHash
    }
'
```

### Error Handling

Same as Full Collection Snapshot. If no events are returned for a tokenId in a collection that does mint that tokenId, suspect a non-standard `Transfer` event or a non-indexed `tokenId` — fall back to scanning all events and filtering on the data field.

### Agent Guidelines

> If the user asks "how many times has this NFT traded?" answer with the event count minus 1 (subtract the mint). If they ask "who's held it the longest?" compute the diffs between consecutive event blocks and report the holder with the largest gap. Include block explorer tx links in every row.

---

## Wallet Holdings — Log Scan Path

For collections that do not implement ERC-721 Enumerable, enumerate a wallet's current holdings by replaying Transfer events filtered on the wallet as either sender or receiver.

### Procedure

1. Fetch events with `topic1 = wallet` (transfers OUT of the wallet) and `topic2 = wallet` (transfers IN to the wallet) — two scans.
2. Combine, sort by `(blockNumber, logIndex)`.
3. Maintain a running set `held: {tokenId}` — add on IN events, remove on OUT events.
4. After replay, `held` is the wallet's current tokenIds.
5. Verify with one Multicall3 batch of `ownerOf(tokenId)` to catch missed events from non-standard contracts.

### Command Template

```bash
COLLECTION=0xCOLLECTION
WALLET=0xUSER
WALLET_TOPIC=$(cast --to-uint256 "$WALLET")   # left-pad to 32 bytes

# Events where wallet was the recipient
cast logs "Transfer(address,address,uint256)" \
  --from-block 0 --to-block latest \
  --address "$COLLECTION" \
  "" "$WALLET_TOPIC" "" \
  --rpc-url "$RPC" --json > in.json

# Events where wallet was the sender
cast logs "Transfer(address,address,uint256)" \
  --from-block 0 --to-block latest \
  --address "$COLLECTION" \
  "$WALLET_TOPIC" "" "" \
  --rpc-url "$RPC" --json > out.json
```

Fold with jq:

```bash
jq -s '
  (.[0] + .[1])
  | sort_by([.blockNumber | tonumber, .logIndex | tonumber])
  | reduce .[] as $e ({};
      ($e.topics[3]) as $tid
      | ($e.topics[2] | sub("^0x0+"; "0x")) as $to
      | if ($to | ascii_downcase) == ("'"$WALLET"'" | ascii_downcase)
        then .[$tid] = true
        else del(.[$tid])
        end
    )
  | keys
' in.json out.json
```

### Error Handling

Same as the full snapshot. Verification mismatch (event replay says held, on-chain `ownerOf` disagrees) usually means a non-emitting transfer happened; trust on-chain.

### Agent Guidelines

> Whenever a wallet has more than ~50 lifetime IN events for a collection, the cost difference between the Enumerable path and the log-scan path becomes large. Always prefer Enumerable when available. The log-scan path is the safety net for collections that simply do not implement it.

---

## Wallet Holdings Diff

Given two wallets, compute:

- tokens held by A but not B
- tokens held by B but not A
- tokens held by both

This is a pure set operation over the two enumerations. Do not issue any extra RPC calls beyond what the two enumerations already require.

### Command Template

```bash
# Assume the two enumerations have been written to a.json and b.json as JSON arrays of tokenIds
jq -n --slurpfile a a.json --slurpfile b b.json '
  ($a[0] | map(tostring) | unique) as $A
  | ($b[0] | map(tostring) | unique) as $B
  | {
      onlyA: ($A - $B),
      onlyB: ($B - $A),
      both:  ($A - ($A - $B))
    }
'
```

### Agent Guidelines

> Report cardinalities first ("A has 12 not in B, B has 3 not in A, 5 shared"), then offer the full lists as a follow-up. Sort outputs numerically so the user can scan them.
