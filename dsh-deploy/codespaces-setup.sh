#!/usr/bin/env bash
# GitHub Codespaces 一键部署 dsh：bash codespaces-setup.sh sk-你的key
# 需要网络正常（Codespace 本身可访问 GitHub / npm / nodesource）
set -euo pipefail

API_KEY="${1:-${DEEPSEEK_API_KEY:-}}"
if [[ -z "$API_KEY" ]]; then
  echo "用法: bash codespaces-setup.sh sk-你的key" >&2
  exit 1
fi

TARGET="$(pwd)"

# 1. 基础工具
echo "==> 安装基础工具 (bubblewrap/git/curl)"
sudo apt-get update -y
sudo apt-get install -y bubblewrap git curl

# 2. Node 24 + pnpm
if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 24 ]]; then
  echo "==> 安装 Node 24"
  curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
corepack enable pnpm 2>/dev/null || npm install -g pnpm

# 3. 克隆 + 搬移 + 构建（约 10-20 分钟）
echo "==> 克隆 deepseek-harness 并构建（约 10-20 分钟）"
git clone --depth 1 https://github.com/deepseek-ai/deepseek-harness.git /tmp/dsh-src
shopt -s dotglob
cp -a /tmp/dsh-src/. "$TARGET/"
shopt -u dotglob
rm -rf /tmp/dsh-src
cd "$TARGET"
pnpm install
pnpm run build

# 4. 重写代理
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/rewrite-proxy.mjs" ]]; then
  cp "$SCRIPT_DIR/rewrite-proxy.mjs" "$TARGET/rewrite-proxy.mjs"
  echo "==> 重写代理已就位"
fi

# 5. API key（.env + ~/.dsh/.credentials.yaml，后者优先级更高）
umask 077
printf 'DEEPSEEK_API_KEY=%s\n' "$API_KEY" > .env
mkdir -p "$HOME/.dsh"
printf 'DEEPSEEK_API_KEY: %s\n' "$API_KEY" > "$HOME/.dsh/.credentials.yaml"
chmod 600 "$HOME/.dsh/.credentials.yaml"

# 6. 启动
echo "==> 启动 dsh web + 重写代理"
nohup node apps/cli/lib/bin.js web >/tmp/dsh-web.log 2>&1 &
nohup node rewrite-proxy.mjs >/tmp/dsh-proxy.log 2>&1 &
sleep 6

if curl -s -o /dev/null http://127.0.0.1:3080/ && curl -s -o /dev/null http://127.0.0.1:3090/; then
  echo "==> dsh web(3080) 与 重写代理(3090) 均已运行"
else
  echo "==> 警告: 服务未就绪，查看日志: tail -20 /tmp/dsh-web.log /tmp/dsh-proxy.log" >&2
fi

echo
echo "=============================================================="
echo "完成！最后一步（在 VS Code 界面操作）："
echo "  1. 底部 Ports 面板找到 3090 端口"
echo "  2. 右键 → Port Visibility → Public"
echo "  3. 复制形如 https://xxx-xxx-3090.app.github.dev 的地址"
echo "  4. 浏览器打开即可（手机电脑都能用）"
echo "重启进程: bash start.sh   |   日志: tail -f /tmp/dsh-web.log"
echo "=============================================================="
