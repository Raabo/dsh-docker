# syntax=docker/dockerfile:1

# ---------- builder: 源码构建（与上游 CI 一致: node 24 + pnpm 11.7.0） ----------
FROM node:24-bookworm AS builder
ENV PNPM_HOME=/pnpm PATH=/pnpm:$PATH
RUN npm install -g pnpm@11.7.0
WORKDIR /app
COPY . .
RUN pnpm install --frozen-lockfile
RUN pnpm run build

# ---------- runtime: 最小运行环境 ----------
FROM node:24-slim AS runtime
ENV NODE_ENV=production \
    DSH_TELEMETRY_DISABLED=1 \
    DSH_HOME=/data/dsh \
    DSH_TRUSTED_HOSTS=""
RUN apt-get update && apt-get install -y --no-install-recommends socat bash \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app /app
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && mkdir -p /data/dsh /workspace && chown -R node:node /data/dsh /workspace
USER node
WORKDIR /workspace
EXPOSE 3080
VOLUME ["/data/dsh", "/workspace"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:3080').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
ENTRYPOINT ["/entrypoint.sh"]
