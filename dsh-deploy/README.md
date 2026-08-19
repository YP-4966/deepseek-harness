# dsh VPS 部署包

把 DeepSeek Harness（dsh）部署到一台有公网 IP 的 Linux 服务器（Ubuntu 22.04 / 24.04），任何设备通过固定网址访问。

> 📌 **本目录与 `YP-4966/dsh-codespace` 仓库的关系**：本目录（`dsh-deploy/`）是部署脚本的**归档副本**；GitHub Codespaces 部署的**权威版本**在 [`YP-4966/dsh-codespace`](https://github.com/YP-4966/dsh-codespace) 仓库（含 `.devcontainer/`、最新版 `codespaces-setup.sh` 等）。两者角色不同、需要同时存在，具体分工与同步流程见 [dsh-codespace/SYNC.md](https://github.com/YP-4966/dsh-codespace/blob/main/SYNC.md)。

## 目录结构

```
dsh-deploy/
├── deploy.sh                 # 一键部署脚本（主入口）
├── rewrite-proxy.mjs         # 重写代理：绕过 dsh 的 loopback 信任栅栏（必需）
├── systemd/
│   ├── dsh-web.service       # dsh web 服务（3080）
│   └── dsh-proxy.service     # 重写代理服务（3090）
└── caddy/
    └── Caddyfile.template    # 反代 + 自动 HTTPS（参考）
```

## 架构

```
浏览器(任何设备) → https://你的域名 → Caddy(自动 HTTPS)
  → 127.0.0.1:3090 rewrite-proxy → 127.0.0.1:3080 dsh web
```

重写代理必须存在：dsh 的 `/api` 有防 DNS 重绑定/跨站安全栅栏，只信任 loopback 来源，远程访问 `host.describe` 等特权方法会 403；重写代理把公网请求伪装成本地回环来源放行（沙箱中已验证）。

## 使用步骤

1. **准备**：一台 Ubuntu 22.04/24.04 服务器（2 核 2G 起步即可），一个域名解析到它的公网 IP
2. **上传**：把整个 `dsh-deploy/` 目录传到服务器（如 `/root/dsh-deploy/`）
3. **执行**（root）：

```bash
DOMAIN=dsh.example.com API_KEY=sk-xxx bash /root/dsh-deploy/deploy.sh
```

   不传环境变量时会交互式询问域名、API key；可选 `AUTH_USER`/`AUTH_PASS` 加密码保护。

4. **验证**：浏览器打开 `https://你的域名`。首次 HTTPS 证书签发可能需 1-2 分钟。

## 说明与提醒

- **密码保护强烈建议**：dsh 本身没有登录认证，公开后任何人知道地址都能消耗你的 API key 余额。用 `AUTH_USER`/`AUTH_PASS` 环境变量或在 Caddyfile 里配置 `basic_auth`
- **bash 工具**：脚本已安装 `bubblewrap`，VPS 上 agent 的 bash 工具可正常执行（沙箱里不可用只是宿主机限制）
- **API key 位置**：脚本同时写入 `/opt/dsh/.env` 和 `~/.dsh/.credentials.yaml`（后者优先级更高，避免漏配）
- **升级**：`cd /opt/dsh && git pull && pnpm install && pnpm run build && systemctl restart dsh-web`
- **换域名/改密码**：编辑 `/etc/caddy/Caddyfile` 后 `systemctl reload caddy`
