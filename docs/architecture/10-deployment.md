# 10. 部署架构

> NSCA 外骨骼基于 yudao-cloud 的 Docker Compose 拓扑扩展。yudao 已提供完整的微服务/单体双模部署方案、Nacos/Sentinel/XXL-JOB 基础设施和 MySQL/Redis 数据层。NSCA 新增 Logto、Stripe Webhook 路由和核心业务服务的容器化。

## 10.1 部署模式

yudao 支持两种部署模式，NSCA 按阶段使用：

| 模式 | 说明 | NSCA 阶段 |
|------|------|---------|
| **单体模式** | yudao-server 合并所有模块为一个 JAR，Nacos 禁用 | 开发期 + MVP |
| **微服务模式** | 每个 yudao 模块独立部署，Nacos 注册发现 | 生产扩展期 |

### 单体开发模式

```
docker compose up → 启动 MySQL + Redis
./mvnw spring-boot:run -pl yudao-server → 启动单体应用 (端口 48080)
  └── 包含: system + infra + member + pay + community (所有模块)
```

### 微服务生产模式

```
docker compose up → 启动全部基础设施 + 微服务
  各 yudao 模块独立容器 + Nacos 注册发现 + Sentinel 限流
```

## 10.2 部署拓扑

```
                        Internet
                           │
                    ┌──────┴──────┐
                    │   Nginx      │  ← TLS 终止 / 反向代理
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        :3000 (Web)  :3005 (Admin)  :48080 (Gateway/yudao-server)
                                           │
                    ┌──────────────────────┘
                    │ Docker Internal Network
                    │
        ┌───────────┼───────────┬───────────┬───────────┐
        ▼           ▼           ▼           ▼           ▼
  yudao-gateway  yudao-system yudao-member yudao-pay yudao-community
  (单体:含所有)   (单体:含所有)  ...独立服务... (微服务:新增)
        │           │           │           │           │
        └───────────┴───────────┴─────┬─────┴───────────┘
                                      │
                          ┌───────────┼───────────┐
                          ▼           ▼           ▼
                      MySQL 8.0   Redis 7     Nacos
                          │
                    ┌─────┴─────┐
                    ▼           ▼
                Logto      Logto-PG
                (OIDC)     (独立DB)
                          │
                    ┌─────┴─────────────┐
                    ▼                   ▼
              nsca-core-service    Elasticsearch
              (核心引擎,内网)       (社区搜索)
```

## 10.3 Docker Compose

> 基于 yudao 的 `docker-compose.yml` 扩展。yudao 原有服务（MySQL、Redis、Nacos、Sentinel、XXL-JOB）保留，NSCA 新增 Logto、Elasticsearch 和核心透传服务。

