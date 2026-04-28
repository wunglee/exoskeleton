# NSCA 外骨骼系统 v1.0 开发路线图

> **文档定位**：外骨骼系统（Spring Cloud Alibaba 微服务平台外壳）的独立工程实施计划
> **核心策略**：先企业设施后平台体验 / 网关即集成协议 / 与核心业务完全并行
> **版本**：v1.0 | 日期：2026-04-28
> **目标读者**：平台工程师、DevOps、技术负责人

---

## 1. 执行摘要

外骨骼系统的开发遵循**"先设施后体验 → 先认证后计费 → 先隔离后开放"**的渐进式交付路径。每一阶段交付一个**独立可用的平台能力**。外骨骼与核心业务系统（`services/`）完全并行开发，唯一集成面是网关 HTTP Header 协议。

```mermaid
graph TB
    subgraph Phase0["Phase 0: 基础设施"]
        P0[Maven多模块 + Docker + DB Schema]
    end
    subgraph Phase1["Phase 1: 认证与租户"]
        P1[Spring Security + Logto + 多租户隔离]
    end
    subgraph Phase2["Phase 2: 计费与支付"]
        P2[Stripe + Jeepay + RP 系统]
    end
    subgraph Phase3["Phase 3: 网关与集成"]
        P3[Gateway Filter Chain + Sentinel + 业务对接]
    end
    subgraph Phase4["Phase 4: 管理与监控"]
        P4[Admin API + Dashboard + 全链路追踪]
    end
    subgraph Phase5["Phase 5: 生产加固"]
        P5[安全 + 性能 + 灾备 + 文档]
    end

    P0 --> P1 --> P2 --> P3 --> P4 --> P5

    style P0 fill:#e3f2fd,stroke:#1565c0
    style P1 fill:#e3f2fd,stroke:#1565c0
    style P2 fill:#fff3e0,stroke:#ef6c00
    style P3 fill:#fff3e0,stroke:#ef6c00
    style P4 fill:#e1f5e1,stroke:#2e7d32
    style P5 fill:#fce4ec,stroke:#c62828
```

**阶段颜色说明**：
- 🔵 蓝色阶段：基础设施，无用户可见功能，但所有后续阶段依赖
- 🟠 橙色阶段：核心业务能力，用户可直接感知（登录/支付）
- 🟢 绿色阶段：运维可见，平台运营能力
- 🔴 红色阶段：生产就绪，安全与可靠性

**与核心业务的关键差异**：

| 维度 | 外骨骼系统 | 核心业务系统 |
|------|-----------|------------|
| 技术栈 | Spring Boot 3.4 + Cloud Alibaba | Python FastAPI / 任意语言 |
| 数据库 | PostgreSQL（独立实例） | 无用户表，信任 Header |
| 交付节奏 | Phase 0-1 需优先完成（认证是前提） | 可使用 Mock 认证并行开发 |
| 集成面 | 网关是唯一入口 | 接收 X-Tenant-Id / X-User-Id Header |

---

## 2. 总体策略

### 2.1 风险前置矩阵

| 风险项 | 风险等级 | 缓解阶段 | 缓解措施 |
|--------|---------|---------|---------|
| Logto OIDC 集成失败 | 🔴 极高 | Phase 1 | 提前验证 JWT 签发/校验全链路，准备 Keycloak 备用方案 |
| MyBatis-Plus 租户拦截器遗漏 | 🔴 极高 | Phase 1 | 全局 SQL 日志审计，集成测试覆盖每张表 |
| Stripe/Jeepay Webhook 签名校验 | 🔴 极高 | Phase 2 | 使用官方 SDK 验证方法，不手写签名逻辑 |
| RP 余额并发扣除超卖 | 🔴 极高 | Phase 2 | PostgreSQL 行级锁 + @Transactional，压测验证 |
| 网关 Filter 顺序错误导致鉴权绕过 | 🔴 极高 | Phase 3 | Filter 顺序写死为 ordinal 常量，集成测试覆盖所有顺序组合 |
| Sentinel 规则误拦正常流量 | 🟠 高 | Phase 3 | 先在日志模式运行 1 周，确认无误再开启限流 |
| Jeepay 支付宝/微信回调延迟 | 🟠 高 | Phase 2 | 异步重试队列 + 手动补单后台 |
| Nacos 单点故障 | 🟡 中 | Phase 5 | 开发阶段可单机，Phase 5 升级集群模式 |

### 2.2 高度并行模型

