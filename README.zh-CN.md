# pharos-nft-skill

为 Pharos 区块链打造的生产级 NFT 工具包，按 Claude Code / OpenClaw / Codex 的 skill 规范封装。补齐官方 [`pharos-skill-engine`](https://github.com/PharosNetwork/pharos-skill-engine) 唯一未覆盖的大块能力：NFT（ERC-721 与 ERC-1155）。

> 中文版 README，与 [README.md](README.md) 内容对应。所有项目代码、frontmatter、命令模板、commit message 仍以英文为主，仅本文档用中文。

## 这个 Skill 做什么

装好之后，宿主 Agent 立刻具备用自然语言回答 Pharos 链上 NFT 问题的能力，**无需写一行运行时代码**。Skill 本身全部由 Markdown + JSON 配置构成；所有上链动作都通过 Agent 按照模板生成的 Foundry (`cast` / `forge`) 命令完成，并默认走 Multicall3 批处理。

### 能力清单

| 能力 | 底层实现 | 参考文档 |
|---|---|---|
| ERC-165 标准探测（ERC-721 / Enumerable / ERC-1155 / 非标合约） | `cast call supportsInterface` | [ownership.md](references/ownership.md) |
| 单钱包持仓判定（持有 ≥ N 个） | `cast call balanceOf` | [ownership.md](references/ownership.md) |
| tokenId 反查持有人（含 staking-proxy 解析） | `cast call ownerOf` + 代理 resolver | [ownership.md](references/ownership.md) |
| ERC-1155 余额与 `balanceOfBatch` | `cast call balanceOf(address,uint256)` | [ownership.md](references/ownership.md) |
| 钱包持有列表（Enumerable 快速路径） | `tokenOfOwnerByIndex` over Multicall3 | [ownership.md](references/ownership.md) |
| 钱包持有列表（log-scan 兜底路径） | 分块 `eth_getLogs` 扫 Transfer | [snapshot.md](references/snapshot.md) |
| 指定区块的完整持有人快照 | Transfer 事件回放 + holder map | [snapshot.md](references/snapshot.md) |
| 单个 tokenId 完整转账历史 | `eth_getLogs` 按 topic3 过滤 | [snapshot.md](references/snapshot.md) |
| 两个钱包持仓差集 | jq 纯集合运算 | [snapshot.md](references/snapshot.md) |
| Multicall3 批处理原语 | `aggregate3` 模板 + 分片策略 | [batch.md](references/batch.md) |
| **声明式资格规则 DSL**（AND / OR / NOT、数量阈值、trait 过滤） | jq 评估 4 节点规则树 | [eligibility.md](references/eligibility.md) |
| 空投 / 白名单批量资格判定 | 四阶段管线：抽取 → 批量取数 → trait 过滤 → 求值 | [eligibility.md](references/eligibility.md) |
| tokenURI / uri 元数据解析（HTTPS / IPFS 多网关竞速 / data URI） | `cast call` + `curl` gateway pool | [metadata.md](references/metadata.md) |
| 按 EIP-721/1155 metadata 规范做 trait 匹配 | jq attribute 匹配器 | [metadata.md](references/metadata.md) |

### 为什么需要这个 Skill

官方 `pharos-skill-engine` 覆盖 ERC-20 与通用合约交互，**完全没有 NFT 能力**。一个普通 Agent 在没有本 skill 的情况下会有这些问题：

- N 个串行 RPC 调用，没有 Multicall3 批处理
- 漏掉 ERC-165 探测，对非 Enumerable 集合走错路径
- 遇到 CryptoPunks 风格非标合约直接报错
- 看不见 staked / escrowed NFT 的真实持有人
- 没有 "钱包 X 是否符合本次空投资格" 的原语（NFT 场景最高频的多钱包问题）

本 skill 把以上 5 个 gap 全部封死，并且**风格与 `pharos-skill-engine` 完全对齐**（同样的 frontmatter、同样的 5 块章节、同样的 `networks.json` schema），熟悉那个 skill 的 Agent 拿到这个零摩擦上手。

## 安装

按你的 Agent 选对应命令：

| Agent | 安装 |
|---|---|
| Claude Code | `npx skills add https://github.com/iwbinb/pharos-nft-skill -g --yes` |
| OpenClaw | `npx skills add https://github.com/iwbinb/pharos-nft-skill -g --yes` |
| Codex | `npx skills add https://github.com/iwbinb/pharos-nft-skill -g --yes` |

加 `-g` 是全局安装（落到 `~/.agents/skills/` 并 symlink 进各 Agent 的 skill 目录，比如 Claude Code 的 `~/.claude/skills/pharos-nft-skill`）。去掉 `-g` 就装到当前项目的 `./.agents/skills/`，仅本项目可见。

装完之后验证：

| Agent | 验证 |
|---|---|
| Claude Code | 任意新会话里输入 `/skills` |
| OpenClaw | `openclaw skills list` |
| Codex | 会话开头输入 `/skills` |

应该能看到 `pharos-nft-skill` 带绿勾出现在列表里。

## 前置依赖

- **Foundry**（`cast`, `forge`）：`curl -L https://foundry.paradigm.xyz | bash && foundryup`
- **jq** 与 **curl**：macOS / Linux 默认自带

核心只读流程（持有判定、快照、历史、资格、元数据）**全部不需要私钥**。仅当你想部署 `assets/fixtures/` 下的演示合约时才需要。

## 用法示例

装好后直接自然语言对话即可，skill 会在涉及 Pharos NFT 的问题上自动触发：

```text
> 钱包 0xabc...123 在 Pharos 测试网的合约 0xdef...456 里有 NFT 吗？
> 列出 0xdef...456 集合里 0xabc...123 持有的所有 tokenId，带元数据。
> 0xdef...456 集合的 tokenId 42 当前归谁所有？
> 给我 0xdef...456 在区块 22000000 时的完整持有人快照。
> 重建 tokenId 42 在 0xdef...456 的完整转账历史。
> 对比 0xabc...123 与 0xfff...000 的 NFT 持仓差异。
> 用 rule.json 对 candidates.txt 里的钱包跑一遍资格检查。
```

Agent 读 [SKILL.md](SKILL.md) 决定加载哪个 reference 文件，然后基于模板生成 `cast` / `forge` 命令并对 Pharos RPC 执行。

## 项目结构

```
pharos-nft-skill/
├── SKILL.md                        # 入口：frontmatter + capability index
├── assets/
│   ├── networks.json               # Pharos RPC 与 explorer 配置（testnet + mainnet）
│   ├── multicall.json              # Multicall3 canonical 地址（已在 Pharos 实测存活）
│   ├── collections.json            # 用户维护的 NFT 集合注册表
│   ├── staking-proxies.json        # 已知 staking / escrow 合约 + resolver
│   └── fixtures/                   # 可选的 ERC-721 / ERC-1155 演示合约
│       ├── foundry.toml
│       ├── src/
│       │   ├── DemoERC721.sol      # 带 Enumerable 扩展
│       │   └── DemoERC1155.sol
│       ├── script/Deploy.s.sol
│       └── README.md
├── references/                     # 按需懒加载的能力指引
│   ├── ownership.md                # 标准探测 / 持有判定 / owner 反查 / Enumerable 枚举
│   ├── batch.md                    # Multicall3 模板与分片策略
│   ├── snapshot.md                 # 快照 / 历史 / log scan 钱包持有
│   ├── eligibility.md              # 规则 DSL 与四阶段评估管线
│   └── metadata.md                 # tokenURI / IPFS / trait 匹配
├── examples/                       # DSL 示例输入
│   ├── rule-airdrop-example.json
│   └── rule-gating-example.json
├── tests/                          # 自动化测试套件（16 个用例）
│   ├── lint/                       # 风格 + 结构校验
│   ├── jq/                         # DSL 评估器 + 辅助 helper
│   ├── live/                       # 真链 RPC 烟雾测试
│   ├── run.sh
│   └── README.md
├── LICENSE                         # MIT-0
├── CHANGELOG.md
├── README.md                       # 英文版（campaign 提交用）
├── README.zh-CN.md                 # 本文档
└── SUBMISSION.md                   # Discord 提交消息草稿
```

## 设计原则

本 skill 针对在公共 RPC 上大规模跑 NFT workflow 这个场景做了几个有倾向性的选择：

1. **Read-first**：核心能力全部只读。资格判定与空投快照流程不需要私钥即可跑通。
2. **不爬 explorer**：Pharos explorer 有反爬保护，skill 完全靠 RPC + Multicall3 + event log，绝不解析 HTML。
3. **默认 Multicall3**：任何会触发 ≥ 4 次串行 `cast call` 的流程都自动折叠成一次 `aggregate3`，省 wall time 又避开 rate limit。
4. **有界 log scan**：`eth_getLogs` 按 `logScanMaxBlocks`（默认 10000）分片，从不假设无上限。
5. **元数据优雅降级**：IPFS 网关全部超时不影响资格判定结果，元数据按 `null` 处理。
6. **一个 DSL 覆盖所有 eligibility**：4 节点规则 schema（`all_of` / `any_of` / `none_of` / `min_count`）够用空投快照、白名单、gating 全部场景。

## 与 pharos-skill-engine 组合

两个 skill 一起装即可，它们共享：

- 同样的 `networks.json` schema（本 skill 自带一份，可独立工作）
- 同样的 Foundry 工具链
- 同样的写操作 pre-check 模式
- 同样的 reference 章节结构（Command Template → Parameters → Output Parsing → Error Handling → Agent Guidelines）

两个都装好后，Agent 可以处理复合问题，例如 "把 100 USDC 换成 tokenId 42 然后查新持有人"，前半段路由到 `pharos-skill-engine`，后半段路由到 `pharos-nft-skill`，无需用户手动切换。

## 自测

仓库自带测试套件，只依赖 bash / jq / python3 / curl，**不需要 Node、不需要 Foundry、不需要 Solidity 编译器**。详情见 [tests/README.md](tests/README.md)。

```bash
# lint + jq（无需联网）
bash tests/run.sh

# lint + jq + 真链 RPC 烟雾测试（连 Pharos atlantic-testnet）
bash tests/run.sh --with-live
```

三套共 16 个用例：

- **lint**（6）：em/en-dash 禁用、JSON 合法性、frontmatter 结构、markdown 链接、锚点定位、bash -n 句法
- **jq**（4）：15 个 fixture 的 DSL 评估器、8 个 trait-match、holdings-diff、文档与代码一致性
- **live**（6，需 `--with-live`）：RPC 可达、Multicall3 bytecode 存在、`aggregate3([])` 往返、`eth_call balanceOf` 形状、`eth_getLogs` 形状、**手编 `aggregate3` 单子调用**

在第一次跑 jq 套件的时候揪出了 DSL evaluator 一个真实 bug（jq 的 `def f(r; h)` 参数是 filter 不是 value，递归时 `r.min_count.n` 会在错误的 `.` 上重新求值）。修复方法已写进 `references/eligibility.md` 防止再犯。

## 验证 Multicall3 在 Pharos 上活着

本 skill 假设 Multicall3 部署在 canonical 地址 `0xcA11bde05977b3631167028862bE2a173976CA11`，已在 Atlantic 测试网实测过：

```bash
curl -s https://atlantic.dplabs-internal.com \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_getCode","params":["0xcA11bde05977b3631167028862bE2a173976CA11","latest"],"id":1}'
```

`result` 字段非空即代表合约存活。

## License

MIT-0，自由使用、修改、再分发，无需署名。见 [LICENSE](LICENSE)。

## 提交信息

本 skill 为 [Pharos Agent Center - Skill Builder Campaign](https://silken-muskox-24e.notion.site/pharos-agent-center-skill-builder-campaign) 撰写。提交格式见 [SUBMISSION.md](SUBMISSION.md)。
