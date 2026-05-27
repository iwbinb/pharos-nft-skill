# pharos-nft-skill test suite

This directory contains the project's automated test suite. The skill itself is documentation, so the tests focus on:

1. **Lint**: structural and stylistic invariants the project must hold.
2. **jq**: the eligibility-DSL evaluator and ancillary jq helpers.
3. **Live (optional)**: live RPC smoke tests against Pharos Atlantic testnet.

## Running

From the repo root:

```bash
# Lint + jq (no network required)
bash tests/run.sh

# Lint + jq + live RPC against Pharos Atlantic testnet
bash tests/run.sh --with-live

# Just one suite
bash tests/run.sh --only lint
bash tests/run.sh --only jq
bash tests/run.sh --only live    # implies --with-live for the live suite
```

The runner prints per-test pass/fail and a final tally. On failure it surfaces the offending output. Per-suite logs land in `tests/_out/`.

## Lint suite

| Test | What it checks |
|------|----------------|
| `00-no-dashes.sh` | No em-dash (U+2014) or en-dash (U+2013) anywhere in tracked text files. House style. |
| `01-json-valid.sh` | Every `.json` file parses cleanly with `jq`. |
| `02-frontmatter.sh` | `SKILL.md` has a `---`-fenced YAML frontmatter with `name`, `description` (folded scalar, length 400 chars), `version`, and `requires.anyBins` listing `cast`, `forge`, `jq`, `curl`. |
| `03-md-links.sh` | Every relative `[text](path)` markdown link resolves to a real file. |
| `04-anchors.sh` | Every `[text](file.md#anchor)` anchor maps to a real heading in the target file (GitHub-style slugification). |
| `05-bash-syntax.sh` | Every fenced ` ```bash ` / ` ```sh ` block passes `bash -n` after substituting `<placeholder>` tokens with safe identifiers. Blocks tagged `# skip-lint` on the first line are exempt. |

## jq suite

| Test | What it checks |
|------|----------------|
| `01-evaluator.sh` | 15 fixture cases of the eligibility DSL evaluator across 3 holdings (alice, bob, empty) × 5 rules (min_count, AND, OR, NOT, nested). Pins the canonical evaluator implementation. |
| `02-doc-evaluator-matches.sh` | Verifies the documented evaluator in `references/eligibility.md` covers all 4 DSL node types (`all_of`, `any_of`, `none_of`, `min_count`). Catches drift between docs and tested code. |
| `03-trait-match.sh` | 8 fixture cases of the `match_traits` helper from `references/metadata.md` (single trait, AND, array-of-values, missing attrs, vacuous true). |
| `04-holdings-diff.sh` | Validates the holdings-diff jq snippet from `references/snapshot.md` against a fixed `(A, B) -> (onlyA, onlyB, both)` reference. |

## Live suite

Hits Pharos Atlantic testnet. Read-only, no private key required, no transactions sent.

| Test | What it checks |
|------|----------------|
| `00-rpc-reachable.sh` | `eth_blockNumber` returns a plausible block number. |
| `01-multicall3-deployed.sh` | `eth_getCode` on `0xcA11bde05977b3631167028862bE2a173976CA11` returns substantial bytecode containing the `Multicall3` ASCII fingerprint. |
| `02-aggregate3-empty.sh` | `aggregate3([])` returns the canonical empty-array ABI encoding. |
| `03-eth-call-balanceof.sh` | `eth_call balanceOf(address)` against testnet USDC returns a well-formed 32-byte uint256 word. |
| `04-getlogs-window.sh` | `eth_getLogs` accepts a 1000-block window query against USDC filtered on the Transfer topic. |
| `05-aggregate3-real-call.sh` | Hand-encoded `aggregate3` with one sub-call (USDC `balanceOf`) returns `success=true`, validating the tuple-array ABI encoding used throughout `references/batch.md`. |

## Fixtures

`tests/jq/fixtures/` holds JSON inputs for the jq suite:

- `holdings-{alice,bob,empty}.json` — three contrasting per-wallet holdings shapes.
- `rule-{min-count,and,or,none,nested}.json` — five rules of increasing complexity.

These are the canonical examples of the DSL inputs. New rule shapes should be added here with corresponding expected results in `01-evaluator.sh`.

## Adding a test

1. Drop a new script under `tests/lint/`, `tests/jq/`, or `tests/live/`. The runner picks up anything matching `*.sh`.
2. The script must `exit 0` on pass and a non-zero code on fail. Print `PASS: ...` to stdout on success; the runner's per-test log already captures stdout/stderr for failure diagnostics.
3. Make it executable: `chmod +x <path>`.
4. Run `bash tests/run.sh` and confirm the new test appears.

## CI

The suite is intentionally dependency-light: just bash, jq, python3, and curl (all default on macOS and Linux). No Node, no Foundry, no Solidity compiler. The lint and jq suites run in well under a second. The live suite takes 5-15 seconds depending on Pharos testnet latency.

A GitHub Actions workflow that runs `bash tests/run.sh --with-live` on every push is a reasonable next step but not currently included.
