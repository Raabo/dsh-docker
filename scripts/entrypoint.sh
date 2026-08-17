#!/bin/bash
# dsh web 启动入口：以 root 启动并修复数据目录属主（bind mount 场景宿主机属主可能不是
# UID 1000），随后降权为 node 用户运行 dsh 与反代。
# dsh 监听 127.0.0.1:3081（上游安全设计禁止 0.0.0.0），proxy.mjs 监听 0.0.0.0:3080 转发。
# DSH_TRUSTED_HOSTS（空格分隔）追加 --trusted-host；DSH_ALLOW_REMOTE_SETTINGS=1 时允许远程设置域。
set -e

# bind mount 权限自修复（幂等；失败不阻塞启动）
chown -R node:node /data/dsh /workspace 2>/dev/null || true

ARGS=(web --host 127.0.0.1 --port 3081)
if [ -n "${DSH_TRUSTED_HOSTS:-}" ]; then
  for h in $DSH_TRUSTED_HOSTS; do
    ARGS+=(--trusted-host "$h")
  done
fi

su node -s /bin/bash -c "dsh ${ARGS[*]}" &
NODE_PID=$!
su node -s /bin/bash -c "node /proxy.mjs" &
PROXY_PID=$!

trap 'kill "$NODE_PID" "$PROXY_PID" 2>/dev/null' EXIT INT TERM
wait -n "$NODE_PID" "$PROXY_PID"