```mermaid
graph LR
    subgraph Contract["契约层（Phase 0 冻结）"]
        C1[网关 Header 协议]
        C2[数据库 Schema]
        C3[OpenAPI 规范]
        C4[Maven 模块结构]
    end

    subgraph Backend["后端并行流"]
        B1[认证服务]
        B2[租户拦截器]
        B3[计费服务]
        B4[支付路由]
        B5[RP 引擎]
        B6[网关 Filter Chain]
        B7[管理 API]
    end

    subgraph Integration["集成验证流"]
        I1[网关→认证 联调]
        I2[网关→计费 联调]
        I3[网关→业务服务 Header 透传]
        I4[全链路审计日志]
    end

    subgraph Ops["运维流"]
        O1[Docker Compose 编排]
        O2[Nacos/Sentinel 部署]
        O3[CI/CD Pipeline]
        O4[监控面板]
    end

    C1 --> B6
    C2 --> B1
    C2 --> B3
    C3 --> B7
    C4 --> B1
    C4 --> B3

    B1 --> I1
    B6 --> I1
    B3 --> I2
    B6 --> I2
    B6 --> I3

    O1 --> O2
    O2 --> B6
    O3 --> B1
    O3 --> B3
```

**并行原则**：
1. **契约先行**：网关 Header 协议（X-Tenant-Id / X-User-Id / X-Job-Id / X-Features）在 Phase 0 冻结
2. **核心业务不等待**：核心引擎开发使用 Mock 认证（`X-User-Id: mock-user-1`），不依赖外骨骼就绪
3. **支付沙箱优先**：Stripe Test Mode + Jeepay 沙箱环境在 Phase 0 即配置好
4. **每个服务独立可测**：认证/计费/网关各自有独立测试套件，不交叉依赖

### 2.3 与核心业务的集成节奏

```
外骨骼 Phase 1 完成（认证就绪）
  → 核心业务可从 Mock 认证切换为真实 JWT 认证
  → 只需信任 X-User-Id / X-Tenant-Id Header
  → 核心代码零修改

外骨骼 Phase 2 完成（计费就绪）
  → 核心 API 调用开始消耗 RP
  → 网关自动完成 RP 扣除
  → 核心代码零修改

外骨骼 Phase 3 完成（网关就绪）
  → 所有流量经过网关 Filter Chain
  → 限流/熔断/审计全部生效
  → 核心代码零修改
```

---

## 3. 阶段详细计划

### Phase 0: 基础设施与契约冻结（第 1-2 周）

**目标**：搭建 Maven 多模块项目骨架、Docker Compose 开发环境、数据库 Schema、冻结网关 Header 协议。

**交付物**：

| 交付物 | 模块 | 验收标准 |
|--------|------|---------|
| Maven 多模块项目 | `exoskeleton/` | `mvn clean compile` 全部模块通过 |
| Docker Compose 开发环境 | `exoskeleton/docker-compose.yml` | `docker compose up -d` 启动 PostgreSQL + Redis + Nacos + Logto |
| 数据库 Schema v0 | Flyway 迁移脚本 | 全部 9 张表（tenants/users/plans/subscriptions/rp_transactions/api_keys/tenant_configs/audit_logs/webhook_events）可迁移/回滚 |
| 网关 Header 协议文档 | `05-gateway-integration.md` | 6 个 Header 定义冻结，与核心业务团队确认 |
| CI/CD Pipeline | GitHub Actions | 自动编译 + 测试 + 代码检查 |
| `exoskeleton-common` 模块 | AuthContext / AuthContextHolder / 基础异常类 | 所有模块可依赖 |

**并行工作流**：

```mermaid
flowchart LR
    subgraph Week1["第 1 周"]
        A[Maven 项目骨架] --> B[模块依赖图]
        C[DB Schema 设计] --> D[Flyway 迁移脚本]
        E[Docker Compose 编排] --> F[基础设施启动]
    end

    subgraph Week2["第 2 周"]
        B --> G[common 模块交付]
        D --> H[Schema 冻结]
        F --> I[DevEnv 可用]
        G --> J[CI/CD 首个 Pipeline]
        H --> K[Header 协议签署]
    end

    style G fill:#e3f2fd,stroke:#1565c0,stroke-width:3px
    style H fill:#e3f2fd,stroke:#1565c0,stroke-width:3px
    style K fill:#e3f2fd,stroke:#1565c0,stroke-width:3px
```

**风险缓解**：
- 第 1 周末：Maven 模块间无循环依赖，所有模块能独立编译
- 第 2 周：Header 协议与核心业务团队联合评审，双方签字确认
- Docker Compose 必须能在 macOS 和 Linux 上同时启动

**升级路径**：Phase 0 完成后，认证/计费/网关可以并行启动开发。

---

### Phase 1: 认证与多租户（第 3-6 周）

**目标**：完成用户注册/登录/认证全流程、多租户数据隔离、API Key 管理。这是外骨骼最核心的能力。

**交付物**：

