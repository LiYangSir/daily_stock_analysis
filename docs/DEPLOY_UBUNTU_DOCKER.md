# Ubuntu Server Docker Compose 部署速查

> 目标：在一台干净的 Ubuntu Server（22.04 / 24.04）上，使用 Docker Compose 部署 daily_stock_analysis WebUI 服务。
> 适用：单机部署、本地或云服务器（阿里云/腾讯云/AWS EC2）。

---

## 1. 准备工作

### 1.1 服务器要求

- Ubuntu Server 20.04 / 22.04 / 24.04
- 至少 2 GB 内存（推荐 4 GB+）、10 GB 可用磁盘
- 已开放出站网络（用于拉取 Docker 镜像、调用 LLM API）
- 一个非 root 用户（推荐用 `ubuntu` 或自建 `dsa`）

### 1.2 端口规划

| 端口 | 用途 | 是否对外 |
| --- | --- | --- |
| 8000 | WebUI / FastAPI | 是（如要远程访问） |

如服务器在公网上，建议只在防火墙/安全组放行 8000，并务必启用 `ADMIN_AUTH_ENABLED=true`。

---

## 2. 安装 Docker + Docker Compose

```bash
# 一键脚本（Docker 官方）
curl -fsSL https://get.docker.com | sudo sh

# 把当前用户加进 docker 组（避免每次都 sudo）
sudo usermod -aG docker $USER
newgrp docker   # 立刻生效，或退出 SSH 重新登录

# 验证（Docker 20.10+ 自带 compose 子命令）
docker --version
docker compose version
```

如果你已经装好但版本太老（< 20.10），请升级，本文档假设使用 `docker compose`（v2）而非 `docker-compose`（v1）。

---

## 3. 拉取项目代码

```bash
sudo apt-get update && sudo apt-get install -y git
cd /opt
sudo git clone https://github.com/ZhuLinsen/daily_stock_analysis.git
sudo chown -R $USER:$USER /opt/daily_stock_analysis
cd /opt/daily_stock_analysis
```

> 如果你 fork 了项目或有私有镜像，把 URL 换成自己的即可。
> 路径不一定要是 `/opt/daily_stock_analysis`，下文命令默认在仓库根目录执行。

---

## 4. 准备 .env 配置

```bash
cp .env.example .env
nano .env   # 或 vim .env
```

**最小可运行配置**（其他保持默认即可）：

```dotenv
# 自选股
STOCK_LIST=600519,hk00700,AAPL

# 任选一个 LLM key（举例使用 DeepSeek 兼容 OpenAI 接口）
OPENAI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
OPENAI_BASE_URL=https://api.deepseek.com
OPENAI_MODEL=deepseek-chat

# 通知（可选，举例钉钉自定义机器人）
CUSTOM_WEBHOOK_URLS=https://oapi.dingtalk.com/robot/send?access_token=xxx

# 公网部署务必开启密码保护（首次访问 WebUI 时设置初始密码）
ADMIN_AUTH_ENABLED=true

# 让容器内 Web 服务监听 0.0.0.0（compose 已自动注入，这里仅说明）
WEBUI_HOST=0.0.0.0
WEBUI_PORT=8000
```

> 完整字段、可选 LLM 通道、通知渠道（飞书/Telegram/邮件等）见仓库根目录 `.env.example` 内注释。

---

## 5. 创建持久化目录

```bash
mkdir -p data logs reports strategies longbridge_tokens
chmod 755 data logs reports strategies
```

这些目录会以 volume 形式挂进容器，保留报告、数据库与日志。

---

## 6. 启动服务

```bash
# 以 FastAPI Web 服务模式启动（推荐）
docker compose -f docker/docker-compose.yml up -d server

# 查看日志
docker compose -f docker/docker-compose.yml logs -f server

# 健康检查
curl -fsS http://127.0.0.1:8000/api/v1/health || echo "服务未就绪"
```

首次启动会自动构建镜像（约 3–8 分钟，取决于网络），完成后容器名为 `stock-server`。

如果只想跑定时分析（不开 WebUI）：

```bash
docker compose -f docker/docker-compose.yml up -d analyzer
```

两者也可同时跑：

```bash
docker compose -f docker/docker-compose.yml up -d analyzer server
```

---

## 7. 首次访问 WebUI

1. 浏览器访问 `http://<服务器IP>:8000`
2. 由于上面开启了 `ADMIN_AUTH_ENABLED=true`，第一次会进入“设置初始密码”页面，设一个强密码后即可登录
3. 登录后在「设置」中可继续维护其他配置（也会落到 `.env`）

