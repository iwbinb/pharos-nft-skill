# Ownership Operation Instructions

This file contains detailed instructions for all NFT ownership operations on the Pharos chain: standard detection, single-token ownership checks, tokenId-to-owner lookup, ERC-1155 balance checks, wallet-holdings enumeration via the Enumerable extension, and resolution of staking-proxy ownership.

> **Network Configuration**: The `<rpc>` parameter in all commands is read from the corresponding network's `rpcUrl` field in `assets/networks.json`. Defaults to the Atlantic testnet.
>
> **Multicall3 Address**: Read from `assets/multicall.json`. Canonical address `0xcA11bde05977b3631167028862bE2a173976CA11` is deployed on both Pharos networks.

---

## Standard Detection

Determine which NFT standard a contract implements before issuing any ownership call. ERC-165 `supportsInterface(bytes4)` is the source of truth; non-standard collections (CryptoPunks-style) are detected by graceful fallback.

### ERC-165 Interface IDs

| Interface | Selector |
|-----------|----------|
| ERC-721 (`IERC721`) | `0x80ac58cd` |
| ERC-721 Enumerable (`IERC721Enumerable`) | `0x780e9d63` |
| ERC-721 Metadata (`IERC721Metadata`) | `0x5b5e139f` |
| ERC-1155 (`IERC1155`) | `0xd9b67a26` |
| ERC-1155 MetadataURI (`IERC1155MetadataURI`) | `0x0e89341c` |

### Command Template

```bash
cast call <collection> "supportsInterface(bytes4)(bool)" <interfaceId> --rpc-url <rpc>
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<collection>` | string | Yes | NFT contract address |
| `<interfaceId>` | bytes4 | Yes | One of the selectors in the table above |
| `<rpc>` | string | Yes | RPC endpoint URL from `assets/networks.json` |

### Output Parsing

- Returns `true` or `false`.
- A `true` response on `0x80ac58cd` confirms ERC-721. Additionally probe `0x780e9d63` to detect the Enumerable extension.
- A `true` response on `0xd9b67a26` confirms ERC-1155.
- A revert or empty return on `supportsInterface` itself indicates a non-standard contract (predates ERC-165). Fall back to probing for the presence of method selectors directly with `cast code` + `cast 4byte`.

### Error Handling

| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| Empty return value | No contract code at target address | Prompt the user to confirm the collection address is correct |
| `execution reverted` on `supportsInterface` | Contract does not implement ERC-165 | Mark as `NonStandard` and try direct selector probes: `ownerOf(uint256)` for ERC-721-like contracts, `balanceOf(address,uint256)` for ERC-1155-like contracts |

### Agent Guidelines

> When the user provides a collection address for the first time in a session, run standard detection before any other ownership operation. Persist the detected standard in memory for the rest of the session. If the collection is already registered in `assets/collections.json`, trust the `standard` field there and skip detection. Always probe ERC-721 Enumerable separately — many production collections implement ERC-721 but **not** Enumerable, which materially changes the holdings-enumeration strategy (Enumerable path vs log-scan path).

---

## Single Ownership Check

Answer the question "does this wallet own one or more NFTs of this collection?" with a single RPC call.

### Command Template (ERC-721)

```bash
cast call <collection> "balanceOf(address)(uint256)" <wallet> --rpc-url <rpc>
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<collection>` | string | Yes | ERC-721 contract address |
| `<wallet>` | string | Yes | Wallet address to check |
| `<rpc>` | string | Yes | RPC endpoint URL |

### Output Parsing

- Returns a uint256 count of NFTs held.
- `0` means the wallet holds none.
- `>0` means the wallet holds at least that many tokens, but does **not** tell you which tokenIds — use the holdings enumeration commands below for that.

### Error Handling

| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `invalid address` | Bad address format | Prompt user to check the address |
| `execution reverted` | Wallet address `0x0` or contract does not implement ERC-721 | Confirm the wallet is non-zero and re-run standard detection on the collection |

### Agent Guidelines

> Use this command when the user's question is a yes/no membership check ("does Alice hold any PharosPunks?"). If the user asks for a list of specific tokenIds, escalate to the holdings enumeration commands. If the user asks for ERC-1155 balance, use the `balanceOf(address,uint256)` variant in the dedicated section below.

---

## TokenId Owner Lookup

Find the current owner of a specific ERC-721 tokenId.

### Command Template

```bash
cast call <collection> "ownerOf(uint256)(address)" <tokenId> --rpc-url <rpc>
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<collection>` | string | Yes | ERC-721 contract address |
| `<tokenId>` | uint256 | Yes | TokenId, decimal or `0x`-prefixed hex |
| `<rpc>` | string | Yes | RPC endpoint URL |

### Output Parsing

- Returns the owner address (20 bytes, 42-character `0x`-prefixed hex).
- If the address matches an entry in `assets/staking-proxies.json` for the current network, resolve the real beneficial owner via the per-proxy resolver method (see the Staking Proxy Resolution section).

