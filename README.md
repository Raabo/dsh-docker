# dsh-docker

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）的自动构建 Docker 镜像。

基于上游官方 npm 包 `@deepseek-ai/dsh`（预构建发布）构建，非源码编译。每 6 小时检查 npm 新版本，有更新自动构建发布。

## 镜像

- `ghcr.io/raabo/dsh:latest` — 最新构建（约 **487MB**，amd64）
- `ghcr.io/raabo/dsh:v<版本>` — 按 npm 版本固定（如 `v0.1.0-rc.6`，可回滚）
- `ghcr.io/raabo/dsh:v<版本>-r<commit>` — 版本 + 构建仓库 commit 组合 tag（精确追溯本次构建的 Dockerfile/entrypoint 状态）

## 快速开始

```bash
mkdir -p /path/to/dsh-data /path/to/dsh-workspace   # 换成你自己的主机目录

docker run -d --name dsh \
  -p 3080:3080 \
  -v /path/to/dsh-data:/data/dsh \
  -v /path/to/dsh-workspace:/workspace \
  -e DSH_TRUSTED_HOSTS="192.168.1.100" \
  ghcr.io/raabo/dsh:latest
```

然后浏览器打开 `http://<主机IP>:3080`。

## Docker Compose

创建 `docker-compose.yml`：

```yaml
services:
  dsh:
    image: ghcr.io/raabo/dsh:latest
    container_name: dsh
    restart: unless-stopped
    ports:
      - "3080:3080"
    volumes:
      # 绑定挂载：数据保存在主机目录（把 ./data 换成你自己的路径，如 /vol1/docker/dsh）
      - ./data/dsh:/data/dsh        # 配置 / profile / 会话
      - ./workspace:/workspace      # 默认工作区

    environment:
      # ── 按需取消注释 ──────────────────────────────
      # 远程访问必填：浏览器地址栏的 IP 或域名（空格分隔多个）
      # DSH_TRUSTED_HOSTS: 192.168.1.100
      # 远程配置模型/密钥（放宽上游 loopback-only 限制，仅可信网络内使用）
      # DSH_ALLOW_REMOTE_SETTINGS: "1"
      # 关闭遥测（镜像默认已启用，无需设置）
      # DSH_TELEMETRY_DISABLED: "1"
```

启动：

```bash
docker compose up -d
```

常用命令：

```bash
docker compose logs -f dsh                 # 看日志
docker compose pull && docker compose up -d  # 拉取最新镜像并重启
docker compose down                        # 停止（数据保留在主机目录）
```

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `DSH_TRUSTED_HOSTS` | （空） | **远程访问必填**。空格分隔的主机列表（`host` 或 `host:port`，不支持通配符）。dsh 的 `/api` 有浏览器信任围栏（防 DNS rebinding / 跨站请求），从非回环地址访问时 Host 必须在此白名单内，否则 API 返回 403。例如 `-e DSH_TRUSTED_HOSTS="192.168.1.100 nas.example.com"`。无端口条目匹配该主机任意端口 |
| `DSH_ALLOW_REMOTE_SETTINGS` | `0` | **默认关闭**。设为 `1` 且请求 Host 在白名单内时，允许远程浏览器访问 settings/credentials 域（LLM 模型配置、密钥）。上游设计为 loopback-only（仅本机可改设置），此开关显式放宽该限制——**仅应在可信网络（内网/VPN）内开启**，否则任何白名单内主机都可读改你的模型配置与密钥 |
| `DSH_HOME` | `/data/dsh` | 配置 / profile / 会话数据目录（建议挂载卷持久化） |
| `DSH_TELEMETRY_DISABLED` | `1` | 关闭遥测 |

## 数据卷

使用**绑定挂载**把数据持久化到主机目录（推荐，方便备份/迁移）：

- `主机目录:/data/dsh` — dsh 配置、profile、会话（`DSH_HOME`）
- `主机目录:/workspace` — 默认工作区（headless 任务的运行目录）

> 目录需提前创建，但**无需手动设置属主**：镜像 entrypoint 以 root 启动，会自动 `chown` 数据目录为容器内 `node` 用户（UID 1000）并 `chmod 600` 密钥文件，随后降权运行 dsh。绑定挂载权限问题由容器自愈。

## 构建机制

- 仓库：<https://github.com/Raabo/dsh-docker>（workflow 用 npm 官方包 `@deepseek-ai/dsh` 构建，无需上游源码）
- 触发：每 6 小时 schedule + push + 手动 `workflow_dispatch`（`force=true` 强制重建）
- 跳过逻辑：检测**组合 tag** `v<npm版本>-r<本仓库commit>` 是否已存在——npm 发新版或本仓库 Dockerfile/entrypoint 有改动都会重建，两者都没变才跳过
- 与源码版差异：npm 包为上游预构建发布（版本滞后于 git master），**不含 codex/claude 子代理 SDK**（镜像更小的主要原因）；需要子代理功能可另行通过 `dsh plugin` 安装

## 安全说明

- entrypoint 以 root 启动（仅用于修复挂载目录权限），随后**降权为 `node` 用户运行 dsh 与反代**
- 上游刻意禁止 `--host 0.0.0.0`（防止 agent 的远程代码执行能力直接暴露到网络）；本镜像内 dsh 监听 `127.0.0.1:3081`，由内置 Node 反代转发 `0.0.0.0:3080`，对外暴露前请务必确认网络边界（防火墙 / Traefik 反向代理 + 认证）
- 设置域（模型配置、密钥）上游强制 loopback-only：远程浏览器访问时 `/api/settings.*`、`/api/credentials.*` 返回 403，属预期行为。本机访问（`localhost` / SSH 隧道）不受影响；确需远程配置时再开 `DSH_ALLOW_REMOTE_SETTINGS=1`（见环境变量表）
- 密钥文件 `.credentials.yaml` 强制 owner-only（600），权限过宽时 dsh 会拒绝启动（防泄露设计）；镜像 entrypoint 会自动修复
- landlock 原生沙箱（`@deepseek-ai/node-addon-landlock-run`）未内置；如需要可在容器内通过 `dsh plugin` 安装并特权运行