| 交付物 | 模块 | 验收标准 |
|--------|------|---------|
| Spring Security OAuth2 配置 | `exoskeleton-auth` | JWT 签名/过期/issuer 校验通过，角色提取正确 |
| Logto OIDC 集成 | `exoskeleton-auth` | 注册/登录/Token 刷新全流程可用 |
| 用户 JIT 预创建 | `exoskeleton-tenant` | 首次 API 请求自动创建用户，幂等 |
| AuthContext / AuthContextHolder | `exoskeleton-common` | ThreadLocal 正确设置/清除，无内存泄漏 |
| MyBatis-Plus 租户拦截器 | `exoskeleton-tenant` | 全部 SQL 自动追加 `WHERE tenant_id = ?` |
| 租户入驻流程 | `exoskeleton-tenant` | Super Admin 创建租户 → 自动创建 Logto 租户 + 管理员 |
| API Key CRUD | `exoskeleton-auth` | 创建/查看前缀/撤销/使用统计 |
| 认证上下文 Filter | `exoskeleton-gateway` | JWT 校验通过后正确注入 X-User-Id, X-Tenant-Id |

**并行工作流**：

```mermaid
flowchart TB
    subgraph AuthService["认证服务"]
        A1[Spring Security 骨架] --> A2[Logto OIDC 对接]
        A2 --> A3[JWT Claim 解析]
        A3 --> A4[角色提取]
    end

    subgraph TenantService["租户服务"]
        T1[User JIT 创建] --> T2[TenantLineInnerInterceptor]
        T2 --> T3[租户入驻 API]
        T3 --> T4[Logto Admin API 集成]
    end

    subgraph Gateway["网关层"]
        G1[JwtAuthFilter] --> G2[TenantHeaderFilter]
        G2 --> G3[AuthContext 注入]
    end

    subgraph Testing["测试验证"]
        V1[JWT 校验测试] --> V2[租户隔离测试]
        V2 --> V3[API Key 认证测试]
        V3 --> V4[端到端认证流程]
    end

    A4 --> G1
    T2 --> G2
    G3 --> V4

    AuthService --> Milestone1
    TenantService --> Milestone1
    Gateway --> Milestone1
    Testing --> Milestone1

    Milestone1["🎯 Phase 1 里程碑<br/>认证与多租户可用"]

    style Milestone1 fill:#e1f5e1,stroke:#2e7d32,stroke-width:3px
```

**关键路径**：Spring Security 配置 → Logto 集成 → JWT 校验 → 租户拦截器 → 端到端认证

**风险缓解**：
- **Week 3**：优先验证 Logto JWT 签发和 Spring Security 校验的密钥配对，这是最易出错的环节
- **Week 4**：租户拦截器接入 SQL 日志，人工抽查全部 SQL 是否包含 `WHERE tenant_id`
- **Week 5-6**：API Key 的 bcrypt 哈希比对性能测试，确保不影响请求延迟

**阶段交付形态**：
- 用户可注册/登录（邮箱 + GitHub OAuth + Google OAuth）
- 每个用户属于一个租户，所有数据自动隔离
- API Key 可用于 CLI/SDK 访问
- 网关向业务服务正确注入 X-User-Id 和 X-Tenant-Id

**升级开关**：`auth.enabled=true`（默认），关闭后进入无认证模式（仅开发环境）。

---

### Phase 2: 计费与支付（第 7-12 周）

**目标**：完成订阅计划、Stripe + Jeepay 支付集成、RP 积分系统的完整闭环。

**交付物**：

| 交付物 | 模块 | 验收标准 |
|--------|------|---------|
| 统一支付抽象 (PaymentService) | `exoskeleton-billing` | StripePaymentService / JeepayPaymentService 实现同一接口 |
| Stripe 集成 | `exoskeleton-billing` | PaymentIntent 创建 → 3DS 认证 → Webhook 回调 → 订阅状态更新 |
| Jeepay 集成 | `exoskeleton-billing` | 支付宝/微信支付 → 回调验签 → 订单状态更新 |
| 支付策略路由 (PaymentRouter) | `exoskeleton-billing` | 根据支付方式 + 币种自动选择 Stripe 或 Jeepay |
| Webhook 幂等处理 | `exoskeleton-billing` | event_id 唯一约束，重复事件返回 `already_processed` |
| RP 服务 (@Transactional) | `exoskeleton-billing` | 余额不足抛异常回滚，并发扣除无超卖 |
| 订阅状态机 | `exoskeleton-billing` | active/past_due/cancelled/expired/trialing 完整流转 |
| XXL-JOB 定时任务 | `exoskeleton-scheduler` | 月度 RP 发放 + 余额过期检查 + Webhook 重试 |
| RP 消费网关过滤器 | `exoskeleton-gateway` | 按 API 路径自动扣除 RP，余额不足返回 402 |
| 功能门控过滤器 | `exoskeleton-gateway` | 检查套餐 features JSONB，不满足返回 403 |

