# syntax=docker/dockerfile:1

# ---------- builder: 源码构建（与上游 CI 一致: node 24 + pnpm 11.7.0） ----------
FROM node:24-bookworm AS builder
ENV PNPM_HOME=/pnpm PATH=/pnpm:$PATH
# 上游 packageManager 字段为 pnpm@11.7.0，锁定一致
RUN npm install -g pnpm@11.7.0 --no-audit --no-fund
WORKDIR /app
COPY . .
# 上游 commit hash 由 workflow 注入（.git 已排除在构建上下文外，build.ts 读不到 git；
# 该值会写进前端构建产物便于溯源，缺省时 build.ts 会报错拒绝构建）
ARG DSH_CLIENT_COMMIT_HASH
ENV DSH_CLIENT_COMMIT_HASH=$DSH_CLIENT_COMMIT_HASH
RUN pnpm install --frozen-lockfile
RUN pnpm run build
# 运行时只需要生产依赖（devDeps 约 700MB 不进镜像）：
# 1. 干净重装 prod（rm 后 install --prod 的 workspace 链接正常；在已有 node_modules 上
#    purge 会丢链接，勿改）
# 2. --ignore-scripts 跳过 root 的 lefthook postinstall（dev 工具）；node-pty 原生模块
#    用全局 node-gyp 补编译（node-gyp 是 devDep，prod 模式不存在）
# 3. subprocess-local 恢复 spawn-helper 可执行位
# 4. .pnpm-store（pnpm 包缓存 ~690MB）在 COPY 前删除，不进镜像
RUN rm -rf node_modules && pnpm install --frozen-lockfile --prod --ignore-scripts \
    && npm install -g node-gyp >/dev/null 2>&1 \
    && cd /app/node_modules/.pnpm/node-pty@*/node_modules/node-pty && node-gyp rebuild >/dev/null \
    && cd /app/packages/subprocess/subprocess-local && node scripts/ensure-spawn-helper.mjs \
    && rm -rf /app/.pnpm-store

# ---------- runtime: 最小运行环境 ----------
FROM node:24-slim AS runtime
ENV NODE_ENV=production \
    DSH_TELEMETRY_DISABLED=1 \
    DSH_HOME=/data/dsh \
    DSH_TRUSTED_HOSTS="" \
    DSH_ALLOW_REMOTE_SETTINGS=0
RUN apt-get update && apt-get install -y --no-install-recommends bash \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app /app
# dsh CLI 入口（源码构建产物 apps/cli/lib/bin.js，tsc 输出默认 644，需补可执行位）
RUN ln -sf /app/apps/cli/lib/bin.js /usr/local/bin/dsh && chmod +x /app/apps/cli/lib/bin.js
COPY scripts/entrypoint.sh /entrypoint.sh
COPY proxy.mjs /proxy.mjs
RUN chmod +x /entrypoint.sh \
    && mkdir -p /data/dsh /workspace && chown -R node:node /data/dsh /workspace
# 以 root 启动（entrypoint 内修复 bind mount 属主后降权为 node 运行）
# USER node
WORKDIR /workspace
EXPOSE 3080
VOLUME ["/data/dsh", "/workspace"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:3080').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
ENTRYPOINT ["/entrypoint.sh"]
