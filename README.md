# dsh-docker

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）的自动构建 Docker 镜像。

上游仓库每次更新（每 6 小时检查一次），GitHub Actions 会自动从源码构建并发布新镜像。

## 镜像

- `ghcr.io/raabo/dsh:latest` — 最新构建
- `ghcr.io/raabo/dsh:sha-<commit>` — 按上游 commit 固定的版本（可回滚）

## 快速开始

```bash
docker run -d --name dsh \
  -p 3080:3080 \
  -v dsh-data:/data/dsh \
  -v dsh-workspace:/workspace \
  -e DSH_TRUSTED_HOSTS="192.168.1.100" \
  ghcr.io/raabo/dsh:latest
```

然后浏览器打开 `http://<主机IP>:3080`。

## Docker Compose

仓库根目录自带 [`docker-compose.yml`](docker-compose.yml)，一条命令启动：

```bash
docker compose up -d
```

远程访问需先配置信任白名单（否则 `/api` 返回 403）。两种方式任选：

```bash
# 方式一：.env 文件
echo "DSH_TRUSTED_HOSTS=192.168.1.100" > .env
docker compose up -d

# 方式二：直接改 docker-compose.yml 的 environment 段
```

常用命令：

```bash
docker compose logs -f dsh   # 看日志
docker compose pull && docker compose up -d   # 拉取最新镜像并重启
docker compose down          # 停止（数据保留在卷里）
```

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `DSH_TRUSTED_HOSTS` | （空） | **远程访问必填**。空格分隔的主机列表（`host` 或 `host:port`，不支持通配符）。dsh 的 `/api` 有浏览器信任围栏（防 DNS rebinding / 跨站请求），从非回环地址访问时 Host 必须在此白名单内，否则 API 返回 403。例如 `-e DSH_TRUSTED_HOSTS="192.168.1.100 nas.example.com"`。无端口条目匹配该主机任意端口 |
| `DSH_HOME` | `/data/dsh` | 配置 / profile / 会话数据目录（建议挂载卷持久化） |
| `DSH_TELEMETRY_DISABLED` | `1` | 关闭遥测 |

## 数据卷

- `/data/dsh` — dsh 配置、profile、会话（`DSH_HOME`）
- `/workspace` — 默认工作区（headless 任务的运行目录）

## 构建机制

- 仓库：<https://github.com/Raabo/dsh-docker>（workflow 直接检出上游 `deepseek-ai/deepseek-harness` master）
- 触发：每 6 小时 schedule + push + 手动 `workflow_dispatch`（`force=true` 强制重建）
- 跳过逻辑：镜像 tag 含上游 commit SHA，`sha-` tag 已存在则跳过（上游无更新不重建）
- 镜像标签同时带 `org.opencontainers.image.revision`（上游 commit）便于溯源

## 安全说明

- 容器以非 root（`node` 用户）运行
- 上游刻意禁止 `--host 0.0.0.0`（防止 agent 的远程代码执行能力直接暴露到网络）；本镜像内 dsh 监听 `127.0.0.1:3081`，由 socat 转发 `0.0.0.0:3080`，对外暴露前请务必确认网络边界（防火墙 / Traefik 反向代理 + 认证）
- landlock 原生沙箱（`@deepseek-ai/node-addon-landlock-run`）未内置；如需要可在容器内通过 `dsh plugin` 安装并特权运行