**并行工作流**：

```mermaid
flowchart TB
    subgraph Payment["支付层"]
        P1[统一接口抽象] --> P2[Stripe SDK 集成]
        P1 --> P3[Jeepay SDK 集成]
        P2 --> P4[Webhook 处理]
        P3 --> P4
        P4 --> P5[幂等性验证]
    end

    subgraph Billing["计费层"]
        B1[订阅状态机] --> B2[RP 余额引擎]
        B2 --> B3[RP 事务审计]
        B3 --> B4[月度发放任务]
    end

    subgraph GatewayBilling["网关计费"]
        G1[RP 消费过滤器] --> G2[功能门控过滤器]
        G2 --> G3[402/403 错误处理]
    end

    subgraph Integration["集成验证"]
        I1[Stripe 沙箱端到端] --> I2[Jeepay 沙箱端到端]
        I2 --> I3[支付→RP 发放]
        I3 --> I4[RP→消费→扣除]
    end

    P5 --> B1
    B4 --> I3
    G3 --> I4

    Payment --> Milestone2
    Billing --> Milestone2
    GatewayBilling --> Milestone2
    Integration --> Milestone2

    Milestone2["🎯 Phase 2 里程碑<br/>计费支付闭环"]

    style Milestone2 fill:#e1f5e1,stroke:#2e7d32,stroke-width:3px
```

**关键路径**：支付抽象 → Stripe 集成 → Webhook 处理 → RP 引擎 → 网关消费过滤器

**风险缓解**：
- **Week 7-8**：优先完成 Stripe Test Mode 的 PaymentIntent → Webhook 全流程，这是国际支付的主路径
- **Week 9-10**：Jeepay 沙箱环境需要中国服务器 IP 白名单，提前申请
- **Week 11**：RP 余额并发扣除用 JMeter 压测 1000 并发，验证 `@Transactional` + 行级锁无超卖
- **Week 12**：XXL-JOB 的任务幂等性验证——同一任务重复执行不重复发放 RP

**阶段交付形态**：
- 用户可选择订阅计划并完成支付（国际信用卡 / 支付宝 / 微信）
- 每月自动发放 RP 配额
- API 调用时网关自动扣除 RP
- 支付 Webhook 事件完整处理，支付状态实时更新

---

### Phase 3: 网关与集成协议（第 13-16 周）

**目标**：完成 Spring Cloud Gateway 完整 Filter Chain、Sentinel 限流熔断、Resilience4j 断路器、业务服务集成验证。

**交付物**：

| 交付物 | 模块 | 验收标准 |
|--------|------|---------|
| 路由配置 | `exoskeleton-gateway` | 外骨骼内部路由 + 业务服务路由全部正确 |
| 完整 Filter Chain | `exoskeleton-gateway` | 7 个 Filter 按序执行，顺序不可变 |
| Sentinel 限流规则 | `exoskeleton-gateway` | 租户级/用户级/全局级限流生效 |
| Resilience4j 断路器 | `exoskeleton-gateway` | 业务服务故障时正确熔断，半开恢复 |
| 审计日志 Filter | `exoskeleton-gateway` | 异步记录，不阻塞主流程 |
| Header 透传验证 | `exoskeleton-gateway` | X-User-Id/X-Tenant-Id/X-Request-Id/X-Features 正确到达业务服务 |
| Nacos 服务注册 | 全部模块 | 所有微服务在 Nacos 注册，健康检查通过 |
| SkyWalking 链路追踪 | 全部模块 | 跨服务调用链完整可见 |

**并行工作流**：

```mermaid
flowchart TB
    subgraph GatewayConfig["网关配置"]
        C1[路由表] --> C2[Filter Chain 顺序]
        C2 --> C3[Sentinel 规则]
        C3 --> C4[断路器策略]
    end

    subgraph Integration["集成验证"]
        I1[网关→认证 联调] --> I2[网关→计费 联调]
        I2 --> I3[网关→管理API 联调]
        I3 --> I4[网关→业务服务 Header 透传]
    end

    subgraph Observability["可观测性"]
        O1[Nacos 注册中心] --> O2[SkyWalking 探针]
        O2 --> O3[全链路追踪]
    end

    subgraph StressTest["压力测试"]
        S1[限流规则验证] --> S2[熔断恢复验证]
        S2 --> S3[1000 QPS 稳定性]
    end

    C4 --> I1
    I4 --> S3
    O3 --> S3

    GatewayConfig --> Milestone3
    Integration --> Milestone3
    Observability --> Milestone3
    StressTest --> Milestone3

    Milestone3["🎯 Phase 3 里程碑<br/>网关全功能就绪"]

    style Milestone3 fill:#e1f5e1,stroke:#2e7d32,stroke-width:3px
```