```yaml
# exoskeleton/docker-compose.yml

version: "3.8"

services:
  # ============ yudao 基础设施（直接复用） ============

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root123
      MYSQL_DATABASE: yudao
    ports: ["3306:3306"]
    volumes: [mysql_data:/var/lib/mysql]
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 5s

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    volumes: [redis_data:/data]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s

  nacos:
    image: nacos/nacos-server:v2.4.0
    environment:
      MODE: standalone
      SPRING_DATASOURCE_PLATFORM: embedded
    ports:
      - "8848:8848"
      - "9848:9848"

  sentinel:
    image: bladex/sentinel-dashboard:1.8.8
    ports: ["8858:8858"]

  xxl-job-admin:
    image: xuxueli/xxl-job-admin:2.4.0
    environment:
      SPRING_DATASOURCE_URL: jdbc:mysql://mysql:3306/yudao?useSSL=false
      SPRING_DATASOURCE_USERNAME: root
      SPRING_DATASOURCE_PASSWORD: root123
    ports: ["8088:8088"]
    depends_on: [mysql]

  # ============ yudao 微服务（单体模式下由 yudao-server 承载） ============

  yudao-server:
    build:
      context: ./yudao-server
      dockerfile: Dockerfile
    depends_on:
      mysql: { condition: service_healthy }
      redis: { condition: service_healthy }
    ports: ["48080:48080"]
    environment:
      SPRING_PROFILES_ACTIVE: local
      SPRING_DATASOURCE_URL: jdbc:mysql://mysql:3306/yudao?useSSL=false
      SPRING_DATASOURCE_USERNAME: root
      SPRING_DATASOURCE_PASSWORD: root123
      SPRING_REDIS_HOST: redis

  # ============ NSCA 新增：认证服务 ============

  logto:
    image: ghcr.io/logto-io/logto:latest
    depends_on:
      logto-postgres: { condition: service_healthy }
    environment:
      DB_URL: postgres://logto:logto_dev@logto-postgres:5432/logto
      ENDPOINT: http://localhost:3001
      ADMIN_ENDPOINT: http://localhost:3002
    ports:
      - "3001:3001"
      - "3002:3002"
    env_file: ./config/logto.env

  logto-postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: logto
      POSTGRES_PASSWORD: logto_dev
      POSTGRES_DB: logto
    volumes: [logto_pgdata:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U logto"]
      interval: 5s

  # ============ NSCA 新增：社区搜索 ============

  elasticsearch:
    image: elasticsearch:7.17.0
    environment:
      discovery.type: single-node
      "ES_JAVA_OPTS": "-Xms512m -Xmx512m"
    ports: ["9200:9200"]
    volumes: [es_data:/usr/share/elasticsearch/data]

  # ============ 核心业务服务（NSCA 新增，内网不暴露） ============

  nsca-core:
    build:
      context: ../services/nsca-core
      dockerfile: Dockerfile
    command: uvicorn main:app --host 0.0.0.0 --port 8100
    # 不对外暴露端口，仅内网可达

  # ============ 前端 ============

  web:
    build: { context: ../web, dockerfile: Dockerfile }
    depends_on: [yudao-server]
    environment:
      NEXT_PUBLIC_API_URL: http://localhost:48080
      NEXT_PUBLIC_LOGTO_ENDPOINT: http://localhost:3001
      NEXT_PUBLIC_LOGTO_APP_ID: ${LOGTO_APP_ID}
    ports: ["3000:3000"]

  admin-ui:
    build: { context: ../admin, dockerfile: Dockerfile }
    depends_on: [yudao-server]
    environment:
      VITE_API_URL: http://localhost:48080
      VITE_LOGTO_ENDPOINT: http://localhost:3001
      VITE_LOGTO_APP_ID: ${LOGTO_ADMIN_APP_ID}
    ports: ["3005:3005"]

  # ============ 监控 ============

  prometheus:
    image: prom/prometheus:latest
    volumes: [./config/prometheus.yml:/etc/prometheus/prometheus.yml]
    ports: ["9090:9090"]

  grafana:
    image: grafana/grafana:latest
    ports: ["3003:3003"]
    volumes: [grafana_data:/var/lib/grafana]

  skywalking-oap:
    image: apache/skywalking-oap-server:8.12.0
    environment:
      SW_STORAGE: mysql
      SW_JDBC_URL: jdbc:mysql://mysql:3306/skywalking?useSSL=false
      SW_DATA_SOURCE_USER: root
      SW_DATA_SOURCE_PASSWORD: root123
    ports: ["11800:11800", "12800:12800"]

volumes:
  mysql_data:
  redis_data:
  logto_pgdata:
  es_data:
  grafana_data:
```

## 10.4 端口规划

| 端口 | 服务 | 来源 | 说明 |
|------|------|------|------|
| 48080 | yudao-server (Gateway) | yudao | API 统一入口（yudao 默认端口） |
| 3000 | Web (Next.js) | NSCA 新增 | 用户前端 |
| 3001 | Logto | NSCA 新增 | OIDC 端点 |
| 3002 | Logto Admin | NSCA 新增 | 认证管理 UI |
| 3003 | Grafana | yudao 已有 | 监控仪表板 |
| 3005 | Admin UI | yudao 已有 | 管理控制台 (yudao-ui + NSCA 扩展) |
| 3306 | MySQL | yudao 已有 | 外骨骼主数据库 |
| 6379 | Redis | yudao 已有 | 缓存 / 限流 / 分布式锁 |
| 8088 | XXL-JOB Admin | yudao 已有 | 调度管理 Dashboard |
| 8100 | NSCA Core (内网) | NSCA 新增 | 核心引擎 — **不对外暴露** |
| 8848 | Nacos | yudao 已有 | 服务注册 + 配置中心 |
| 8858 | Sentinel Dashboard | yudao 已有 | 限流熔断管理 |
| 9090 | Prometheus | yudao 已有 | 指标采集 |
| 9200 | Elasticsearch | NSCA 新增 | 社区全文搜索 |
| 11800 | SkyWalking OAP (gRPC) | yudao 已有 | 链路追踪数据接收 |
| 12800 | SkyWalking OAP (HTTP) | yudao 已有 | 链路追踪查询 |

