#!/bin/bash
# dsh web 启动入口：dsh 监听 127.0.0.1:3081（上游安全设计禁止 0.0.0.0），
# socat 把 0.0.0.0:3080 转发到 127.0.0.1:3081，使容器端口映射对外可用。
# DSH_TRUSTED_HOSTS（空格分隔）追加 --trusted-host，用于远程浏览器 /api 信任围栏。
set -e

ARGS=(web --host 127.0.0.1 --port 3081)
if [ -n "${DSH_TRUSTED_HOSTS:-}" ]; then
  for h in $DSH_TRUSTED_HOSTS; do
    ARGS+=(--trusted-host "$h")
  done
fi

node /app/apps/cli/lib/bin.js "${ARGS[@]}" &
NODE_PID=$!
socat TCP-LISTEN:3080,fork,reuseaddr TCP:127.0.0.1:3081 &
SOCAT_PID=$!

trap 'kill "$NODE_PID" "$SOCAT_PID" 2>/dev/null' EXIT INT TERM
wait -n "$NODE_PID" "$SOCAT_PID"
