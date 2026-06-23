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
# 用 Docker 官方一键脚本安装最新稳定版
curl -fsSL https://get.docker.com | sudo sh

# 把当前用户加到 docker 用户组，之后就不用每次 sudo 跑 docker 命令
sudo usermod -aG docker $USER

# 让组变更立刻在当前 shell 生效（不用退出再登录）
newgrp docker

# 验证 Docker Engine 已安装
docker --version

# 验证 Docker Compose 子命令可用（Docker 20.10+ 自带）
docker compose version
```

本文档使用 `docker compose`（v2）。

---

## 3. 拉取项目代码

```bash
# 刷新 apt 索引并安装 git（只用一次）
sudo apt-get update && sudo apt-get install -y git

# 把项目克隆到 /opt 目录，方便系统级管理
sudo git clone https://github.com/LiYangSir/daily_stock_analysis.git /opt/daily_stock_analysis

# 把目录所有权改回当前用户，后续 git pull / 编辑 .env 不再需要 sudo
sudo chown -R $USER:$USER /opt/daily_stock_analysis

# 切到项目根目录，下文命令都默认在这里执行
cd /opt/daily_stock_analysis
```

---

## 4. 准备 .env 配置

```bash
# 拷贝示例配置作为起点
cp .env.example .env

# 用你顺手的编辑器打开（这里用 nano；vim/code 都行）
nano .env
```

最小可运行配置：

```dotenv
# 自选股列表（A股代码、hk + 港股代码、美股 ticker，逗号分隔）
STOCK_LIST=600519,hk00700,AAPL

# LLM（任选一个 key；下面以 DeepSeek 为例）
# OpenAI 兼容协议：项目把 OPENAI_API_KEY/OPENAI_BASE_URL/OPENAI_MODEL 自动映射到 LiteLLM
OPENAI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
OPENAI_BASE_URL=https://api.deepseek.com
OPENAI_MODEL=deepseek-chat

# 公网部署务必开启密码保护，否则任何人都能访问 WebUI
ADMIN_AUTH_ENABLED=true
```

完整字段说明见仓库 `.env.example` 内注释。

---

## 5. 创建持久化目录

```bash
# 这些目录会以 volume 形式挂进容器，保存数据库、日志、报告、策略和 Longbridge token；
# 提前在宿主机建好，权限默认就归当前用户，避免后面跑容器时权限不对
mkdir -p data logs reports strategies longbridge_tokens
```

---

## 6. 启动服务

```bash
# 以 FastAPI Web 服务模式后台启动（推荐）；首次会自动构建镜像
docker compose -f docker/docker-compose.yml up -d server

# 实时跟随容器日志（Ctrl+C 退出，不会停服务）
docker compose -f docker/docker-compose.yml logs -f server

# 健康检查：返回 200 即代表服务就绪
curl -fsS http://127.0.0.1:8000/api/v1/health
```

首次启动会自动构建镜像。如果只想跑定时分析（不开 WebUI）：

```bash
# 跑后台定时任务版（按 SCHEDULE_TIMES 周期执行分析并通过通知渠道推送）
docker compose -f docker/docker-compose.yml up -d analyzer
```

---

## 7. 首次访问 WebUI

浏览器访问 `http://<服务器IP>:8000`，第一次会进入“设置初始密码”页面。

---

## 8. 反向代理 + HTTPS（公网部署）

> 适合把容器跑在 `127.0.0.1:8000`，外面挂 nginx 处理 80/443 + 证书续签。下面用 `stock.quguai.cn` 举例，替换成你自己的域名即可。

### 8.1 准备

```bash
# 1. 在 DNS 控制台把域名 A/AAAA 记录解析到这台服务器 IP
#    （阿里云 / Cloudflare 等都行）

# 2. 安装 nginx 和 certbot（Let's Encrypt 客户端 + nginx 插件）
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

### 8.2 写一份最小 HTTP 站点配置

第一次申请证书时 certbot 需要走 HTTP-01 挑战，所以**先只写 80 端口**。Ubuntu 推荐放在 `/etc/nginx/conf.d/`：

```bash
# 把站点配置写到 /etc/nginx/conf.d/stock.conf（域名换成你自己的）
sudo tee /etc/nginx/conf.d/stock.conf > /dev/null <<'EOF'
server {
    listen 80;
    server_name stock.quguai.cn;

    # 反代到本机 daily_stock_analysis 容器
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;

        # 透传真实主机名和客户端 IP，给 WebUI 限流/日志使用
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 报告生成 / Agent 推理可能较久，给 5 分钟超时
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;

        # 关闭缓冲，让 SSE / 流式回复实时下发给浏览器
        proxy_buffering off;
    }

    # 设置导入 / 截图等接口允许的最大上传体积
    client_max_body_size 20m;
}
EOF