---

## 8. 反向代理 + HTTPS（可选但强烈推荐公网部署）

最简单方案：服务器上再装 nginx + certbot，让 nginx 监听 80/443，反代到 `127.0.0.1:8000`。

```bash
sudo apt-get install -y nginx certbot python3-certbot-nginx

sudo tee /etc/nginx/sites-available/dsa <<'EOF'
server {
    listen 80;
    server_name your.domain.com;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        # SSE / streaming 支持
        proxy_buffering off;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/dsa /etc/nginx/sites-enabled/dsa
sudo nginx -t && sudo systemctl reload nginx

# 自动申请并配置 Let's Encrypt 证书
sudo certbot --nginx -d your.domain.com
```

完成后建议在 `.env` 增加 `TRUST_X_FORWARDED_FOR=true` 并重启容器，让登录限流取真实 IP。

---

## 9. 升级 / 维护

升级时遵循 **「先备份 → 再拉代码 → 重建镜像 → 滚动重启 → 验证 → 失败回滚」** 的顺序。

### 9.1 升级前准备

```bash
cd /opt/daily_stock_analysis

# 1) 记录当前版本（用于回滚）
git rev-parse --short HEAD | tee /tmp/dsa-prev-rev.txt
docker compose -f docker/docker-compose.yml ps

# 2) 备份关键数据 + .env（即便 volume 在宿主机，也建议归档）
sudo tar czf "/opt/dsa-backup-$(date +%F-%H%M).tgz" \
  /opt/daily_stock_analysis/.env \
  /opt/daily_stock_analysis/data \
  /opt/daily_stock_analysis/reports \
  /opt/daily_stock_analysis/logs \
  /opt/daily_stock_analysis/longbridge_tokens
ls -lh /opt/dsa-backup-*.tgz | tail -3
```

### 9.2 仅修改了 `.env`（不需要重建）

```bash
# 改完 .env 后只需重启即可，不会重新构建镜像，秒级生效
docker compose -f docker/docker-compose.yml restart server
docker compose -f docker/docker-compose.yml logs --tail=50 server
```

少数配置（端口、数据库路径、调度器开关）需要 down/up 才能完全应用：

```bash
docker compose -f docker/docker-compose.yml down
docker compose -f docker/docker-compose.yml up -d server
```

### 9.3 升级到上游最新版本（含代码改动）

```bash
cd /opt/daily_stock_analysis

# 1) 拉取最新代码（fast-forward，避免引入冲突分支）
git fetch --all --prune
git pull --ff-only

# 2) 重新构建镜像（--pull 拉取最新基础镜像，--no-cache 可强制干净构建）
docker compose -f docker/docker-compose.yml build --pull
# 如果想完全干净：
# docker compose -f docker/docker-compose.yml build --pull --no-cache

# 3) 滚动重启（compose 会复用 volume，数据保留）
docker compose -f docker/docker-compose.yml up -d server

# 4) 健康检查
sleep 5
curl -fsS http://127.0.0.1:8000/api/v1/health && echo "OK"
docker compose -f docker/docker-compose.yml logs --tail=80 server
```

### 9.4 锁定版本升级（推荐生产）

直接 `git pull` 等于跟着 main 走，生产环境推荐跟踪 release tag：

```bash
# 列出最近 5 个 release
git tag --sort=-creatordate | head -5

# 升级到指定 tag
git fetch --tags
git checkout v3.21.0           # 替换为目标版本
docker compose -f docker/docker-compose.yml build --pull
docker compose -f docker/docker-compose.yml up -d server
```

切回主干：

```bash
git checkout main
git pull --ff-only
```

### 9.5 升级失败回滚

```bash
cd /opt/daily_stock_analysis

# 1) 回退代码到升级前的提交
PREV_REV=$(cat /tmp/dsa-prev-rev.txt)
git checkout "$PREV_REV"

# 2) 重建旧版本镜像
docker compose -f docker/docker-compose.yml build
docker compose -f docker/docker-compose.yml up -d server

# 3) 如果 .env / 数据也被破坏，从备份恢复
# sudo tar xzf /opt/dsa-backup-YYYY-MM-DD-HHMM.tgz -C /
# docker compose -f docker/docker-compose.yml restart server
```

### 9.6 镜像与磁盘清理（建议每次升级后跑一次）

```bash
# 移除悬空 layer / 旧镜像 / 退出的容器
docker image prune -f
docker container prune -f
docker builder prune -f

# 查看当前占用
docker system df
```

