# syntax=docker/dockerfile:1

# ---------- builder: npm 全局安装官方预构建包（node-pty 原生模块需工具链编译，用完整镜像） ----------
FROM node:24 AS builder
RUN npm install -g @deepseek-ai/dsh --no-audit --no-fund \
    && rm -rf /root/.npm

# ---------- runtime: 最小运行环境 ----------
FROM node:24-slim AS runtime
ENV NODE_ENV=production \
    DSH_TELEMETRY_DISABLED=1 \
    DSH_HOME=/data/dsh \
    DSH_TRUSTED_HOSTS="" \
    DSH_ALLOW_REMOTE_SETTINGS=0
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/@deepseek-ai/dsh/lib/bin.js /usr/local/bin/dsh \
    && mkdir -p /data/dsh /workspace && chown -R node:node /data/dsh /workspace
COPY scripts/entrypoint.sh /entrypoint.sh
COPY proxy.mjs /proxy.mjs
RUN chmod +x /entrypoint.sh
USER node
WORKDIR /workspace
EXPOSE 3080
VOLUME ["/data/dsh", "/workspace"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:3080').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
ENTRYPOINT ["/entrypoint.sh"]
