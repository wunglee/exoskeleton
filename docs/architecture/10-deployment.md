# 10. 部署架构

> 外骨骼系统基于 Docker Compose 的完整部署拓扑，包含基础设施、微服务、认证、监控组件。所有外骨骼组件与核心业务服务在同一 Docker 网络中运行，但只有网关对外暴露端口。

## 10.1 部署拓扑

```
                        Internet
                           │
                    ┌──────┴──────┐
                    │   Nginx      │  ← 反向代理 / TLS 终止
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        :3000 (Web)  :3005 (Admin)  :8080 (Gateway)
                                           │
                    ┌──────────────────────┘
                    │ Docker Internal Network
                    │
        ┌───────────┼───────────┬───────────┬───────────┐
        ▼           ▼           ▼           ▼           ▼
    auth-svc   tenant-svc  billing-svc  admin-svc  scheduler-svc
        │           │           │           │           │
        └───────────┴───────────┴─────┬─────┴───────────┘
                                      │
                          ┌───────────┼───────────┐
                          ▼           ▼           ▼
                      PostgreSQL   Redis      Nacos
                          │
                    ┌─────┴─────┐
                    ▼           ▼
                Logto      Logto-PG
```

## 10.2 Docker Compose（开发环境）

```yaml
# exoskeleton/docker-compose.yml

version: "3.8"

services:
  # ============ 基础设施 ============

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: nsca
      POSTGRES_PASSWORD: nsca_dev
      POSTGRES_DB: nsca
    ports: ["5432:5432"]
    volumes: [pgdata:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U nsca"]
      interval: 5s

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    volumes: [redisdata:/data]
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
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/nsca
      SPRING_DATASOURCE_USERNAME: nsca
      SPRING_DATASOURCE_PASSWORD: nsca_dev
    ports: ["8088:8088"]

  # ============ 认证 ============

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

  # ============ 外骨骼微服务 ============

  gateway:
    build: { context: ./exoskeleton-gateway, dockerfile: Dockerfile }
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
      nacos: { condition: service_healthy }
    ports: ["8080:8080"]
    environment:
      NACOS_SERVER_ADDR: nacos:8848
      SENTINEL_DASHBOARD: sentinel:8858

  auth-service:
    build: { context: ./exoskeleton-auth, dockerfile: Dockerfile }
    depends_on: [postgres, redis, nacos]

  tenant-service:
    build: { context: ./exoskeleton-tenant, dockerfile: Dockerfile }
    depends_on: [postgres, nacos]

  billing-service:
    build: { context: ./exoskeleton-billing, dockerfile: Dockerfile }
    depends_on: [postgres, redis, nacos]

  admin-service:
    build: { context: ./exoskeleton-admin, dockerfile: Dockerfile }
    depends_on: [postgres, nacos]

  scheduler-service:
    build: { context: ./exoskeleton-scheduler, dockerfile: Dockerfile }
    depends_on: [postgres, xxl-job-admin]

  # ============ 业务服务（不修改！仅作为依赖） ============

  nsca-compute:
    build: { context: ../services/nsca-compute, dockerfile: Dockerfile }
    # 注意：不对外暴露端口，仅内网可达
    command: uvicorn main:app --host 0.0.0.0 --port 8100

  # ============ 前端 ============

  web:
    build: { context: ../web, dockerfile: Dockerfile }
    depends_on: [gateway]
    environment:
      NEXT_PUBLIC_API_URL: http://localhost:8080
      NEXT_PUBLIC_LOGTO_ENDPOINT: http://localhost:3001
      NEXT_PUBLIC_LOGTO_APP_ID: ${LOGTO_APP_ID}
    ports: ["3000:3000"]

  admin-ui:
    build: { context: ../admin, dockerfile: Dockerfile }
    depends_on: [gateway]
    environment:
      VITE_API_URL: http://localhost:8080
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
    image: apache/skywalking-oap-server:10.0.0
    environment:
      SW_STORAGE: postgresql
      SW_JDBC_URL: jdbc:postgresql://postgres:5432/skywalking
    ports: ["11800:11800", "12800:12800"]

volumes:
  pgdata:
  redisdata:
  logto_pgdata:
  grafana_data:
```

## 10.3 外部环境变量

```bash
# exoskeleton/config/.env
LOGTO_APP_ID=xxx
LOGTO_APP_SECRET=xxx
LOGTO_ADMIN_APP_ID=xxx
STRIPE_API_KEY=sk_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
JEEPAY_BASE_URL=https://pay.jeepay.vip
JEEPAY_MCH_NO=xxx
JEEPAY_APP_ID=xxx
JEEPAY_API_KEY=xxx
```

## 10.4 端口规划

| 端口 | 服务 | 用途 |
|------|------|------|
| 8080 | Spring Cloud Gateway | API 统一入口 |
| 3000 | Web (Next.js) | 用户前端 |
| 3001 | Logto | OIDC 端点 |
| 3002 | Logto Admin | 认证管理控制台 |
| 3003 | Grafana | 监控仪表板 |
| 3005 | Admin UI (Refine) | 管理控制台 |
| 5432 | PostgreSQL | 外骨骼数据库 |
| 6379 | Redis | 缓存 / 限流 |
| 8088 | XXL-JOB Admin | 调度管理 |
| 8100 | NSCA Compute (内网) | 核心计算引擎 — **不对外暴露** |
| 8848 | Nacos | 服务注册 + 配置中心 |
| 8858 | Sentinel Dashboard | 限流熔断管理 |
| 9090 | Prometheus | 指标采集 |
| 11800 | SkyWalking OAP (gRPC) | 链路追踪数据接收 |
| 12800 | SkyWalking OAP (HTTP) | 链路追踪查询 |

## 10.5 网络隔离规则

| 规则 | 说明 |
|------|------|
| 外骨骼微服务 | 不暴露公网端口，仅 Docker 内网可达 |
| 业务服务 (nsca-compute) | 不暴露公网端口，仅网关可路由 |
| 基础设施 (PG/Redis) | 不暴露公网端口 |
| Gateway | 仅暴露 8080 |
| 前端 (Web/Admin) | 暴露 3000/3005（开发），生产环境经 Nginx 代理 |
| Logto | 暴露 3001/3002（OIDC 端点需公网可达） |

## 10.6 生产环境部署要点

1. **Nginx 前置**：TLS 终止、静态资源、反向代理
2. **Nacos 集群模式**：3 节点 + MySQL 持久化
3. **PostgreSQL 主从**：读写分离，自动故障切换
4. **Redis Sentinel**：高可用 + 持久化
5. **日志收集**：ELK / Loki + Promtail
6. **密钥管理**：HashiCorp Vault 或云 KMS
7. **CI/CD**：GitHub Actions / GitLab CI，每个模块独立镜像构建

---

## 参考

- [Docker Compose 文档](https://docs.docker.com/compose/)
- [Nacos 部署手册](https://nacos.io/docs/latest/guide/admin/deployment/)
- [XXL-JOB 部署文档](https://www.xuxueli.com/xxl-job/)
