# Examples

Sample inputs that demonstrate the eligibility rule DSL described in [`../references/eligibility.md`](../references/eligibility.md).

| File | Demonstrates |
|------|--------------|
| `rule-airdrop-example.json` | Compound `all_of` + `none_of` rule for an airdrop snapshot. |
| `rule-gating-example.json` | Compound `any_of` rule with a nested trait filter (`tier: founder`). |

Both files use placeholder collection addresses (`0x...aaaa`, `0x...bbbb`, `0x...cccc`). Replace with real Pharos collections — for example the demo fixtures from `../assets/fixtures/` — before running.

## Running an Example

```bash
SKILL_DIR=~/.claude/skills/pharos-nft-skill
NET=atlantic-testnet
RPC=$(jq -r --arg n "$NET" '.networks[] | select(.name==$n) | .rpcUrl' "$SKILL_DIR/assets/networks.json")

# Replace the placeholder collection addresses with real ones first
$EDITOR "$SKILL_DIR/examples/rule-airdrop-example.json"

# Provide a candidate wallet list
cat > /tmp/candidates.txt <<EOF
0xWALLET_1
0xWALLET_2
0xWALLET_3
EOF

# Drive the evaluation (see references/eligibility.md for the full pipeline)
bash "$SKILL_DIR/references/eligibility-driver.sh" \
  "$SKILL_DIR/examples/rule-airdrop-example.json" \
  /tmp/candidates.txt
```

The example rules also serve as a documentation reference for the DSL schema. New rules can start by copying one of these and editing the leaf addresses.
