#!/bin/bash
# dsh web 启动入口：dsh 监听 127.0.0.1:3081（上游安全设计禁止 0.0.0.0），
# proxy.mjs（Node http 反代）监听 0.0.0.0:3080 并转发，使容器端口映射对外可用。
# DSH_TRUSTED_HOSTS（空格分隔）追加 --trusted-host，用于远程浏览器 /api 信任围栏。
# DSH_ALLOW_REMOTE_SETTINGS=1（且 Host 在白名单内）时允许远程访问 settings/credentials 域。
set -e

ARGS=(web --host 127.0.0.1 --port 3081)
if [ -n "${DSH_TRUSTED_HOSTS:-}" ]; then
  for h in $DSH_TRUSTED_HOSTS; do
    ARGS+=(--trusted-host "$h")
  done
fi

dsh "${ARGS[@]}" &
NODE_PID=$!
node /proxy.mjs &
PROXY_PID=$!

trap 'kill "$NODE_PID" "$PROXY_PID" 2>/dev/null' EXIT INT TERM
wait -n "$NODE_PID" "$PROXY_PID"