### Error Handling

| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `execution reverted` | TokenId never minted, or was burned (sent to zero) | Inform the user the token does not exist or has been burned |
| Empty return value | Collection contract not present at address | Re-run standard detection |

### Agent Guidelines

> After getting the owner, **always cross-check against `staking-proxies.json`**. If the owner is a known proxy and the user did not explicitly ask for the proxy address, append a clarifying line like: `tokenId N is held in staking proxy 0xPROXY — the beneficial owner is 0xUSER` so the result is actionable for gating/airdrop purposes. Also include block explorer links: tokenId page `<explorerUrl>/token/<collection>?a=<tokenId>` and owner page `<explorerUrl>/address/<owner>`.

---

## ERC-1155 Balance Check

ERC-1155 lets a single contract hold many distinct tokenIds, each with fungible-style balances per holder. The balance call therefore takes both a holder and a tokenId.

### Command Template (single)

```bash
cast call <collection> "balanceOf(address,uint256)(uint256)" <wallet> <tokenId> --rpc-url <rpc>
```

### Command Template (batch — same wallet, multiple tokenIds, or multiple wallets, same tokenId)

ERC-1155 defines a native batch query that takes parallel arrays of accounts and tokenIds.

```bash
cast call <collection> "balanceOfBatch(address[],uint256[])(uint256[])" "[<wallet1>,<wallet2>,...]" "[<tokenId1>,<tokenId2>,...]" --rpc-url <rpc>
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<collection>` | string | Yes | ERC-1155 contract address |
| `<wallet>` / `<wallet[i]>` | string | Yes | Holder address(es) |
| `<tokenId>` / `<tokenId[i]>` | uint256 | Yes | TokenId(s) |
| `<rpc>` | string | Yes | RPC endpoint URL |

For the batch variant, the two arrays must have equal length and are paired index-by-index.

### Output Parsing

- Single: returns a uint256 balance.
- Batch: returns a uint256 array of balances, one per (wallet, tokenId) pair.
- Unlike ERC-721, a balance of `0` is normal and not a revert.

### Error Handling

| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `execution reverted` | Not an ERC-1155 contract | Re-run standard detection |
| `arrays length mismatch` | The two arrays passed to `balanceOfBatch` differ in length | Fix the arrays before retry |

### Agent Guidelines

> Always prefer `balanceOfBatch` when the same operation needs to be repeated across more than two pairs — it is one RPC call instead of N. For cross-collection batches use the Multicall3 pattern in [`batch.md`](batch.md) instead.

---

## Wallet Holdings — Enumerable Path

When the collection implements ERC-721 Enumerable (verify with the standard-detection step), the cheapest way to enumerate a wallet's tokenIds is `tokenOfOwnerByIndex(owner, index)` in a Multicall3 batch.

### Procedure

1. Call `balanceOf(wallet)` to learn the count `N`.
2. Build a Multicall3 `aggregate3` calldata containing N entries, each calling `tokenOfOwnerByIndex(wallet, i)` for `i` in `0..N-1`.
3. Decode the returned uint256 array — those are the tokenIds owned by the wallet.

### Command Template

Step 1 — balance:

```bash
N=$(cast call <collection> "balanceOf(address)(uint256)" <wallet> --rpc-url <rpc>)
```

Step 2 — assemble Multicall3 batch. Use the helper jq snippet to build the `aggregate3` parameter (`(address,bool,bytes)[]`):

```bash
CALLS=$(jq -c -n --arg col "<collection>" --argjson n "$N" '
  [range(0; $n) | {target: $col, allowFailure: false, callData: ("0x2f745c59" + (. * (16^64) | tostring | "0x" + .))}]
')
# Simpler: build the array with `cast abi-encode` per item, joined with seq.
TOKENIDS=()
for i in $(seq 0 $((N-1))); do
  TOKENIDS+=("$(cast call <collection> "tokenOfOwnerByIndex(address,uint256)(uint256)" <wallet> $i --rpc-url <rpc>)")
done
```

The recommended pattern is to invoke Multicall3 via `cast` directly:

```bash
# Encode each tokenOfOwnerByIndex call
CALLDATAS=()
for i in $(seq 0 $((N-1))); do
  CALLDATAS+=("$(cast calldata 'tokenOfOwnerByIndex(address,uint256)' <wallet> $i)")
done

# Build the (address,bool,bytes)[] tuple array
TUPLES=$(printf '(%s,false,%s),' "<collection>" "${CALLDATAS[@]}" | sed 's/.$//')
MC3=$(jq -r --arg n "$NET" '.deployedOn[$n]' assets/multicall.json)

# Call Multicall3
cast call $MC3 "aggregate3((address,bool,bytes)[])(((bool,bytes))[])" "[$TUPLES]" --rpc-url <rpc>
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<collection>` | string | Yes | ERC-721 Enumerable contract |
| `<wallet>` | string | Yes | Wallet to enumerate |
| `<rpc>` | string | Yes | RPC endpoint URL |
| `N` | uint256 | derived | Count from step 1 |