### 9.7 升级前后冒烟项（建议手动过一遍）

- [ ] WebUI 首页可登录、自选股报告能加载
- [ ] 「设置 → 通知」点 “发送测试” 至少一个渠道返回成功
- [ ] 「设置 → LLM 渠道」执行一次 “测试连通性”
- [ ] `/chat` 输入一条问题能拿到流式回复
- [ ] 浏览器 DevTools 控制台没有 4xx/5xx 红色报错
- [ ] `docker compose ... logs --tail=200 server` 没有 ERROR 级别异常

### 9.8 自动化建议

对长期维护的部署，可以把上面的步骤写成脚本：

```bash
sudo tee /usr/local/bin/dsa-upgrade <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/daily_stock_analysis
PREV=$(git rev-parse --short HEAD)
echo "$PREV" >/tmp/dsa-prev-rev.txt
sudo tar czf "/opt/dsa-backup-$(date +%F-%H%M).tgz" .env data reports logs longbridge_tokens
git fetch --all --prune
git pull --ff-only
docker compose -f docker/docker-compose.yml build --pull
docker compose -f docker/docker-compose.yml up -d server
sleep 5
curl -fsS http://127.0.0.1:8000/api/v1/health
echo "Upgrade OK (was $PREV → $(git rev-parse --short HEAD))"
EOF
sudo chmod +x /usr/local/bin/dsa-upgrade
```

之后升级只需一行：

```bash
sudo dsa-upgrade
```

---

## 10. 备份与还原

数据全部在挂载目录里，完整备份即可：

```bash
sudo tar czf dsa-backup-$(date +%F).tgz \
  /opt/daily_stock_analysis/.env \
  /opt/daily_stock_analysis/data \
  /opt/daily_stock_analysis/logs \
  /opt/daily_stock_analysis/reports \
  /opt/daily_stock_analysis/longbridge_tokens
```

还原时把目录解压回原位再 `docker compose ... up -d server` 即可。

---

## 11. 常用排错命令

```bash
# 容器状态
docker compose -f docker/docker-compose.yml ps

# 实时日志
docker compose -f docker/docker-compose.yml logs -f --tail=200 server

# 进容器排查
docker compose -f docker/docker-compose.yml exec server bash

# 看端口占用
sudo ss -ltnp | grep 8000

# 重置（保留数据）
docker compose -f docker/docker-compose.yml down
docker compose -f docker/docker-compose.yml up -d server

# 完全清理（数据保留在宿主机挂载目录里）
docker compose -f docker/docker-compose.yml down --rmi local
```

常见问题：

- **8000 端口起不来**：检查 `.env` 里 `API_PORT` 是否与 compose 中 `${API_PORT:-8000}` 期望一致；或主机已被占用，可改成 `API_PORT=8080` 后 `up -d server` 重启。
- **首页一直加载**：进容器看 `logs/stock_analysis_*.log`，多半是 LLM key 没填或网络不通。
- **WebUI 改了配置不生效**：少量配置（端口、调度器、数据库路径）需要重启容器；正常做法 `docker compose ... restart server`。
- **公网访问慢/卡**：开启 nginx + HTTPS，或在 `.env` 配置代理 `USE_PROXY=true`、`PROXY_HOST`、`PROXY_PORT`（仅在你确实有可用代理时）。

---

## 12. 安全清单（公网部署必看）

- [ ] `.env` 权限收紧：`chmod 600 .env`
- [ ] 启用 `ADMIN_AUTH_ENABLED=true` 并设置高强度密码
- [ ] 只通过 nginx + HTTPS 暴露 80/443，**不要直接把 8000 暴露公网**
- [ ] 定期 `git pull` + 重建镜像，跟进上游安全修复
- [ ] 备份目录不要放进 Git；`.env`、`data/`、`reports/` 已在 `.gitignore` 内

---

## 13. 卸载

```bash
cd /opt/daily_stock_analysis
docker compose -f docker/docker-compose.yml down --rmi local
cd /
sudo rm -rf /opt/daily_stock_analysis    # 会删除报告与数据，请先备份
```

---

## 附：仓库内已有的相关文档

- `docs/DEPLOY.md` / `docs/DEPLOY_EN.md`：完整部署指南（含直接部署、Systemd、Supervisor 等多方案）
- `docs/deploy-webui-cloud.md`：云服务器开放公网访问的细节
- `docker/docker-compose.yml`：本指南所引用的 compose 文件
- `.env.example`：所有可配置项的官方说明
