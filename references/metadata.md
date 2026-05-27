# NFT Metadata Operation Instructions

This file describes how to fetch and parse the metadata associated with a specific NFT (via `tokenURI(uint256)` for ERC-721 or `uri(uint256)` for ERC-1155), with robust handling of the three common URI schemes (HTTPS, IPFS, data URI) and a multi-gateway race pool for IPFS resolution.

Metadata is consumed by:

- Trait filters in the eligibility DSL ([`eligibility.md`](eligibility.md)).
- User-facing presentation of NFTs in holdings listings.
- Image fetches for downstream rendering (out of scope for this skill: addresses, names, and attributes are enough for gating).

> **No explorer scraping**: This skill never resolves metadata through the Pharos block explorer. All URIs come from on-chain calls to the collection contract itself.

---

## On-Chain URI Lookup

### Command Template (ERC-721)

```bash
cast call <collection> "tokenURI(uint256)(string)" <tokenId> --rpc-url <rpc>
```

### Command Template (ERC-1155)

```bash
cast call <collection> "uri(uint256)(string)" <tokenId> --rpc-url <rpc>
```

ERC-1155 `uri` returns a template string that may contain the substring `{id}`. Per the standard, replace `{id}` with the **lowercased 64-character zero-padded hex** representation of the tokenId before resolving.

```bash
URI_TEMPLATE=$(cast call <collection> "uri(uint256)(string)" <tokenId> --rpc-url <rpc>)
ID_HEX=$(printf '%064x' <tokenId>)
URI=$(echo "$URI_TEMPLATE" | sed "s/{id}/$ID_HEX/g")
```

### Output Parsing

The on-chain string falls into one of three schemes:

| Scheme | Example | Resolution |
|--------|---------|------------|
| HTTPS | `https://meta.example.com/123.json` | `curl --max-time 5 ...` |
| IPFS | `ipfs://bafy.../123.json` or `ipfs://Qm.../123.json` | Multi-gateway race (see below) |
| Data URI | `data:application/json;base64,eyJ...` | Strip prefix, `base64 -d` |

### Error Handling

| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `execution reverted` | TokenId not minted, or contract doesn't implement metadata extension | Re-run standard detection; if metadata extension missing, treat metadata as `null` |
| Empty string | Collection returns blank for unset tokens | Treat as `null` |
| `ipfs://` URI but no `/path` after CID | URI is a directory CID, not a file | Append `/<tokenId>.json` or `/metadata.json` heuristically; if both fail, return `null` |

### Agent Guidelines

> Always normalize the URI to a fully resolved HTTPS URL before fetching. Do not pass `ipfs://` URIs to curl directly. Show the user the resolved gateway URL when reporting metadata so they can verify it independently.

---

## IPFS Gateway Pool

Use a small pool of public IPFS gateways and race them for the first 2xx response. Each gateway gets a short timeout (default 500ms initial, 2s overall). This protects against any single gateway being slow or down.

### Recommended Pool

| Gateway | URL Template | Notes |
|---------|--------------|-------|
| ipfs.io | `https://ipfs.io/ipfs/<cid>/<path>` | Reference gateway, sometimes rate-limited |
| Cloudflare | `https://cloudflare-ipfs.com/ipfs/<cid>/<path>` | Generally fast |
| dweb.link | `https://dweb.link/ipfs/<cid>/<path>` | Protocol Labs operated |
| nftstorage.link | `https://nftstorage.link/ipfs/<cid>/<path>` | Optimized for NFT metadata |
| 4everland | `https://4everland.io/ipfs/<cid>/<path>` | Web3-native gateway |

### Race Implementation