**关键路径**：路由配置 → Filter Chain 顺序 → Sentinel 规则 → 业务服务集成 → 压力测试

**风险缓解**：
- **Week 13**：Filter Chain 顺序是最关键的设计——顺序错误可能导致鉴权绕过。写死 ordinal 常量（-1, 0, 10, 20, 30, 40, 50, 99）
- **Week 14-15**：Sentinel 规则先在日志模式运行 1 周，确认无误后再开启限流
- **Week 16**：业务服务 Header 透传测试——核心业务团队确认 X-Tenant-Id / X-User-Id 正确接收

**阶段交付形态**：
- 所有 API 请求经过完整的 Filter Chain（认证 → 租户 → 功能门控 → RP 扣除 → 限流 → 路由 → 审计）
- 业务服务故障时自动熔断，恢复后自动半开
- Nacos Dashboard 可见全部微服务健康状态
- SkyWalking 可追踪跨服务调用链

---

### Phase 4: 管理控制台与运维（第 17-20 周）

**目标**：完成管理 API、监控面板、运维工具，平台运营能力就绪。

**交付物**：

| 交付物 | 模块 | 验收标准 |
|--------|------|---------|
| 管理 REST API | `exoskeleton-admin` | 租户/用户/订阅/RP/审计 CRUD 全部可用 |
| RBAC 权限控制 | `exoskeleton-admin` | Super Admin / Tenant Admin / Support 三角色正确隔离 |
| 管理控制台前端骨架 | `admin/` | 登录 + 仪表板 + 租户列表 + 用户列表页面 |
| Prometheus + Grafana | 监控栈 | 微服务指标采集 + 仪表板 |
| Sentinel Dashboard | 限流管理 | 规则实时查看/修改 |
| XXL-JOB Dashboard | 调度管理 | 任务状态/日志/手动触发 |
| 告警规则 | Prometheus AlertManager | 服务宕机 / RP 异常消耗 / Webhook 失败率告警 |

**并行工作流**：

```mermaid
flowchart TB
    subgraph AdminAPI["管理 API"]
        A1[租户管理] --> A2[用户管理]
        A2 --> A3[订阅管理]
        A3 --> A4[RP 审计]
    end

    subgraph Frontend["管理前端"]
        F1[仪表板] --> F2[租户列表]
        F2 --> F3[用户列表]
        F3 --> F4[订阅/RP 管理]
    end

    subgraph Monitoring["监控栈"]
        M1[Prometheus 采集] --> M2[Grafana 面板]
        M2 --> M3[告警规则]
    end

    A4 --> M1
    F4 --> M3

    AdminAPI --> Milestone4
    Frontend --> Milestone4
    Monitoring --> Milestone4

    Milestone4["🎯 Phase 4 里程碑<br/>平台运营能力就绪"]

    style Milestone4 fill:#e1f5e1,stroke:#2e7d32,stroke-width:3px
```

**风险缓解**：
- **Week 17-18**：管理 API 的权限控制必须严格——Super Admin 可操作所有租户，Tenant Admin 只能操作自己租户
- **Week 19-20**：Grafana 面板至少包含：API QPS、P99 延迟、RP 消费速率、Webhook 成功率

**阶段交付形态**：
- 管理员可通过 Web 界面管理租户/用户/订阅
- Grafana 展示全平台实时运营指标
- 异常情况自动告警

---

### Phase 5: 生产加固（第 21-24 周）

**目标**：安全审计、性能优化、灾备方案、文档完善。系统达到生产就绪标准。

**交付物**：

| 交付物 | 模块 | 验收标准 |
|--------|------|---------|
| 安全审计 | 全部 | OWASP Top 10 扫描通过，无 CRITICAL 漏洞 |
| 性能优化 | 全部 | 网关 P99 < 50ms（不含业务调用），RP 扣除 P99 < 10ms |
| Nacos 集群 | 基础设施 | 3 节点集群 + MySQL 持久化 |
| PostgreSQL 主从 | 基础设施 | 读写分离 + 自动故障切换 |
| Redis Sentinel | 基础设施 | 哨兵模式 + 自动故障转移 |
| 灾备演练 | 全部 | 数据库恢复 < 30 分钟，服务自愈 < 5 分钟 |
| API 文档 | 全部 | OpenAPI 3.0 规范，Swagger UI 可访问 |
| 运维手册 | 全部 | 部署/监控/告警/故障处理完整文档 |

**并行工作流**：

