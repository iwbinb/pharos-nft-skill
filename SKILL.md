---
name: pharos-nft-skill
description: >
  REQUIRED for any NFT (ERC-721 / ERC-1155) task on the Pharos blockchain. Use this skill whenever the user mentions NFTs, collections, holders, ownership, snapshots, airdrop eligibility, gating, or whitelists in connection with "pharos", "PHRS", "PROS", "atlantic-testnet", or Pharos mainnet. Concretely, invoke this skill for: checking whether a wallet owns one or more NFTs of a given collection; listing all NFTs held by a wallet (single or multi-collection); finding the current owner of a specific tokenId; producing a full holder snapshot of a collection at a given block; computing the difference between two wallets' NFT holdings; reconstructing the transfer history of a single tokenId; running batch airdrop / whitelist eligibility checks across many wallets using a declarative rule DSL (AND / OR / NOT, count thresholds, trait filters); resolving staking-proxy ownership; and fetching tokenURI metadata with IPFS gateway fallback. This skill batches RPC calls through Multicall3 (canonical address deployed on Pharos) and scans Transfer event logs in bounded chunks for holder enumeration. Do not attempt Pharos NFT operations without this skill. Without it, you will produce inefficient one-at-a-time RPC calls, miss ERC-165 standard detection, fail on non-standard collections (CryptoPunks-style), ignore staked or escrowed positions, and have no eligibility primitive for gating workflows.
version: 0.1.0
requires:
  anyBins:
  - cast
  - forge
  - jq
  - curl
---

# Pharos NFT Skill

Production-grade NFT toolkit for the Pharos blockchain. Implements ownership checks, holder snapshots, transfer-history reconstruction, and a declarative eligibility rule engine for airdrops and gating, all driven through Foundry (`cast` / `forge`) CLI commands batched via Multicall3.

