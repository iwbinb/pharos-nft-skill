# Eligibility Rule DSL and Batch Evaluation

This file specifies the declarative eligibility DSL — the killer feature of `pharos-nft-skill`. Given a set of wallets and a rule expressed as JSON, decide for each wallet whether it satisfies the rule. The DSL composes any boolean combination of NFT-ownership constraints with thresholds and optional trait filters.

Typical use cases:

- Airdrop snapshot: "every wallet that holds ≥ 1 PharosPunk AND ≥ 2 PharosCats."
- Gated whitelist: "any wallet that holds (≥ 1 Founder NFT) OR (≥ 5 Genesis NFTs AND no Blacklist NFT)."
- DAO voting weight precondition: "wallet holds ≥ 1 governance NFT at block N."

The DSL is intentionally tiny — 4 node types — and is evaluated by `jq` over pre-batched holdings data, so end-to-end runs are bounded by RPC time, not by evaluator complexity.

---

## Rule Schema

A rule is a JSON object. Exactly one of the following keys is present at each node:

| Key | Type | Semantics |
|-----|------|-----------|
| `all_of` | Rule[] | Logical AND. True iff every sub-rule is true. |
| `any_of` | Rule[] | Logical OR. True iff at least one sub-rule is true. |
| `none_of` | Rule[] | Logical NOT (over an OR). True iff every sub-rule is false. |
| `min_count` | LeafRule | Leaf node. True iff the wallet holds ≥ `n` tokens of `collection` (after applying optional `traits` filter). |

Leaf shape:

```json
{
  "min_count": {
    "collection": "0xCOLLECTION_ADDRESS",
    "n": 1,
    "traits": {
      "rarity": "legendary",
      "background": ["red", "gold"]
    }
  }
}
```

`traits` is optional. When present, only tokens whose metadata `attributes` match every key are counted toward `n`. Multi-value entries are OR-matched per key (the example above means rarity is legendary AND background is red or gold). Metadata fetching is described in [`metadata.md`](metadata.md).

### Full Example

```json
{
  "all_of": [
    {
      "any_of": [
        { "min_count": { "collection": "0xFOUNDER", "n": 1 } },
        {
          "all_of": [
            { "min_count": { "collection": "0xGENESIS", "n": 5 } },
            { "min_count": { "collection": "0xACCESS", "n": 1, "traits": { "tier": "platinum" } } }
          ]
        }
      ]
    },
    {
      "none_of": [
        { "min_count": { "collection": "0xBLACKLIST", "n": 1 } }
      ]
    }
  ]
}
```

In English: holds (a Founder NFT) OR (≥ 5 Genesis NFTs AND a platinum-tier Access NFT); AND does not hold any Blacklist NFT.

---

## End-to-End Evaluation Pipeline

Eligibility evaluation is a four-stage pipeline:

1. **Extract** the set of collections referenced anywhere in the rule.
2. **Batch-fetch** each wallet's holdings (counts and tokenIds) for every referenced collection. ERC-721 paths via Multicall3 [`batch.md`](batch.md), ERC-1155 via `balanceOfBatch`.
3. **Filter by traits** (only for leaves with `traits`): for each matching tokenId fetch metadata once via [`metadata.md`](metadata.md), cache by `(collection, tokenId)`, and reduce the count to the subset satisfying the trait filter.
4. **Evaluate** the rule expression with a jq recursive function over the per-wallet holdings JSON.

Stages 1, 2, 4 are pure; only stage 3 makes external network calls (IPFS), and even that is cache-friendly.

### Stage 1 — Extract Referenced Collections

```bash
RULE_FILE=rule.json
jq '[.. | objects | select(has("min_count")) | .min_count.collection] | unique' "$RULE_FILE"
```

### Stage 2 — Build Holdings Snapshot per Wallet

For each wallet in the input list, produce a JSON object of the shape:

```json
{
  "0xCOLLECTION_A": ["1", "5", "17"],
  "0xCOLLECTION_B": ["100"]
}
```

For ERC-1155 collections, encode each entry as `"<tokenId>:<balance>"` so the leaf evaluator can match against thresholds correctly.

Use the holdings enumeration patterns from [`ownership.md`](ownership.md) and [`snapshot.md`](snapshot.md). Persist results in `holdings/<wallet>.json` for the duration of the run.

### Stage 3 — Apply Trait Filters

Only invoke this stage if the rule contains any `traits` filter. For each `(collection, tokenId)` referenced by a wallet's holdings AND mentioned in a traits-bearing leaf:

```bash
META=$(./metadata-fetch.sh "$COLLECTION" "$TOKEN_ID")   # see metadata.md
# Compare META.attributes against the traits filter (jq)
```

Cache aggressively keyed by `(collection, tokenId)`; metadata is immutable for normal collections.

### Stage 4 — Evaluate Rule

The evaluator is a single jq expression that recurses over the rule tree. It receives the rule and the holdings snapshot as inputs and emits `true` / `false` per wallet.