```mermaid
flowchart TB
    subgraph Security["安全加固"]
        S1[OWASP 扫描] --> S2[漏洞修复]
        S2 --> S3[渗透测试]
    end

    subgraph Performance["性能优化"]
        P1[网关压测] --> P2[DB 查询优化]
        P2 --> P3[缓存策略]
    end

    subgraph HA["高可用"]
        H1[Nacos 集群] --> H2[PG 主从]
        H2 --> H3[Redis Sentinel]
        H3 --> H4[灾备演练]
    end

    subgraph Docs["文档"]
        D1[API 文档] --> D2[运维手册]
        D2 --> D3[部署文档]
    end

    S3 --> Milestone5
    P3 --> Milestone5
    H4 --> Milestone5
    D3 --> Milestone5

    Milestone5["🎯 Phase 5 里程碑<br/>生产就绪"]

    style Milestone5 fill:#fce4ec,stroke:#c62828,stroke-width:3px
```

**风险缓解**：
- **Week 21-22**：安全审计发现 CRITICAL 漏洞必须立即修复，HIGH 漏洞必须在 Phase 5 结束前关闭
- **Week 23**：灾备演练必须实际执行一次完整恢复流程，不允许"理论可行"
- **Week 24**：运维手册必须包含"常见故障处理"章节，覆盖至少 10 个故障场景

**阶段交付形态**：
- 系统可在生产环境稳定运行
- 安全扫描通过，高可用架构就绪
- 运维文档完整，新人可按手册独立部署

---

## 4. 全局依赖与甘特图

### 4.1 服务依赖图

```mermaid
graph TB
    subgraph P0["Phase 0"]
        p0_common[exoskeleton-common]
        p0_db[DB Schema]
        p0_docker[Docker Compose]
    end

    subgraph P1["Phase 1"]
        p1_auth[认证服务]
        p1_tenant[租户服务]
        p1_api_key[API Key 管理]
    end

    subgraph P2["Phase 2"]
        p2_stripe[Stripe 集成]
        p2_jeepay[Jeepay 集成]
        p2_rp[RP 引擎]
        p2_scheduler[XXL-JOB 任务]
    end

    subgraph P3["Phase 3"]
        p3_gateway[Gateway Filter Chain]
        p3_sentinel[Sentinel 限流]
        p3_breaker[Resilience4j 断路器]
        p3_header[Header 透传验证]
    end

    subgraph P4["Phase 4"]
        p4_admin[管理 API]
        p4_monitor[Prometheus + Grafana]
        p4_alert[告警规则]
    end

    subgraph P5["Phase 5"]
        p5_ha[Nacos 集群 + PG 主从 + Redis Sentinel]
        p5_security[安全审计]
        p5_perf[性能优化]
        p5_docs[运维文档]
    end

    p0_common --> p1_auth
    p0_common --> p1_tenant
    p0_db --> p1_auth
    p0_db --> p1_tenant

    p1_auth --> p2_rp
    p1_tenant --> p2_rp
    p1_auth --> p3_gateway
    p1_tenant --> p3_gateway

    p2_rp --> p3_gateway
    p2_stripe --> p2_rp
    p2_jeepay --> p2_rp

    p3_gateway --> p3_sentinel
    p3_gateway --> p3_breaker
    p3_gateway --> p3_header

    p3_gateway --> p4_admin
    p3_sentinel --> p4_monitor

    p4_admin --> p5_security
    p4_monitor --> p5_perf
    p3_gateway --> p5_ha
```

### 4.2 甘特图

```mermaid
gantt
    title 外骨骼系统 v1.0 开发路线图（24周）
    dateFormat  YYYY-MM-DD
    axisFormat  %m/%d

    section Phase 0
    Maven多模块项目        :p0_1, 2026-04-28, 1w
    Docker Compose环境      :p0_2, 2026-04-28, 1w
    DB Schema + Flyway     :p0_3, 2026-04-28, 2w
    Header协议冻结          :p0_4, 2026-05-05, 1w
    CI/CD Pipeline         :p0_5, 2026-04-28, 2w
    Phase0验收             :milestone, p0_m, after p0_3, 0d

    section Phase 1
    Spring Security + Logto :p1_1, after p0_3, 3w
    租户拦截器              :p1_2, after p0_3, 2w
    API Key管理             :p1_3, after p1_1, 1w
    网关Auth Filter         :p1_4, after p1_1, 1w
    端到端认证测试          :p1_5, after p1_4, 1w
    Phase1验收             :milestone, p1_m, after p1_5, 0d

    section Phase 2
    统一支付抽象            :p2_1, after p1_2, 1w
    Stripe集成              :p2_2, after p2_1, 3w
    Jeepay集成              :p2_3, after p2_1, 3w
    Webhook处理             :p2_4, after p2_2, 1w
    RP引擎                  :p2_5, after p2_2, 2w
    XXL-JOB定时任务         :p2_6, after p2_5, 1w
    网关消费/门控过滤器     :p2_7, after p2_5, 1w
    Phase2验收             :milestone, p2_m, after p2_7, 0d

    section Phase 3
    路由配置                :p3_1, after p2_m, 1w
    Filter Chain完成        :p3_2, after p3_1, 2w
    Sentinel规则            :p3_3, after p3_2, 1w
    Resilience4j断路器      :p3_4, after p3_2, 1w
    Nacos + SkyWalking      :p3_5, after p2_m, 2w
    Header透传验证          :p3_6, after p3_2, 1w
    压力测试                :p3_7, after p3_6, 1w
    Phase3验收             :milestone, p3_m, after p3_7, 0d

    section Phase 4
    管理REST API            :p4_1, after p3_m, 2w
    管理前端骨架            :p4_2, after p4_1, 2w
    Prometheus + Grafana    :p4_3, after p3_m, 2w
    告警规则                :p4_4, after p4_3, 1w
    Phase4验收             :milestone, p4_m, after p4_4, 0d

    section Phase 5
    安全审计                :p5_1, after p4_m, 2w
    性能优化                :p5_2, after p4_m, 2w
    Nacos/PG/Redis高可用    :p5_3, after p4_m, 3w
    灾备演练                :p5_4, after p5_3, 1w
    API文档 + 运维手册      :p5_5, after p4_m, 2w
    Phase5验收             :milestone, p5_m, after p5_5, 0d
```