```bash
fetch_ipfs() {
  local URI="$1"   # e.g. ipfs://bafy.../123.json
  local PATH_PART="${URI#ipfs://}"
  local GATEWAYS=(
    "https://ipfs.io/ipfs"
    "https://cloudflare-ipfs.com/ipfs"
    "https://dweb.link/ipfs"
    "https://nftstorage.link/ipfs"
    "https://4everland.io/ipfs"
  )
  local TMP
  TMP=$(mktemp -d)
  local PIDS=()
  for GW in "${GATEWAYS[@]}"; do
    (
      # Use a hash of the gateway name as a unique filename. md5sum is GNU coreutils;
      # md5 is the BSD/macOS equivalent. Try GNU first, fall back to BSD.
      HASH=$(echo "$GW" | { md5sum 2>/dev/null || md5; } | awk '{print $1}' | cut -c1-8)
      curl -fsSL --max-time 2 "$GW/$PATH_PART" -o "$TMP/$HASH.json"
    ) &
    PIDS+=($!)
  done
  # Wait for the first successful file to appear
  local DEADLINE=$(($(date +%s) + 3))
  while [ $(date +%s) -lt $DEADLINE ]; do
    for f in "$TMP"/*.json; do
      if [ -s "$f" ]; then
        cat "$f"
        for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
        rm -rf "$TMP"
        return 0
      fi
    done
    sleep 0.1
  done
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done
  rm -rf "$TMP"
  return 1
}
```

`fetch_ipfs ipfs://bafy.../123.json` prints the JSON body or returns nonzero on full failure.

### Error Handling

| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| All gateways time out | Public IPFS infrastructure unreachable | Return `null` metadata, log a warning, continue the workflow |
| Gateway returns HTML (CAPTCHA / rate-limit page) | Rate-limited | Race other gateways; if all degraded, return `null` |
| Pinned-only CID, public gateways do not have it | Collection used a private pinning service | Surface the URI to the user and stop attempting auto-resolution |

### Agent Guidelines

> Never block a workflow on IPFS: eligibility checks should degrade gracefully when metadata is unavailable. Cache successful fetches keyed by `(collection, tokenId)`; metadata is immutable for well-behaved collections, and re-fetching the same tokenId across an eligibility run wastes wall time.

---

## Data URI Decoding

A common modern pattern is to encode the metadata JSON inline in the contract:

```
data:application/json;base64,eyJuYW1lIjogIkV4YW1wbGUiLCAiYXR0cmlidXRlcyI6IFt7InRyYWl0X3R5cGUiOiAicmFyaXR5IiwgInZhbHVlIjogImxlZ2VuZGFyeSJ9XX0=
```

```bash
URI=$(cast call <collection> "tokenURI(uint256)(string)" <tokenId> --rpc-url <rpc>)
JSON=$(echo "$URI" | sed -E 's|^data:application/json(;[^,]*)?,||' | base64 -d 2>/dev/null || echo "$URI" | sed -E 's|^data:application/json(;[^,]*)?,||')
```

Some contracts also use `data:application/json;utf8,...` (plain text); the same sed strips the prefix and the trailing fallback emits the raw payload without base64 decoding.

### Agent Guidelines

> Inline-data collections do not depend on IPFS at all and are the fastest path to metadata. When detected, skip the IPFS pool entirely.

---

## Standard NFT Metadata JSON

Per [EIP-721 / EIP-1155 metadata extensions](https://eips.ethereum.org/EIPS/eip-721), the resolved JSON typically conforms to:

```json
{
  "name": "Example NFT #1",
  "description": "...",
  "image": "ipfs://...",
  "external_url": "https://...",
  "attributes": [
    { "trait_type": "rarity", "value": "legendary" },
    { "trait_type": "background", "value": "red" }
  ]
}
```

Only `name` and `attributes` are load-bearing for this skill (eligibility traits filter on `attributes`). The other fields are passed through to the user verbatim.

### Trait Match Helper

```bash
# Returns "true" if attributes match every key in $TRAITS (an inline JSON object).
match_traits() {
  local META_JSON="$1"
  local TRAITS_JSON="$2"
  echo "$META_JSON" | jq --argjson traits "$TRAITS_JSON" '
    [.attributes // [] | .[] | {(.trait_type): .value}] | add // {}
    | . as $attrs
    | $traits
    | to_entries
    | all(
        .value as $want
        | $attrs[.key] as $have
        | if ($want | type) == "array"
          then $want | any(. == $have)
          else $want == $have
          end
      )
  '
}
```

### Agent Guidelines

> Trait filters in the eligibility DSL ultimately route through `match_traits`. When the user describes a trait filter in natural language ("only Gold-tier"), confirm the canonical `trait_type` and `value` strings against one sample tokenId's metadata before assuming. Trait names are case-sensitive on most collections.
