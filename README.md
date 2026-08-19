# DeepSeek Harness（dsh）

> 本 README 由 AI 在探索本仓库后整理的中文版项目说明。官方双语内容见 [README.zh.md](README.zh.md)（中文）与 `README.i18n.yaml`（i18n 配置）。

DeepSeek Harness（`dsh`）是 [DeepSeek AI](https://deepseek.com) 开发的开源 **agent harness（智能体框架）**。

核心设计：**一切皆插件（everything is a plugin）**，由 [Cordis](https://github.com/cordiverse/cordis) 驱动。Cordis 的设计见论文 [_A Programming Paradigm for Spatiotemporal Composability_](https://github.com/cordiverse/paper)。

> ⚠️ **开发者预览阶段**：正在快速迭代，未来会出现破坏兼容性的变更。

---

## 1. 项目是什么

- 一个可自举的智能体运行框架：会话、系统提示词、工具、agent 循环、模型适配全部以插件形式存在，**没有需要打补丁的"特权核心"**。
- 扩展方式：在 Cordis 上下文（`ctx`）旁边挂载插件；插件通过 `ctx.effect()` / `ctx.on()` / `ctx.waterfall()` 注册能力，卸载时自动回滚。
- 产物形态：Web UI（默认 `http://127.0.0.1:3080`）、headless 一次性执行、ACP 自动化服务器、JSON-RPC SDK、Python SDK。

## 2. 技术架构要点

### 2.1 运行时组成（Profile / Bundle）
- **Profile**：按名字存储的插件组合（位于 Harness home），`web`、`headless` 是内置模板；可通过 `--profile` 指定。
- **Bundle**：可安装的 Cordis 配置层（patch 层），可被上层 patch 覆盖。
- 配置：`dsh --profile web --dump-config` 可查看实际启动的插件树；每行配置都可通过 `cordis.patch.yml` 覆盖。配置文件允许 `!!js`（仅限插件 config 与 entry disabled 字段）。

### 2.2 核心包与 `ctx` 服务
| 包 | 职责 | `ctx` 键 |
|---|---|---|
| `core/session` | 追加式 `SessionEvent` 日志 + 内存存储 | `ctx.sessions` |
| `core/system-prompt` | 提示词分节与工具 schema 组装 | `ctx.systemPrompt` |
| `core/tools` | 作用域工具注册表 + 受保护的执行管线 | `ctx.tools` |
| `core/agent` | `Agent` 接口、实时注册表、`agent/*` 事件 | `ctx.agents` |
| `core/agent-loop` | 默认的驱动实现（可替换） | `ctx.agentLoop` |
| `llm/llm` | 消息/流词汇 + 模型适配器接缝 | `ctx.llm` |

### 2.3 事件系统（扩展点）
- **Session 事件**：写入持久日志、可通过 `session/event` 广播；跨重启必须存活的事实用这类。
- **Agent 事件**（`agent/*`）：携带活的 `Agent`（inbox、step、status、request、validation、continuation），用于观察/拦截进行中的工作。
- **能力事件**：在接缝上挂策略与适配器（`fs/*`、`tools/*`、`telemetry/*`）。

### 2.4 Turn 流程
- **step** = 一次模型请求 + 它调用的工具；**turn** = 零个或多个 step。
- 流程：`turn/start → claim 输入 → 组装 prompt/tools → agent/pre-step → step/start → llm/stream → assistant/chunk → tool/call → tools/execute → tool/result → step/end → turn/end`。
- `agent/pre-step`、`agent/request`、`llm/stream`、`tools/*` 是 **waterfall**（监听者必须调用 `next()` 才会继续）；`agent/turn-stopping` 是串行事件，无 `next()`。

### 2.5 Session 日志是唯一真相
- **模型可见 ⟺ 已记录**：任何进入模型请求的内容必须能从会话日志重建；新的模型可见输入必须新增 session 事件（扩展 `SessionEventMap` 并从日志渲染）。
- `deriveMessages()` 从日志投影模型历史；fork、resume、转录、遥测、持久化都源自这条流。

### 2.6 能力接缝（Capability Seam）
- 一个可替换能力 = **Service Definition（接口声明）+ Service Provider（实现）+ Consumer（通常是模型工具）** 三种角色，缺一不可。
- 换一个 Provider 就能改变整个产品行为（例如把 fs/subprocess 指向远程沙箱，Bash/PTY/LSP 一起跟着走）。

## 3. 仓库结构

```
vendor/       vendored Cordis 源码（manifest 与同步流程见 vendor/README.md）
packages/     @deepseek-ai/dsh-<pkg> workspaces，按分组目录组织
  core/       产品 API 主干：session、system-prompt、tools、agent、agent-loop
  api/        远程 BFF 组装 + Typert RPC 网关
  llm/        LLM 能力：Service Definition/Consumer + DeepSeek providers
  shell/       bash 能力；subprocess/ terminal/ fs/ lsp/ skill/ web/ 等同理
  session/    持久化会话：JSONL/SQLite 后端、投影、标题、遥测
  sdk/        JSON-RPC 协议、服务端与 TypeScript 客户端
  acp/        仅自动化的 Agent Client Protocol 服务器
  client/ + host/  Web UI 的浏览器端与网关端
  examples/   演示 bundle；util/ 零依赖工具库
python/       Python SDK 与内置运行时（deepseek-harness-sdk / -runtime-bin）
native/       @deepseek-ai/node-addon-landlock-run 源码
examples/     可运行的 cordis.yml 叶子配置
docs/         架构、生成的目录、事后分析、cookbook
scripts/      仓库门禁与生成器
website/      VitePress 站点（双语 docs 的投影）
.agents/      Agent 工作流与 Agent Notes（笔记，含归档规则）
```

## 4. 运行方式

### 通过 npm 运行
```sh
npx @deepseek-ai/dsh web
```
默认启动 Web UI：`http://127.0.0.1:3080`，详见 [Web UI 指南](docs/user/guide/index.md)。

### 从源码运行
```sh
git clone https://github.com/deepseek-ai/deepseek-harness.git
cd deepseek-harness
pnpm install
pnpm run build
pnpm dsh web
```

### 环境要求
- Node.js `^22.19 || >=24`，pnpm workspaces，ESM（`"type": "module"`）全量启用。
- 真实 API 测试/演示需要 `DEEPSEEK_API_KEY`（root `.env` 或环境变量）。

## 5. 常用命令

```sh
pnpm install            # 安装依赖
pnpm run build          # tsc 产出 lib/types + tsdown 打包运行时
pnpm run test           # vitest 单元测试
pnpm run test:coverage  # CI 覆盖门禁：packages/*/*/src 每文件 100%
pnpm run test:e2e       # 真实 API 测试（无 DEEPSEEK_API_KEY 时自动跳过）
pnpm run test:snapshot  # 无 key 的 ACP/headless 回放比对
pnpm run typecheck      # 类型检查（strict + noImplicitAny）
pnpm run lint           # oxlint
pnpm run duplication    # 跨文件 TS 克隆检测
pnpm run hygiene        # knip + publint + workspace 约束 + NodeNext 消费检查
pnpm run doc-sync       # 文档门禁（VitePress 构建兼作死链检查）
pnpm run demo:cordis    # agent 修改自身运行时（需 key）
pnpm run demo:acp       # ACP 自动化服务器（需 key）
```

## 6. 测试与质量门禁

- `test:coverage`（而非 `test`）是 CI 覆盖门禁，要求 `packages/*/*/src` 每文件 100%。
- 快照测试：每个非平凡的产品可见行为变更，都要在同一个 PR 里带一个真实可运行的 keyless 快照。
- 静态门禁与测试通过 tsconfig `paths` 解析到 `src`（源码平面）；消费构建产物 `lib/` 的门禁单独声明依赖（产物平面）。
- 钩子：非平凡变更必须附 Agent Note（`.agents/notes/`），归档后的笔记视为冻结、不可再改。

## 7. 部署与远程访问（实践记录）

- dsh Web UI 监听 `127.0.0.1:3080`；`packages/client/connection/src/api-request-trust.ts` 中的 `isTrustedApiRequest` 要求 Host 为 loopback 或匹配 `trustedHosts`，否则 `/api/*` 返回 403（防跨站栅栏）。
- 远程访问方案：用 `rewrite-proxy.mjs` 在 3090 端口把请求 Host 改写为 `127.0.0.1:3080`、剥离 `Origin`/`Sec-Fetch-*` 头以绕过栅栏；再将该端口设为 Public。
- 一键云端部署（GitHub Codespaces）的完整手册与脚本维护在 **`dsh-codespace` 仓库**（含部署脚本、devcontainer 钩子、故障排查表）。

## 8. Python SDK

- `deepseek-harness-sdk` / `deepseek-harness-runtime-bin`：以子进程方式驱动 dsh，通过 stdio 上的换行分隔 JSON-RPC 通信。
- SDK 启动匹配的内置运行时，除非显式指定通道；运行时总是要求显式配置。详见 [python/README.md](python/README.md)。

## 9. 社区与支持

- 反馈与 bug：<a href="https://github.com/deepseek-ai/deepseek-harness/discussions">GitHub Discussions</a>
- 插件仓库可添加 [`dsh-plugin`](https://github.com/topics/dsh-plugin) 话题便于被发现
- 中文社区：企微小助手 / 入群问卷 / 微信公众号（见 [README.zh.md](README.zh.md) 二维码）

## 10. 许可证

[MIT](LICENSE)；第三方依赖许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