---

## 5. 团队与执行

### 5.1 团队分工

| 角色 | 人数 | 负责模块 | 活跃阶段 |
|------|------|---------|---------|
| **平台工程师 (认证)** | 1人 | Spring Security / Logto / API Key / AuthContext | Phase 0-3 |
| **平台工程师 (租户)** | 1人 | MyBatis-Plus / 租户隔离 / 用户 JIT | Phase 0-3 |
| **平台工程师 (计费)** | 1人 | Stripe / Jeepay / RP 引擎 / Webhook | Phase 2-4 |
| **平台工程师 (网关)** | 1人 | Gateway / Filter Chain / Sentinel / Resilience4j | Phase 3-4 |
| **DevOps** | 1人 | Docker / CI/CD / Nacos / SkyWalking / 高可用 | Phase 0, 5 |
| **前端工程师** | 1人 | 管理控制台前端 (React + Ant Design) | Phase 4 |

> 注：此团队可与核心业务团队共享人员，但两个系统独立开发、独立仓库、独立 CI/CD。

### 5.2 每周并行任务示例（Phase 2 第 1 周）

```mermaid
flowchart LR
    subgraph Mon["周一"]
        M1[认证工程师: 认证上下文传递到计费服务]
        M2[租户工程师: 租户表关联 users 表]
        M3[计费工程师: PaymentService 接口定义]
        M4[DevOps: Stripe Webhook 本地隧道配置]
    end

    subgraph Wed["周三"]
        W1[认证工程师: AuthContext Filter 调试]
        W2[租户工程师: ignoreTable 配置验证]
        W3[计费工程师: Stripe PaymentIntent 首次请求]
        W4[DevOps: Jeepay 沙箱环境申请]
    end

    subgraph Fri["周五"]
        F1[认证工程师: 集成测试编写]
        F2[租户工程师: 跨租户访问拦截测试]
        F3[计费工程师: Stripe SDK 错误处理]
        F4[DevOps: 本地 HTTPS 证书配置]
    end

    Mon --> Wed --> Fri

    style Mon fill:#e3f2fd,stroke:#1565c0
    style Wed fill:#fff3e0,stroke:#ef6c00
    style Fri fill:#e1f5e1,stroke:#2e7d32
```

---

## 6. 里程碑验收标准

### Milestone 1：认证与多租户可用（Phase 1 结束）

- [ ] Logto 注册/登录全流程可用（邮箱 + GitHub + Google）
- [ ] JWT 签发/校验/过期处理正确
- [ ] 租户拦截器对全部表（除 plans/webhook_events）注入 WHERE tenant_id
- [ ] API Key 创建/撤销/使用统计可用
- [ ] 网关向业务服务正确注入 X-User-Id, X-Tenant-Id
- [ ] 跨租户访问被正确拦截（403）

### Milestone 2：计费支付闭环（Phase 2 结束）

- [ ] Stripe Test Mode PaymentIntent → Webhook → 订阅激活全流程
- [ ] Jeepay 沙箱支付宝/微信支付 → 回调 → RP 到账
- [ ] 1000 并发 RP 扣除无超卖
- [ ] XXL-JOB 月度发放准确、不重复
- [ ] 网关 RP 消费过滤器正确扣除，余额不足返回 402
- [ ] 功能门控按套餐 features 正确拦截

### Milestone 3：网关全功能就绪（Phase 3 结束）

