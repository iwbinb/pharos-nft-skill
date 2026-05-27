# Discord Submission Payload

Per the campaign rules ("submission details need to be in one message as a whole"), the following block is what to paste into `#skill-submission` on the Pharos Discord. All fields are filled in for `pharos-nft-skill`.

---

**Skill name**: pharos-nft-skill

**Short description**: Production-grade NFT (ERC-721 + ERC-1155) toolkit for Pharos. Adds the one major capability the official pharos-skill-engine does not cover: NFTs. Provides ownership checks, holder snapshots, transfer history, wallet diffs, and a declarative eligibility rule DSL (AND / OR / NOT, count thresholds, trait filters) for airdrops and gating. All workflows are Multicall3-batched and read-only by default. Composes with pharos-skill-engine.

**GitHub link**: https://github.com/iwbinb/pharos-nft-skill

**Email Address**: iwbinb@gmail.com

**Demo link / video / screenshots**: Live evidence committed to the repo under `docs/`:
- `docs/install-and-test.txt`: full transcript of `npx skills add https://github.com/iwbinb/pharos-nft-skill -g --yes` followed by an `ls` of the resulting `~/.claude/skills/pharos-nft-skill/` directory, confirming the skill installs end-to-end into Claude Code's skill registry.
- `docs/test-output.txt`: complete `tests/run.sh --with-live` output run from the installed location, 16/16 passing. Includes lint, jq evaluator, and live Pharos Atlantic testnet RPC checks (Multicall3 deployed at canonical address, `eth_call balanceOf`, `eth_getLogs` window, hand-encoded `aggregate3` with one sub-call).

**Instructions on how to use the Skill**:
1. Install Foundry: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
2. Install the skill globally: `npx skills add https://github.com/iwbinb/pharos-nft-skill -g --yes` (omit `-g` for project-local install)
3. Verify in Claude Code: type `/skills`. `pharos-nft-skill` should appear with a green checkmark
4. Use natural language: "does wallet 0xabc... own any NFTs in collection 0xdef... on Pharos testnet?". The skill triggers automatically on NFT-related Pharos questions and generates the appropriate cast / forge commands.

**Supported framework**: Claude Code, OpenClaw, Codex (any Agent runtime that reads `~/.claude/skills/` or equivalent and supports the SKILL.md frontmatter format used by pharos-skill-engine).

**Additional notes / dependencies**:
- Dependencies: Foundry (`cast`, `forge`), `jq`, `curl`. All listed in `requires.anyBins` in SKILL.md frontmatter
- Multicall3 is assumed to be at the canonical address `0xcA11bde05977b3631167028862bE2a173976CA11`; verified live on Atlantic testnet (eth_getCode returned a non-empty result on May 27, 2026)
- Networks: Atlantic testnet (default) and mainnet; same `networks.json` shape as pharos-skill-engine
- Read-first design: no private key is required for any core workflow (ownership, snapshot, history, eligibility, metadata)
- Optional fixture contracts under `assets/fixtures/` (ERC-721 Enumerable + ERC-1155) for end-to-end testing when no public NFT collection exists on a given network
- License: MIT-0 (matches the upstream pharos-skill-engine license)

---

## How to send

1. GitHub username is already set to `iwbinb`. Adjust if pushing to a different account.
2. Optional: add a Loom or YouTube walkthrough link on top of the committed `docs/` transcripts.
3. Paste the entire payload above (between the two `---` lines) as ONE message in `#skill-submission` on https://discord.com/invite/pharos.
4. Do not split across multiple messages: the campaign rules require a single message.

## Optional: PR to PharosNetwork/pharos-skill-engine

The two skills compose naturally. After Discord submission, consider opening a PR to https://github.com/PharosNetwork/pharos-skill-engine that adds an "Adjacent Skills" section in their README pointing to this repo. That maximizes discoverability and shows good citizenship to the campaign reviewers.
