#!/usr/bin/env bash
# One-shot deployment of DeepSeek Harness (dsh) web to a fresh Ubuntu 22.04/24.04 VPS.
# Run as root:  bash deploy.sh
#
# Required inputs (env vars or interactive prompts):
#   DOMAIN     - domain name already resolving to this server, e.g. dsh.example.com
#   API_KEY    - DeepSeek API key (sk-...)
# Optional:
#   AUTH_USER  - basic-auth username (if you want password protection)
#   AUTH_PASS  - basic-auth password
#   APP_DIR    - install location (default /opt/dsh)
set -euo pipefail

DOMAIN="${DOMAIN:-}"
API_KEY="${API_KEY:-}"
AUTH_USER="${AUTH_USER:-}"
AUTH_PASS="${AUTH_PASS:-}"
APP_DIR="${APP_DIR:-/opt/dsh}"
REPO_URL="${REPO_URL:-https://github.com/deepseek-ai/deepseek-harness.git}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: run as root (sudo bash deploy.sh)" >&2
  exit 1
fi

# ---- collect inputs ---------------------------------------------------------
if [[ -z "$DOMAIN" ]]; then
  read -rp "域名（已解析到本机，如 dsh.example.com）: " DOMAIN
fi
if [[ -z "$API_KEY" ]]; then
  read -rsp "DeepSeek API key: " API_KEY; echo
fi
if [[ -z "$AUTH_USER" && -z "$AUTH_PASS" ]]; then
  read -rp "设置访问用户名（直接回车=不设密码保护）: " AUTH_USER
  if [[ -n "$AUTH_USER" ]]; then
    read -rsp "设置访问密码: " AUTH_PASS; echo
  fi
fi

echo "==> 目标域名: $DOMAIN"
echo "==> 安装目录: $APP_DIR"

# ---- system packages --------------------------------------------------------
echo "==> 安装 Node 24 / pnpm / bubblewrap / caddy ..."
apt-get update -y
apt-get install -y curl ca-certificates gnupg apt-transport-https

# Node 24
if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 24 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -y nodejs
fi

# Caddy (stable apt repo)
if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt-get update -y
  apt-get install -y caddy
fi

apt-get install -y bubblewrap apache2-utils # bash tool sandbox + htpasswd for basic auth

corepack enable pnpm || true
if ! command -v pnpm >/dev/null 2>&1; then
  npm install -g pnpm
fi

# ---- build dsh --------------------------------------------------------------
if [[ ! -f "$APP_DIR/package.json" ]]; then
  echo "==> 克隆 deepseek-harness ..."
  git clone --depth 1 "$REPO_URL" "$APP_DIR"
  cd "$APP_DIR"
  echo "==> pnpm install（可能较久）..."
  pnpm install
  echo "==> pnpm run build ..."
  pnpm run build
else
  echo "==> $APP_DIR 已存在，跳过 clone/build（如需重构建请手动执行 pnpm install && pnpm run build）"
fi
cd "$APP_DIR"

# ---- rewrite proxy ----------------------------------------------------------
echo "==> 安装重写代理 ..."
cp "$(dirname "$0")/rewrite-proxy.mjs" "$APP_DIR/rewrite-proxy.mjs"

# ---- API key ----------------------------------------------------------------
echo "==> 写 API key 到 $APP_DIR/.env（含 ~/.dsh credentials 兜底）..."
umask 077
printf 'DEEPSEEK_API_KEY=%s\n' "$API_KEY" > "$APP_DIR/.env"
mkdir -p "$HOME/.dsh"
if [[ -f "$HOME/.dsh/.credentials.yaml" ]] && grep -q 'DEEPSEEK_API_KEY' "$HOME/.dsh/.credentials.yaml" 2>/dev/null; then
  sed -i "s|^DEEPSEEK_API_KEY:.*|DEEPSEEK_API_KEY: $API_KEY|" "$HOME/.dsh/.credentials.yaml"
  chmod 600 "$HOME/.dsh/.credentials.yaml"
else
  printf 'DEEPSEEK_API_KEY: %s\n' "$API_KEY" > "$HOME/.dsh/.credentials.yaml"
  chmod 600 "$HOME/.dsh/.credentials.yaml"
fi

# ---- systemd units ----------------------------------------------------------
echo "==> 安装 systemd 服务 ..."
mkdir -p /etc/systemd/system
cp "$(dirname "$0")/systemd/dsh-web.service" /etc/systemd/system/
cp "$(dirname "$0")/systemd/dsh-proxy.service" /etc/systemd/system/
# fix WorkingDirectory if APP_DIR differs
sed -i "s|/opt/dsh|$APP_DIR|g" /etc/systemd/system/dsh-web.service /etc/systemd/system/dsh-proxy.service
systemctl daemon-reload
systemctl enable --now dsh-proxy dsh-web

sleep 3
if systemctl is-active --quiet dsh-web && systemctl is-active --quiet dsh-proxy; then
  echo "==> dsh-web + dsh-proxy 已运行"
else
  echo "==> 警告: 服务未全部运行，检查: journalctl -u dsh-web -u dsh-proxy -n 50" >&2
fi

# ---- Caddy ---------------------------------------------------------------
echo "==> 配置 Caddy ..."
AUTH_BLOCK=""
if [[ -n "$AUTH_USER" && -n "$AUTH_PASS" ]]; then
  HASH="$(htpasswd -nbB "$AUTH_USER" "$AUTH_PASS" | cut -d: -f2)"
  AUTH_BLOCK="    basic_auth {
        $AUTH_USER $HASH
    }"
fi
cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
$AUTH_BLOCK

    reverse_proxy 127.0.0.1:3090
}
EOF
systemctl enable --now caddy
sleep 3
if systemctl is-active --quiet caddy; then
  echo "==> Caddy 已运行"
else
  echo "==> 警告: Caddy 未运行，检查: journalctl -u caddy -n 50" >&2
fi

# ---- firewall -------------------------------------------------------------
if command -v ufw >/dev/null 2>&1; then
  echo "==> 放行 80/443（ufw）..."
  ufw allow 80/tcp >/dev/null 2>&1 || true
  ufw allow 443/tcp >/dev/null 2>&1 || true
fi

echo
echo "=============================================================="
echo "部署完成。访问: https://$DOMAIN"
echo "确认域名已解析到本机公网 IP；HTTPS 证书由 Caddy 自动签发（首次可能需等 1-2 分钟）。"
echo "服务管理: systemctl status dsh-web dsh-proxy caddy"
echo "日志:     journalctl -u dsh-web -f"
echo "=============================================================="