- [ ] 7 个 Filter 按序执行，无绕过
- [ ] Sentinel 限流规则生效，超限返回 429
- [ ] Resilience4j 断路器在业务服务故障时正确熔断
- [ ] 审计日志异步记录完整
- [ ] 1000 QPS 持续 10 分钟无 5xx 错误
- [ ] SkyWalking 链路追踪跨服务完整

### Milestone 4：平台运营能力就绪（Phase 4 结束）

- [ ] 管理 API 完整可用（租户/用户/订阅/RP CRUD）
- [ ] 管理控制台前端可登录 + 查看仪表板 + 管理租户
- [ ] Prometheus + Grafana 监控面板展示核心指标
- [ ] 服务宕机/Sentinel 限流触发告警通知

### Milestone 5：生产就绪（Phase 5 结束）

- [ ] OWASP Top 10 扫描无 CRITICAL 漏洞
- [ ] 网关 P99 < 50ms（不含业务调用）
- [ ] Nacos 集群 + PostgreSQL 主从 + Redis Sentinel 可用
- [ ] 灾备演练：数据库恢复 < 30 分钟，服务自愈 < 5 分钟
- [ ] API 文档 + 运维手册完整

---

## 7. 风险应急计划

### 7.1 红色风险应急预案

| 风险场景 | 触发条件 | 应急措施 | 影响 |
|---------|---------|---------|------|
| Logto OIDC 集成失败 | JWT 校验连续失败 | 切换为 Keycloak，1 周缓冲期 | Phase 1 延长 1 周 |
| 租户数据泄漏 | 跨租户查询返回非本租户数据 | 立即冻结网关，逐表审计 SQL 日志 | Phase 1 延长 2 周 |
| Stripe Webhook 签名校验失败 | 回调数据被篡改 | 回退到手动确认支付状态，联系 Stripe Support | Phase 2 延长 1 周 |
| RP 并发超卖 | 压测发现余额负数 | 引入 Redis 分布式锁 + DB 乐观锁双重保障 | Phase 2 延长 1 周 |
| Gateway Filter 顺序错误 | 鉴权绕过漏洞 | 立即回滚 Filter Chain 配置，编写 Filter 顺序集成测试 | Phase 3 延长 1 周 |
| 业务服务 Header 不兼容 | 核心业务无法读取 X-Tenant-Id | 网关临时添加 JSON Body 注入兼容模式 | 不影响外骨骼进度 |

### 7.2 范围收缩策略

若进度落后，按以下优先级收缩范围：

```mermaid
graph LR
    A[按期交付完整外骨骼] -->|落后<1周| B[优先保证认证+网关可用]
    B -->|落后1-2周| C[牺牲 Jeepay，仅保留 Stripe]
    C -->|落后2-3周| D[牺牲管理前端，仅保留管理API]
    D -->|落后>3周| E[牺牲高可用，单机先行]

    B --> B1[保留: JWT+多租户+网关+Stripe]
    C --> C1[保留: JWT+多租户+网关+Stripe]
    D --> D1[保留: JWT+多租户+网关+Stripe+管理API]
    E --> E1[保留: 全部功能但单机部署]

    style A fill:#e1f5e1,stroke:#2e7d32
    style E fill:#ffebee,stroke:#c62828
```

**核心原则**：认证和网关是整个外骨骼的脊梁，这两项绝对不能收缩。

---

## 8. 与核心业务的集成检验点

| 外骨骼阶段 | 检验内容 | 核心业务配合 |
|-----------|---------|------------|
| Phase 1 完成 | 核心业务能否通过 X-User-Id 识别用户 | 读取 Header 替代 Mock 认证 |
| Phase 2 完成 | 核心 API 调用是否正确触发 RP 扣除 | 确认 RP 扣除不阻塞业务响应 |
| Phase 3 完成 | 限流/熔断不影响正常业务调用 | 配合压力测试 |
| Phase 4 完成 | 管理后台可查看核心业务的审计日志 | audit_logs 表包含核心 API 记录 |

---

## 9. 成功度量

| 维度 | 指标 | 目标值 |
|------|------|--------|
| **安全** | OWASP 漏洞数 | 0 CRITICAL, 0 HIGH |
| **性能** | 网关 P99 延迟 | < 50ms |
| **性能** | RP 扣除 P99 延迟 | < 10ms |
| **可靠性** | 网关可用性 | 99.9% |
| **隔离** | 跨租户数据泄漏 | 0 次 |
| **支付** | Webhook 处理成功率 | > 99.5% |
| **审计** | 审计日志完整性 | 100% |

---

**文档结束。**

> **使用说明**：本文档是外骨骼系统的独立工程路线图，与核心业务路线图（`docs/core/planning/development-roadmap.md`）完全并行。两个系统通过网关 Header 协议集成，互不阻塞。甘特图日期基于 2026-04-28 起算。
