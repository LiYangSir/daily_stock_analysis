# Ubuntu Server Docker Compose 部署速查

> 在一台干净的 Ubuntu Server 上用 Docker Compose 部署 daily_stock_analysis WebUI。

---

## 1. 准备工作

- Ubuntu Server 20.04 / 22.04 / 24.04
- 至少 2 GB 内存、10 GB 可用磁盘
- 一个非 root 用户

需要对外开放的端口只有 8000（WebUI / FastAPI）。

---

## 2. 安装 Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker

docker --version
docker compose version
```

本文档使用 `docker compose`（v2）。

---

## 3. 拉取项目代码

```bash
sudo apt-get update && sudo apt-get install -y git
sudo git clone https://github.com/ZhuLinsen/daily_stock_analysis.git /opt/daily_stock_analysis
sudo chown -R $USER:$USER /opt/daily_stock_analysis
cd /opt/daily_stock_analysis
```

---

## 4. 准备 .env 配置

```bash
cp .env.example .env
nano .env
```

最小可运行配置：

```dotenv
STOCK_LIST=600519,hk00700,AAPL

# LLM（任选一个 key；下面以 DeepSeek 为例）
OPENAI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
OPENAI_BASE_URL=https://api.deepseek.com
OPENAI_MODEL=deepseek-chat

# 公网部署务必开启密码保护
ADMIN_AUTH_ENABLED=true
```

完整字段说明见仓库 `.env.example` 内注释。

---

## 5. 创建持久化目录

```bash
mkdir -p data logs reports strategies longbridge_tokens
```

---

## 6. 启动服务

```bash
docker compose -f docker/docker-compose.yml up -d server
docker compose -f docker/docker-compose.yml logs -f server
curl -fsS http://127.0.0.1:8000/api/v1/health
```

首次启动会自动构建镜像。如果只想跑定时分析（不开 WebUI）：

```bash
docker compose -f docker/docker-compose.yml up -d analyzer
```

---

## 7. 首次访问 WebUI

浏览器访问 `http://<服务器IP>:8000`，第一次会进入“设置初始密码”页面。

---

## 8. 反向代理 + HTTPS（公网部署）

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
        proxy_buffering off;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/dsa /etc/nginx/sites-enabled/dsa
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d your.domain.com
```

启用 HTTPS 后建议在 `.env` 加上 `TRUST_X_FORWARDED_FOR=true` 并重启容器。

---

## 9. 升级

只改了 `.env`：

```bash
docker compose -f docker/docker-compose.yml restart server
```

升级到上游最新代码：

```bash
cd /opt/daily_stock_analysis

# 升级前先备份（数据都在挂载目录里）
sudo tar czf "/opt/dsa-backup-$(date +%F-%H%M).tgz" \
  .env data reports logs longbridge_tokens

git fetch --all --prune
git pull --ff-only
docker compose -f docker/docker-compose.yml build --pull
docker compose -f docker/docker-compose.yml up -d server

curl -fsS http://127.0.0.1:8000/api/v1/health
```

升级失败回滚：

```bash
git checkout <上一个 commit>
docker compose -f docker/docker-compose.yml build
docker compose -f docker/docker-compose.yml up -d server
```

数据 / `.env` 异常时从备份恢复：

```bash
sudo tar xzf /opt/dsa-backup-YYYY-MM-DD-HHMM.tgz -C /opt/daily_stock_analysis
docker compose -f docker/docker-compose.yml restart server
```

---

## 10. 排错

```bash
# 状态 / 日志
docker compose -f docker/docker-compose.yml ps
docker compose -f docker/docker-compose.yml logs -f --tail=200 server

# 进容器排查
docker compose -f docker/docker-compose.yml exec server bash

# 重启
docker compose -f docker/docker-compose.yml restart server

# 完全停止（数据保留在挂载目录里）
docker compose -f docker/docker-compose.yml down
```

常见问题：

- **8000 端口起不来**：主机端口被占用，改 `.env` 里 `API_PORT=8080` 后重启。
- **首页一直加载**：看 `logs/stock_analysis_*.log`，通常是 LLM key 缺失或网络不通。
- **WebUI 改配置不生效**：端口、调度器、数据库路径等需要 `restart server` 才生效。

---

## 附：相关文档

- `docs/DEPLOY.md` / `docs/DEPLOY_EN.md`：完整部署指南（直接部署 / Systemd / Supervisor）
- `docker/docker-compose.yml`：本指南引用的 compose 文件
- `.env.example`：所有配置项的官方说明
