# Demo NFT Fixtures

Two minimal NFT contracts useful for end-to-end testing of `pharos-nft-skill` against Pharos Atlantic testnet. They are not required to use the skill (point the skill at any existing collection), but they make for a fully reproducible demo when no public collection exists on a given network.

| Contract | Standard | Purpose |
|----------|----------|---------|
| `DemoERC721` | ERC-721 + Enumerable | Exercises the Enumerable fast path, `ownerOf`, `balanceOf`, `tokenOfOwnerByIndex` |
| `DemoERC1155` | ERC-1155 | Exercises `balanceOf(address,uint256)` and `balanceOfBatch` |

## One-time Setup

```bash
SKILL_DIR=~/.claude/skills/pharos-nft-skill
cd "$SKILL_DIR/assets/fixtures"

# OpenZeppelin contracts (pinned to v5.x compatible with solc 0.8.24)
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# Required by forge std scripts
forge install foundry-rs/forge-std --no-commit

# Compile to verify everything resolves
forge build
```

If `forge install` fails because the directory is not a git repo, run `git init` once inside `assets/fixtures/` first.

## Deploy to Atlantic Testnet

The Atlantic testnet is the default. Mainnet deployments require explicit confirmation per `pharos-skill-engine` conventions.

```bash
export PRIVATE_KEY=0xYOUR_TESTNET_KEY_FUNDED_WITH_PHRS

# Sanity-check derived address
cast wallet address --private-key $PRIVATE_KEY

# Deploy both contracts and mint a handful of tokens to the deployer
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' ../networks.json) \
  --broadcast \
  --private-key $PRIVATE_KEY
```

Note the two contract addresses printed at the end. Append them to `../collections.json`:

```json
{
  "atlantic-testnet": [
    {
      "address": "0xDemoERC721_FROM_LOGS",
      "name": "Pharos Demo 721",
      "standard": "ERC721Enumerable",
      "deployBlock": 22683700,
      "notes": "Demo fixture for pharos-nft-skill"
    },
    {
      "address": "0xDemoERC1155_FROM_LOGS",
      "name": "Pharos Demo 1155",
      "standard": "ERC1155",
      "deployBlock": 22683700
    }
  ]
}
```

Update `deployBlock` with the actual block from the deploy receipt: it's used to bound the log-scan range in snapshot operations.

## Generate Demo Data

After deployment, mint tokens to multiple wallets so eligibility and snapshot demos have something to work with.

```bash
ERC721=0xDemoERC721_FROM_LOGS
ERC1155=0xDemoERC1155_FROM_LOGS
RPC=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' ../networks.json)

# Mint tokenIds 4..8 to a second wallet
cast send "$ERC721" "mint(address)" 0xSECOND_WALLET --rpc-url "$RPC" --private-key $PRIVATE_KEY
cast send "$ERC721" "mint(address)" 0xSECOND_WALLET --rpc-url "$RPC" --private-key $PRIVATE_KEY

# Airdrop ERC-1155 tokenId 3 to a list of wallets
cast send "$ERC1155" "airdrop(address[],uint256,uint256)" \
  "[0xWALLET_A,0xWALLET_B,0xWALLET_C]" 3 1 \
  --rpc-url "$RPC" --private-key $PRIVATE_KEY
```

## Reset

The fixtures are not upgradeable. To start over, deploy fresh instances and replace the addresses in `collections.json`. Old fixture addresses can be safely left in `collections.json`: they simply become inert (zero balances across the board).

## Faucet

Atlantic testnet PHRS is required to deploy. Refer to the Pharos developer docs (`https://www.pharos.xyz`) for the current faucet endpoint and rate limit: the link changes periodically and is not embedded here to avoid documentation drift.

## License

MIT: see the top-level `LICENSE` file.
