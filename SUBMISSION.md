# Discord Submission Payload

Per the campaign rules ("submission details need to be in one message as a whole"), the following block is what to paste into `#skill-submission` on the Pharos Discord. All fields are filled in for `pharos-nft-skill`.

---

**Skill name**: pharos-nft-skill

**Short description**: Production-grade NFT (ERC-721 + ERC-1155) toolkit for Pharos. Adds the one major capability the official pharos-skill-engine does not cover: NFTs. Provides ownership checks, holder snapshots, transfer history, wallet diffs, and a declarative eligibility rule DSL (AND / OR / NOT, count thresholds, trait filters) for airdrops and gating. All workflows are Multicall3-batched and read-only by default. Composes with pharos-skill-engine.

**GitHub link**: https://github.com/<YOUR-GH-USERNAME>/pharos-nft-skill

**Email Address**: iwbinb@icloud.com

**Demo link / video / screenshots**: See README.md and references/*.md for end-to-end examples. A walkthrough video is included at /docs/demo.mp4 in the repo (record after deploying fixtures to Atlantic testnet).

**Instructions on how to use the Skill**:
1. Install Foundry: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
2. Install the skill: `npx skills add https://github.com/<YOUR-GH-USERNAME>/pharos-nft-skill`
3. Verify in Claude Code: type `/skills`: `pharos-nft-skill` should appear with a green checkmark
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

1. Replace `<YOUR-GH-USERNAME>` with the actual GitHub org / user where the repo is pushed.
2. Replace the demo video reference with a real link (Loom, YouTube unlisted, or repo-hosted MP4) **after recording**.
3. Paste the entire payload above (between the two `---` lines) as ONE message in `#skill-submission` on https://discord.com/invite/pharos.
4. Do not split across multiple messages: the campaign rules require a single message.

## Optional: PR to PharosNetwork/pharos-skill-engine

The two skills compose naturally. After Discord submission, consider opening a PR to https://github.com/PharosNetwork/pharos-skill-engine that adds an "Adjacent Skills" section in their README pointing to this repo. That maximizes discoverability and shows good citizenship to the campaign reviewers.