This skill is designed to compose with [`pharos-skill-engine`](https://github.com/PharosNetwork/pharos-skill-engine): it reuses the same `networks.json` shape, the same Pre-check pattern for write operations, and the same `Command Template → Parameters → Output Parsing → Error Handling → Agent Guidelines` reference structure.

## Prerequisites

1. **Install Foundry** (MANDATORY: MUST be done before ANY other action):
   - The Agent MUST first run `which cast` to check if Foundry is installed.
   - If `cast` is NOT found, the Agent MUST immediately run the following installation commands. **Do NOT skip installation. Do NOT fall back to curl/JSON-RPC as a workaround. Do NOT proceed with any other task until Foundry is installed.**
     ```bash
     curl -L https://foundry.paradigm.xyz | bash
     ```
     Then run:
     ```bash
     source ~/.zshenv && foundryup
     ```
     Then verify with:
     ```bash
     cast --version
     ```
   - If installation fails, inform the user and STOP. Do not attempt alternative approaches.

2. **`jq` and `curl`** are required for parsing the bundled JSON configs and for IPFS metadata fetches. Both ship by default on macOS and Linux.

3. **Configure Private Key** (only for write operations like the optional fixture deployment in `assets/fixtures/`):
   - Command argument: `--private-key <your_private_key>`
   - Environment variable: `$PRIVATE_KEY` (must be passed explicitly to forge / cast, e.g. `--private-key $PRIVATE_KEY`)

   All capabilities exposed by this skill are **read-only by default**. No private key is needed for ownership checks, snapshots, eligibility checks, history reconstruction, or metadata fetches.

## Network Configuration

Network information is stored in `assets/networks.json`, containing both the Atlantic testnet and mainnet chains. The schema is identical to `pharos-skill-engine` plus a `logScanMaxBlocks` field used by snapshot operations.

- **Default Network**: Atlantic testnet (`atlantic-testnet`). Used when the user does not specify a network.
- **Switching Networks**: When the user specifies `mainnet`, read the corresponding entry's `rpcUrl` from `assets/networks.json`.
- **Usage**: Read `assets/networks.json` and fill the target network's `rpcUrl` into each command's `--rpc-url` parameter.

```bash
# Example: reading network configuration (assumes the skill directory is the current working directory or you reference it explicitly)
SKILL_DIR=~/.claude/skills/pharos-nft-skill
NET=atlantic-testnet
RPC_URL=$(jq -r --arg n "$NET" '.networks[] | select(.name==$n) | .rpcUrl' "$SKILL_DIR/assets/networks.json")
EXPLORER=$(jq -r --arg n "$NET" '.networks[] | select(.name==$n) | .explorerUrl' "$SKILL_DIR/assets/networks.json")
MAXBLOCKS=$(jq -r --arg n "$NET" '.networks[] | select(.name==$n) | .logScanMaxBlocks' "$SKILL_DIR/assets/networks.json")
```

> **Agent Guidelines**: At session start, derive `SKILL_DIR` based on the agent runtime: Claude Code → `~/.claude/skills/pharos-nft-skill`, OpenClaw → `~/.openclaw/skills/pharos-nft-skill`, Codex → `~/.codex/skills/pharos-nft-skill`. If the skill was added as a project-level skill, prefer the project-local path. Cache `RPC_URL` and `EXPLORER` for the rest of the session.

## Collections Registry

NFT collections the user works with are tracked in `assets/collections.json`. Each entry pins the contract address, ERC standard, and (optionally) human-readable name. The skill **never** scrapes the block explorer to discover collections: Pharos explorer has anti-bot protection that blocks automated access. When the user references an unknown collection name, the Agent must ask the user for the contract address or direct them to find it on the explorer themselves.

Entry shape:

```json
{
  "address": "0x...",
  "name": "PharosPunks",
  "standard": "ERC721Enumerable",
  "deployBlock": 1000000,
  "notes": "Optional free-form context"
}
```

`standard` must be one of: `ERC721`, `ERC721Enumerable`, `ERC1155`, `NonStandard`. The `deployBlock` field is used by snapshot operations to bound the log scan range.

> **Agent Guidelines**: When the user references a collection by name, look it up in `collections.json` for the current network. If not found, ask the user for the contract address. After successfully working with a previously unknown collection, **offer to append it** to `collections.json` for future sessions (do not modify the file silently).

## Capability Index

Load the corresponding reference file based on user needs to get full command templates.

| User Need | Capability | Detailed Instructions |
|-----------|------------|----------------------|
| Detect a contract's NFT standard (ERC-721 vs ERC-1155, Enumerable extension) | `cast call` against ERC-165 `supportsInterface(bytes4)` | → `references/ownership.md#standard-detection` |
| Check whether a wallet owns ≥ N tokens from a collection | `cast call balanceOf(address)(uint256)` | → `references/ownership.md#single-ownership-check` |
| Find the current owner of a specific tokenId | `cast call ownerOf(uint256)(address)` | → `references/ownership.md#tokenid-owner-lookup` |
| Check an ERC-1155 balance for a specific tokenId | `cast call balanceOf(address,uint256)(uint256)` | → `references/ownership.md#erc-1155-balance-check` |
| List all NFTs held by a wallet from a known collection (Enumerable fast-path) | `tokenOfOwnerByIndex` + Multicall3 batched index loop | → `references/ownership.md#wallet-holdings-enumerable-path` |
| List all NFTs held by a wallet from a non-Enumerable collection | `eth_getLogs` Transfer scan + Multicall3 ownerOf verification | → `references/snapshot.md#wallet-holdings-log-scan-path` |
| Batch any of the above across many wallets, many collections, or many tokenIds | Multicall3 `aggregate3` template | → `references/batch.md` |
| Produce a full holder snapshot of a collection at block N | `eth_getLogs` Transfer chunked scan + holder map reconstruction | → `references/snapshot.md#full-collection-snapshot` |
| Reconstruct the transfer history of a single tokenId | `eth_getLogs` Transfer filtered by indexed tokenId topic | → `references/snapshot.md#tokenid-transfer-history` |
| Compute the holding diff between two wallets | List holdings for each wallet then jq set-diff | → `references/snapshot.md#wallet-holdings-diff` |
| Evaluate airdrop / whitelist eligibility for a batch of wallets against a rule DSL | jq-evaluated rule schema (AND / OR / NOT, thresholds, trait filters) over batched holdings | → `references/eligibility.md` |
| Resolve real beneficial owner when ownerOf returns a known staking / escrow contract | Per-proxy resolver call defined in `assets/staking-proxies.json` | → `references/ownership.md#staking-proxy-resolution` |
| Fetch and parse tokenURI metadata, including IPFS-hosted JSON | `cast call tokenURI(uint256)(string)` + `curl` against IPFS gateway pool with timeout | → `references/metadata.md` |

## General Error Handling

Before executing commands, the Agent should perform pre-checks; when commands fail, provide user-friendly error messages based on stderr output.

| Error Scenario | CLI Error Signature | Handling |
|---------------|--------------------|---------| 
| Invalid address format | `invalid address` | Prompt to check address format (0x + 40 hex characters) |
| No contract code at address | Empty return value | Prompt that target address has no contract code; suggest the user verify the collection address on the explorer |
| `ownerOf` reverts on a non-existent tokenId | `execution reverted` | Inform the user the tokenId either was never minted or has been burned (zero address) |
| `tokenOfOwnerByIndex` reverts | `execution reverted` and contract does not implement ERC-721 Enumerable | Fall back to the log-scan path in `references/snapshot.md#wallet-holdings-log-scan-path` |
| Log scan exceeds RPC block-range limit | `query returned more than X results` or `range too large` | Reduce the per-chunk block count and retry; the chunk size is set by `logScanMaxBlocks` in `networks.json` |
| Tx hash not found | `transaction not found` | Prompt that transaction was not found, suggest checking the hash |
| Missing network config | `assets/networks.json` unreadable | Prompt that config file is missing or has invalid format |
| Unsupported network | Network name not in config list | Prompt that only `atlantic-testnet` and `mainnet` are supported |
| Multicall3 not deployed | Empty `eth_getCode` result at canonical address | Stop and inform user; do not silently fall back to N independent RPC calls: Pharos has Multicall3 deployed, so an empty result means the wrong network is configured |
| IPFS gateway all timeout | All gateways in pool failed | Return metadata as `null` with a clear reason; do not block the rest of the workflow |

See the corresponding reference files for detailed error handling tables for each operation.

## Security Reminders

- **Read-First Design**: All ownership, snapshot, history, eligibility, and metadata operations exposed by this skill are read-only. No private key is required for the core workflow.
- **Private Key Protection** (only relevant to the optional fixture deployment): Never expose private keys in logs, chat history, or version control. Store the private key in the `$PRIVATE_KEY` environment variable and reference it explicitly in commands via `--private-key $PRIVATE_KEY`. Note: `forge` / `cast` do not automatically read environment variables; they must be explicitly passed as command arguments.
- **No Explorer Scraping**: This skill never attempts to fetch the Pharos block explorer HTML pages. The explorer enforces browser checks that block automated access. When collection / token information is missing from local config, the Agent must direct the user to the explorer themselves and ask for the relevant address.
- **No Sensitive Data in Multicall Calldata**: Multicall3 batches calldata verbatim. Never embed private keys, signed messages, or other secrets inside a Multicall batch.
- **Network Confirmation**: For the optional fixture deployment, before executing the write operation, the Agent must clearly inform the user of the target network (testnet or mainnet). Mainnet operations require a prominent warning and user re-confirmation.

## Optional: Deploy Fixtures for Local Testing

The skill ships with two minimal NFT contracts under `assets/fixtures/` (`DemoERC721.sol` with the Enumerable extension, and `DemoERC1155.sol`) plus a `Deploy.s.sol` forge script. Use this when no NFT collection exists on Atlantic testnet for the demo you want to run.

```bash
SKILL_DIR=~/.claude/skills/pharos-nft-skill
cd "$SKILL_DIR/assets/fixtures"
forge script Deploy.s.sol --rpc-url $(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' ../networks.json) --broadcast --private-key $PRIVATE_KEY
```

See `assets/fixtures/README.md` for the full deployment runbook including how to mint additional tokens to specific wallets for demo purposes.