# 检查语法并 reload
sudo nginx -t && sudo systemctl reload nginx
```

### 8.3 自动签发证书并升级到 HTTPS

```bash
# certbot 会：申请证书 → 把 80 端口配置改写为 443 + 80→443 跳转 → 自动续签
sudo certbot --nginx -d stock.quguai.cn

# 确认新配置语法 OK 并 reload（certbot 一般已经做了）
sudo nginx -t && sudo systemctl reload nginx
```

执行完后 `/etc/nginx/conf.d/stock.conf` 会被 certbot 重写成下面这种「managed」结构：

```nginx
server {
    server_name stock.quguai.cn;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_buffering off;
    }

    client_max_body_size 20m;

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/stock.quguai.cn/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/stock.quguai.cn/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}

server {
    if ($host = stock.quguai.cn) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    listen 80;
    server_name stock.quguai.cn;
    return 404; # managed by Certbot
}
```

这种结构后续 `certbot renew` 会自动续签，不需要再手动改。

### 8.4 收尾

```dotenv
# 在 .env 里加上（HTTPS 部署务必加），并 docker compose ... restart server
TRUST_X_FORWARDED_FOR=true
```

这样登录限流和审计日志读到的是真实公网 IP 而不是 nginx 的 127.0.0.1。

> 备注：如果你的服务器走 `/etc/nginx/sites-available/` + `/etc/nginx/sites-enabled/` 这套约定（比如默认的 nginx.conf 里有 `include /etc/nginx/sites-enabled/*;`），把上面 `/etc/nginx/conf.d/stock.conf` 路径改成 `/etc/nginx/sites-available/stock`，再 `ln -sf` 到 sites-enabled 下即可。

---

## 9. 升级

只改了 `.env`：

```bash
# 只重启容器即可加载新配置（端口、调度器、数据库路径等才需要这么做；
# 大多数运行时字段直接热生效，根本不用重启）
docker compose -f docker/docker-compose.yml restart server
```

升级到上游最新代码：

```bash
cd /opt/daily_stock_analysis

# 升级前先备份（数据都在挂载目录里）：
# .env 是配置；data 含 SQLite 数据库；reports 是历史报告；
# logs 是排错用日志；longbridge_tokens 是行情 token 缓存
sudo tar czf "/opt/dsa-backup-$(date +%F-%H%M).tgz" \
  .env data reports logs longbridge_tokens

# 拉远端最新分支（fast-forward only，避免引入合并提交）
git fetch --all --prune
git pull --ff-only

# 重新构建镜像，--pull 会顺便刷新基础镜像
docker compose -f docker/docker-compose.yml build --pull

# 滚动重启：用新镜像重新创建容器，volume 复用所以数据不丢
docker compose -f docker/docker-compose.yml up -d server

# 升级后健康检查
curl -fsS http://127.0.0.1:8000/api/v1/health
```

升级失败回滚：

```bash
# 把代码回退到升级前的提交（先用 git log 查到目标 SHA）
git checkout <上一个 commit>

# 重建对应版本镜像并启动（不加 --pull，避免又拉到新基础镜像）
docker compose -f docker/docker-compose.yml build
docker compose -f docker/docker-compose.yml up -d server
```

数据 / `.env` 异常时从备份恢复：

```bash
# 把备份解压回项目目录（注意把日期占位符换成实际文件名）
sudo tar xzf /opt/dsa-backup-YYYY-MM-DD-HHMM.tgz -C /opt/daily_stock_analysis

# 重启容器加载恢复后的 .env / 数据
docker compose -f docker/docker-compose.yml restart server
```

---

## 10. 排错

```bash
# 看容器是否在跑、健康检查状态、端口映射
docker compose -f docker/docker-compose.yml ps

# 跟随最近 200 行日志（实时刷新）
docker compose -f docker/docker-compose.yml logs -f --tail=200 server

# 进入容器开个 shell，定位文件 / 跑命令
docker compose -f docker/docker-compose.yml exec server bash

# 容器卡住或想清状态时重启
docker compose -f docker/docker-compose.yml restart server

# 完全停止并删除容器（数据卷不动，下次 up 会自动重建）
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
