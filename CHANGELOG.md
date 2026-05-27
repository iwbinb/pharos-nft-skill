# Changelog

## 0.1.0 (2026-05-27)

Initial release for the Pharos Agent Center Skill Builder Campaign.

### Added

- `SKILL.md` entry point with frontmatter (name, description, version, requires.anyBins) and Capability Index.
- Five reference files covering the full NFT workflow on Pharos:
  - `references/ownership.md` (standard detection, single ownership, tokenId owner lookup, ERC-1155 balance, Enumerable enumeration, staking-proxy resolution)
  - `references/batch.md` (Multicall3 `aggregate3` patterns, chunking, cross-collection and many-wallet aggregations)
  - `references/snapshot.md` (full collection snapshot, tokenId transfer history, log-scan wallet holdings, wallet diff)
  - `references/eligibility.md` (declarative rule DSL with AND / OR / NOT / count thresholds / trait filters; jq-evaluated pipeline)
  - `references/metadata.md` (tokenURI / uri resolution, IPFS gateway race pool, data URI decoding, trait matching)
- `assets/networks.json`, `assets/multicall.json` (canonical address verified live on Pharos Atlantic testnet), `assets/collections.json` (user registry), `assets/staking-proxies.json` (proxy registry).
- Optional fixture contracts under `assets/fixtures/`: `DemoERC721` (with Enumerable extension) and `DemoERC1155`, plus forge deploy script and a fixture README with deploy + mint runbook.
- `examples/rule-{airdrop,gating}-example.json` showing the DSL schema in practice.
- `tests/` suite (16 tests across lint, jq, and live RPC).
- `README.md`, `SUBMISSION.md` (Discord submission payload), `LICENSE` (MIT-0).

### Fixed (during the testing pass)

- Eligibility DSL evaluator: jq function parameters are *filters*, not values. The original recursive evaluator re-evaluated `r.min_count.n` against whatever `.` was at the pipeline position, which broke every compound rule. Bound `r` and `h` to `$r`/`$h` via `as` so every reference is a stable value. Caught by `tests/jq/01-evaluator.sh`.
- ERC-721 Enumerable fixture: OpenZeppelin v5 requires multi-parent overrides for `_update`, `_increaseBalance`, and `supportsInterface` when combining `ERC721` and `ERC721Enumerable`. Added.
- Multicall3 batch template in `references/ownership.md`: rewrote a broken jq pseudocode snippet and a `printf` pattern that mismatched format placeholders against arguments. Replaced with a clear bash loop.
- ABI signature for `aggregate3` return type: corrected `(((bool,bytes))[])` to `((bool,bytes)[])` in `references/ownership.md`.
- `cast abi-decode` invocation: requires a function-shape signature, not a bare type.
- `cast --to-uint256` / `cast --to-dec` references modernized to subcommand form (`cast to-uint256`, `cast to-dec`).
- Log replay jq pipelines: removed `tonumber` calls on hex-string blockNumber fields (would fail on older cast). Switched to RPC-order trust and provided a hex-to-decimal helper for tokenId display.
- IPFS race helper: replaced macOS-incompatible `md5sum` with a portable fallback that tries `md5sum` first and falls back to `md5`.
