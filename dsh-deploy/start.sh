#!/usr/bin/env bash
# Codespace 休眠/重建后重新拉起 dsh（每次进来跑一次即可）
cd "$(dirname "$0")"
nohup node apps/cli/lib/bin.js web >/tmp/dsh-web.log 2>&1 &
nohup node rewrite-proxy.mjs >/tmp/dsh-proxy.log 2>&1 &
sleep 3
echo "dsh 已启动；去 Ports 面板把 3090 设为 Public"