## 10.5 网络隔离规则

| 规则 | 说明 |
|------|------|
| yudao 微服务 | 单体模式下仅 yudao-server 运行；微服务模式下各模块不暴露公网端口 |
| 核心业务 (nsca-core) | 不暴露公网端口，仅 yudao-gateway 路由可达 |
| 基础设施 (MySQL/Redis) | 不暴露公网端口（开发期可临时暴露） |
| Gateway / yudao-server | 仅暴露 48080 |
| 前端 (Web/Admin) | 暴露 3000/3005（开发），生产经 Nginx 代理 |
| Logto | 暴露 3001/3002（OIDC 端点需公网可达） |

## 10.6 外部环境变量

```bash
# exoskeleton/config/.env
LOGTO_APP_ID=xxx
LOGTO_APP_SECRET=xxx
LOGTO_ADMIN_APP_ID=xxx
STRIPE_API_KEY=sk_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
# 支付宝/微信支付（yudao Jeepay，如使用）
JEEPAY_BASE_URL=https://pay.jeepay.vip
JEEPAY_MCH_NO=xxx
JEEPAY_API_KEY=xxx
# MySQL（复用 yudao 配置）
SPRING_DATASOURCE_URL=jdbc:mysql://mysql:3306/yudao
SPRING_DATASOURCE_USERNAME=root
SPRING_DATASOURCE_PASSWORD=root123
```

## 10.7 生产环境部署要点

1. **Nginx 前置**：TLS 终止、静态资源、反向代理到 yudao-server
2. **yudao-server 集群**：单体模式下 2+ 实例 + Nginx upstream 负载均衡
3. **Nacos 集群模式**（微服务）：3 节点 + MySQL 持久化，替换单体内嵌模式
4. **MySQL 主从**：读写分离，自动故障切换
5. **Redis Sentinel**：高可用 + AOF 持久化
6. **日志收集**：ELK / Loki + Promtail
7. **密钥管理**：HashiCorp Vault 或云 KMS，替换 `.env` 文件
8. **CI/CD**：GitHub Actions / GitLab CI，yudao-server 和 NSCA 前端独立镜像构建
9. **Stripe Webhook**：生产需配置 Stripe CLI 或公网可访问的 Webhook URL

## 10.8 与 yudao 部署的差异

| 维度 | yudao 原有 | NSCA 扩展 |
|------|----------|----------|
| **数据库** | MySQL 8.0 | 保留 MySQL，Phase 4 迁移 PostgreSQL |
| **OIDC 提供方** | 无独立 OIDC | 新增 Logto + Logto PostgreSQL |
| **搜索** | MySQL LIKE 搜索 | 新增 Elasticsearch（社区全文搜索） |
| **核心服务** | 无 | 新增 nsca-core（Python FastAPI） |
| **前端** | yudao-ui-admin (Vue3) | 保留 + 新增 Web (Next.js) |
| **支付** | Jeepay (支付宝/微信) | 保留 + 新增 Stripe |
| **部署模式** | 单体 + 微服务双模 | 开发期单体，生产期按需微服务 |

---

## 参考

- [yudao-cloud 部署文档](https://doc.iocoder.cn/deploy/)
- [Docker Compose 文档](https://docs.docker.com/compose/)
- [Nacos 部署手册](https://nacos.io/docs/latest/guide/admin/deployment/)
- [Logto 自部署文档](https://docs.logto.io/docs/tutorials/self-hosting/)