```bash
WALLET=0xUSER
HOLDINGS_FILE="holdings/${WALLET}.json"
RULE_FILE=rule.json

jq -n --slurpfile rule "$RULE_FILE" --slurpfile holdings "$HOLDINGS_FILE" '
  def evalRule(r; h):
    if r | has("all_of") then
      (r.all_of | all(evalRule(.; h)))
    elif r | has("any_of") then
      (r.any_of | any(evalRule(.; h)))
    elif r | has("none_of") then
      (r.none_of | all(evalRule(.; h)) | not)
    elif r | has("min_count") then
      (h[r.min_count.collection] // [])
      | length >= r.min_count.n
    else
      error("invalid rule node: \(r | keys)")
    end;
  evalRule($rule[0]; $holdings[0])
'
```

For ERC-1155 with `balance` semantics, replace `length` with a sum over decoded balances:

```jq
... 
elif r | has("min_count") then
  (h[r.min_count.collection] // [])
  | map(if type == "string" and contains(":") then split(":")[1] | tonumber else 1 end)
  | add // 0
  >= r.min_count.n
end;
```

When trait filters are present, pre-filter the per-collection tokenId list before invoking the evaluator, so the rule itself stays trait-agnostic. This keeps the jq expression small and predictable.

---

## Batch Eligibility Driver Script

Combine the four stages into one driver. The runtime cost is dominated by stage 2 (RPC batching) and stage 3 (metadata fetches).

```bash
#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR=~/.claude/skills/pharos-nft-skill
NET=${NET:-atlantic-testnet}
RULE_FILE=${1:?usage: $0 rule.json wallets.txt}
WALLETS_FILE=${2:?usage: $0 rule.json wallets.txt}

RPC=$(jq -r --arg n "$NET" '.networks[] | select(.name==$n) | .rpcUrl' "$SKILL_DIR/assets/networks.json")
MC3=$(jq -r --arg n "$NET" '.deployedOn[$n]' "$SKILL_DIR/assets/multicall.json")
COLLECTIONS=$(jq -c '[.. | objects | select(has("min_count")) | .min_count.collection] | unique' "$RULE_FILE")

# Stage 2: For each wallet, fetch holdings for every collection referenced in the rule.
# (Pseudocode; the actual loop calls ownership.md and snapshot.md primitives per wallet × collection.)

# Stage 3: (Skipped if no traits filter anywhere in the rule.)

# Stage 4: Evaluate per wallet.
while IFS= read -r WALLET; do
  RESULT=$(jq -n --slurpfile rule "$RULE_FILE" --slurpfile h "holdings/${WALLET}.json" '
    def evalRule(r; h):
      if r | has("all_of") then (r.all_of | all(evalRule(.; h)))
      elif r | has("any_of") then (r.any_of | any(evalRule(.; h)))
      elif r | has("none_of") then (r.none_of | all(evalRule(.; h)) | not)
      elif r | has("min_count") then ((h[r.min_count.collection] // []) | length >= r.min_count.n)
      else error("invalid rule node") end;
    evalRule($rule[0]; $h[0])
  ')
  echo "$WALLET $RESULT"
done < "$WALLETS_FILE"
```

Persist `holdings/<wallet>.json` files so re-runs of the same rule against the same wallet set are nearly free.

### Error Handling

| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `invalid rule node` | Rule has a key not in `all_of` / `any_of` / `none_of` / `min_count` | Surface the offending node to the user |
| Missing collection in holdings snapshot | A wallet's holdings file omits a collection mentioned in the rule | Treat as empty (eligible only if `n == 0`); never silently pass |
| Metadata fetch failure | All IPFS gateways timed out for a tokenId that needs a traits filter | Mark the trait check as `false` for that tokenId, log a warning, continue |
| jq parse error | Malformed rule JSON | Pretty-print the rule and ask the user to confirm before retry |

### Agent Guidelines

> Always **dry-run** the rule against a single known-good wallet before the full batch — surface that one wallet's evaluation trace ("Founder leaf: true, Blacklist leaf: false → all_of: true"). Only then proceed to the full batch. After completion, present three counts: total wallets, eligible count, ineligible count, plus a 10-row preview of each bucket. Offer to dump the full lists as CSV.

---

## Worked Example — Pharos Atlantic Testnet

Assume `rule.json` is the full example from above, and `wallets.txt` has 1,000 addresses one per line.

```bash
SKILL_DIR=~/.claude/skills/pharos-nft-skill
NET=atlantic-testnet

# Sanity check the rule before doing anything else
jq '.' rule.json

# Inspect referenced collections
jq '[.. | objects | select(has("min_count")) | .min_count.collection] | unique' rule.json

# Run the driver
bash batch-eligibility.sh rule.json wallets.txt | tee results.tsv

# Summarize
awk '{print $2}' results.tsv | sort | uniq -c
```

The expected output is two lines: `N true` / `M false`. From there, `awk '$2=="true" {print $1}' results.tsv > eligible.txt` extracts the eligible wallet list for downstream use (airdrop tooling, gated dApp config).

### Agent Guidelines

> Eligibility runs are the most common multi-wallet workflow on this skill, so format the final report well. Always include: rule summary (one English sentence), eligible cardinality, ineligible cardinality, the snapshot block, the network, and total elapsed time. Make the result file path explicit so the user knows where to find downstream-ready data.