### Output Parsing

The Multicall3 `aggregate3` return is an array of `(bool success, bytes returnData)`. For each entry, the `returnData` is the uint256 tokenId — decode with `cast --to-dec` after stripping leading zeros, or parse the raw bytes.

### Error Handling

| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| `execution reverted` on `tokenOfOwnerByIndex` | Collection does not implement Enumerable, despite earlier detection success | Fall back to the log-scan path in [`snapshot.md`](snapshot.md#wallet-holdings-log-scan-path) |
| Multicall3 partial failure | An individual sub-call reverted (e.g. wallet balance changed mid-flight due to concurrent transfer) | Set `allowFailure: true` in the tuple to get partial results, re-issue failed indices |

### Agent Guidelines

> Use the Enumerable path **only** after standard detection confirms `0x780e9d63`. For collections with thousands of tokens per holder, split the batch into chunks of at most 500 calls to stay under typical RPC `eth_call` gas limits. If `N` is 0, return an empty list immediately without making the batch call.

---

## Wallet Holdings — Log Scan Path

For collections that do **not** implement ERC-721 Enumerable, enumerate a wallet's current holdings by scanning `Transfer` event logs. The full procedure lives in [`snapshot.md`](snapshot.md#wallet-holdings-log-scan-path); this section just links to it for navigation.

---

## Staking Proxy Resolution

Real-world NFTs are often deposited into staking, escrow, or marketplace custody contracts. `ownerOf` then returns the proxy address instead of the user. This breaks naive gating logic. Resolve the real beneficial owner by consulting `assets/staking-proxies.json` and calling the proxy's resolver method.

### Schema (`assets/staking-proxies.json`)

```json
{
  "atlantic-testnet": [
    {
      "address": "0xPROXY",
      "name": "Example Staking Vault",
      "resolver": "stakerOf(uint256)(address)",
      "appliesTo": ["0xCOLLECTION_A", "0xCOLLECTION_B"]
    }
  ]
}
```

`appliesTo` is optional — when absent, the resolver applies to any collection. When present, the resolver only applies when the underlying NFT belongs to one of the listed collections.

### Command Template

```bash
# After ownerOf returned the proxy address
PROXY_INFO=$(jq -r --arg n "$NET" --arg p "<proxyAddress>" '.[$n][] | select(.address == $p)' assets/staking-proxies.json)
RESOLVER=$(echo "$PROXY_INFO" | jq -r '.resolver')

cast call <proxyAddress> "$RESOLVER" <tokenId> --rpc-url <rpc>
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `<proxyAddress>` | string | Yes | The address returned by `ownerOf` that matched a `staking-proxies.json` entry |
| `<tokenId>` | uint256 | Yes | Same tokenId used in the original `ownerOf` call |
| `<rpc>` | string | Yes | RPC endpoint URL |

### Output Parsing

Returns the real beneficial owner address. If the resolver itself reverts, the proxy may not actually be tracking this tokenId — report the raw proxy ownership to the user.

### Error Handling

| Error Signature | Cause | Suggested Action |
|----------------|-------|-----------------|
| Proxy not found in config | `ownerOf` returned an address not in `staking-proxies.json` | Report the raw owner address; offer to append the proxy to `staking-proxies.json` if the user identifies it |
| Resolver reverts | Resolver signature wrong or tokenId not tracked | Inform user; fall back to raw proxy ownership |

### Agent Guidelines

> Resolution adds one RPC round trip per matched tokenId. For batch eligibility flows ([`eligibility.md`](eligibility.md)) this can be material — batch the resolver calls through Multicall3 instead of looping serially. After resolution succeeds, always display both the proxy and the real owner so the user understands the chain of custody.

---

## End-to-End Example — Atlantic Testnet

The following session shows a complete read-only ownership flow against the Pharos Atlantic testnet. Run from the skill's installation directory.

```bash
SKILL_DIR=~/.claude/skills/pharos-nft-skill
NET=atlantic-testnet
RPC=$(jq -r --arg n "$NET" '.networks[] | select(.name==$n) | .rpcUrl' "$SKILL_DIR/assets/networks.json")
COLLECTION=0xYourCollectionAddressHere
WALLET=0xYourWalletAddressHere

# 1. Detect standard
cast call "$COLLECTION" "supportsInterface(bytes4)(bool)" 0x80ac58cd --rpc-url "$RPC"  # ERC-721
cast call "$COLLECTION" "supportsInterface(bytes4)(bool)" 0x780e9d63 --rpc-url "$RPC"  # Enumerable

# 2. Single ownership check
cast call "$COLLECTION" "balanceOf(address)(uint256)" "$WALLET" --rpc-url "$RPC"

# 3. Lookup owner of tokenId 1
cast call "$COLLECTION" "ownerOf(uint256)(address)" 1 --rpc-url "$RPC"
```
