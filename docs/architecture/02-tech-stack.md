# 02. 技术栈能力匹配

> NSCA 外骨骼基于 yudao-cloud 技术栈二次开发，复用其成熟的组件选型和版本管理。本章说明 yudao 已提供的能力、NSCA 新增的选型，以及从当前栈到目标栈的迁移路径。

## 2.1 yudao-cloud 当前技术栈

yudao-cloud 已选型并验证的核心依赖（NSCA 直接复用）：

| 能力 | yudao 选型 | 版本 | 说明 |
|------|----------|------|------|
| **基础框架** | Spring Boot + Spring Framework | 2.7.18 / 5.3.39 | 国内 Java 生态最广泛验证版本 |
| **微服务体系** | Spring Cloud + Spring Cloud Alibaba | 2021.0.9 / 2021.0.6.2 | 含 Nacos 2.x、Sentinel、Gateway |
| **服务注册 + 配置中心** | Nacos | 2.x | 注册+配置二合一，支持 CP/AP 切换 |
| **API 网关** | Spring Cloud Gateway | 2021.x | 响应式非阻塞，与 Sentinel 无缝集成 |
| **限流 / 熔断 / 降级** | Sentinel | 1.8.x | 实时 Dashboard，动态规则推送 |
| **ORM + 多租户** | MyBatis-Plus + TenantLineInnerInterceptor | 3.5.15 | 租户拦截器自动注入 WHERE 条件 |
| **认证** | Spring Security + OAuth2 Resource Server | 5.8.16 | 框架级安全防护 |
| **社交登录** | JustAuth | 1.16.7 | 国内平台开箱即用（GitHub/微信/钉钉等） |
| **API 文档** | SpringDoc + Knife4j | 1.8.0 / 4.5.0 | OpenAPI 3.0 兼容 |
| **连接池** | Druid | 1.2.27 | 国内生产环境广泛验证 |
| **缓存 + 分布式锁** | Redisson | 3.52.0 | Redis 客户端 + 分布式锁 |
| **分布式调度** | XXL-JOB | 2.4.0 | 分片、失败重试、Dashboard 管理 |
| **分布式追踪** | SkyWalking | 8.12.0 | 无侵入 agent，线程级追踪 |
| **工具库** | Hutool 5 + Guava + Lombok + MapStruct | — | 国内 Java 标准工具组合 |
| **工作流引擎** | Flowable | 6.8.0 | 审批流程（按需启用） |
| **消息队列** | RocketMQ Spring | 2.3.5 | 异步事件（按需启用） |
| **数据库** | MySQL 8.0 | — | 主库，yudao 默认存储 |
| **Java** | JDK 8 | 1.8 | yudao 当前基线 |

> **yudao-dependencies** 通过统一的 BOM 管理上述所有依赖版本，NSCA 扩展模块继承该 BOM，不引入版本碎片化。

### 2.1.1 yudao 单体 vs 微服务部署

yudao 支持两种部署模式：

| 部署模式 | 说明 | NSCA 阶段 |
|---------|------|---------|
| **单体（yudao-server）** | 所有模块合并为一个 Spring Boot JAR，Nacos 禁用 | 开发期 + MVP |
| **微服务** | 每个模块独立部署，Nacos 注册发现 | 生产扩展期 |

yudao-server 在 `application.yaml` 中默认禁用 Nacos 注册发现：

```yaml
spring:
  cloud:
    nacos:
      discovery:
        enabled: false   # 单体模式禁用
      config:
        enabled: false
```

NSCA 开发阶段复用单体模式降低环境复杂度，生产环境按需切换为微服务部署。

## 2.2 技术栈迁移路径

yudao 当前栈（JDK 8 + Spring Boot 2.7）是经过大规模生产验证的稳定基线，但 Spring Boot 2.7 已于 2023/11 停止 OSS 支持。NSCA 的迁移策略如下：

| 阶段 | Java | Spring Boot | 数据库 | 时间 |
|------|------|------------|--------|------|
| **Phase 1: 基于 yudao 基线** | JDK 8 | 2.7.18 | MySQL 8.0 | 当前 |
| **Phase 2: JDK 升级** | JDK 17 | 2.7.18 | MySQL 8.0 | NSCA v1.1 |
| **Phase 3: Boot 升级** | JDK 17 | 3.x | MySQL 8.0 | NSCA v1.2 |
| **Phase 4: JDK 21 + PostgreSQL** | JDK 21 | 3.x | PostgreSQL 16 | NSCA v2.0 |

### Phase 1 技术策略（当前）

- **不修改 yudao 的 JDK/Spring Boot 版本**，直接在其上进行业务扩展
- 新增模块（member 扩展、pay 扩展、community）使用 JDK 8 + Spring Boot 2.7.18
- 新增依赖（如 Stripe SDK）需验证 JDK 8 兼容性
- 使用 yudao 提供的 MySQL 8.0 + Druid + MyBatis-Plus 数据访问层

### Phase 2-4 的迁移重点

- Spring Boot 3.x 要求 `javax.*` → `jakarta.*` 包名变更（yudao 社区已有迁移分支）
- Spring Security 6.x 的 API 变更（`WebSecurityConfigurerAdapter` 已移除）
- Nacos 2.2+ 对 Spring Boot 3.x 的原生支持
- PostgreSQL 16 替代 MySQL 的 SQL 兼容性适配（yudao 已内置多数据库方言支持）

> **yudao 厂商已规划 Spring Boot 3.x + JDK 17 迁移分支**，NSCA 跟随社区节奏升级，避免过早投入迁移成本。

## 2.3 选型论证

### 为什么在 yudao 基础上扩展，而非替换组件？

| yudao 组件 | 论证 |
|-----------|------|
| **MyBatis-Plus** | 多租户拦截器开箱即用，国内生态事实标准。yudao 已有的 BaseMapper/Service 层直接复用到 NSCA 扩展 DO |
| **Nacos** | 已在 yudao 中集成并验证。单体阶段禁用，微服务阶段一键启用即可 |
| **Sentinel** | 已在 yudao-gateway 中集成。NSCA 只需新增限流规则，不需替代组件 |
| **XXL-JOB** | 已在 yudao 中集成。NSCA 每日 RP 衰减、发票自动生成等定时任务直接注册 |
| **SkyWalking** | 已在 yudao 中配置。NSCA 服务自动纳入追踪，无需额外工作 |
| **Spring Security** | yudao 已实现 OAuth2 资源服务器 + Token 存储。NSCA 扩展 Token 格式和验证逻辑 |

### 为什么新增 Logto 而非完全依赖 yudao 社交登录？

yudao 的 JustAuth 库覆盖国内社交平台（微信、钉钉、GitHub 等），但 NSCA 额外需要：
- 企业 SSO（OIDC 协议）— JustAuth 不覆盖
- 多租户 OIDC 提供方 — Logto 原生支持
- 面向国际用户的 UI — Logto 内置 i18n

Logto 作为外部 OIDC 提供方，与 yudao 的 Spring Security OAuth2 集成，**两者互补而非替代**。

### 为什么新增 Stripe SDK 而非完全依赖 Jeepay？

yudao 通过 yudao-module-pay 的 Jeepay 渠道支持支付宝/微信支付。NSCA 面向国际市场，需要：
- 信用卡/借记卡支付 → Stripe Payment Intents
- 订阅/周期性付款 → Stripe Billing + Webhook
- 119 种货币 → Stripe 原生多币种

Stripe 作为**新增支付渠道**加入 yudao-module-pay 的渠道体系，与 Jeepay 并行，复用 yudao 的统一订单模型。

## 2.4 NSCA 新增技术选型

以下选型为 NSCA 在 yudao 基础上的增量引入：

| 能力需求 | 选型 | 版本 | JDK 8 兼容 | 选型理由 |
|---------|------|------|-----------|---------|
| **OIDC 认证提供方** | Logto | latest | 不相关（独立部署） | 开源 OIDC，内置多租户，管理 UI 开箱即用 |
| **Stripe 支付** | stripe-java | 25.x (JDK 8) | 是 | Stripe 官方 SDK。注意：stripe-java 26.x+ 要求 JDK 17，NSCA 暂用 25.x |
| **数据迁移** | Flyway | 9.x (JDK 8) | 是 | yudao 已引入 Flyway，NSCA 添加独立 migration 脚本 |
| **对象存储** | yudao OSS 抽象层 | — | 是 | 直接复用 yudao-infra 的文件服务，对接 S3/MinIO/阿里云 OSS |
| **链路追踪** | SkyWalking | 8.12.0 | 是 | yudao 已集成，NSCA 零工作直接受益 |
| **社区富文本编辑** | Tiptap | latest | 不相关（前端） | 无头编辑器，支持 Markdown + 富文本，XSS 安全 |
| **社区搜索** | Elasticsearch | 7.17+ | 不相关（独立部署） | 全文搜索、聚合统计 |

> **NSCA 新增选型原则**：优先使用 yudao 已有组件，仅在 yudao 无法满足时新增。新增组件需验证与 JDK 8 的兼容性。Logto、Stripe、Elasticsearch 均为独立部署的**外部服务**，与 Java 运行时版本解耦。

## 2.5 技术栈全景

```
┌──────────────────────────────────────────────────────────────────────┐
│                       NSCA 外骨骼技术栈全景                              │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  yudao 基座（直接复用）                                                  │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │  Spring Boot 2.7.18 + Spring Cloud 2021.0.9 + JDK 8        │     │
│  │  MyBatis-Plus 3.5.15 + Redisson 3.52 + XXL-JOB 2.4         │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  网关层                                                               │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │  Spring Cloud Gateway（复用 yudao-gateway）                    │     │
│  │  Sentinel 限流/熔断（复用）                                    │     │
│  │  → 扩展：JWT RS256 校验 + API Key 校验 + RP 预扣检查           │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  服务层                                                               │
│  ┌──────────────┬──────────────┬──────────────┬────────────────┐    │
│  │  认证/授权     │  计费/订阅     │  支付           │  社区            │    │
│  │  Spring      │  yudao-member │  yudao-pay     │  yudao-module-  │    │
│  │  Security    │  + 扩展        │  + Stripe      │  community      │    │
│  │  + Logto     │  (rp_*/       │  (新增渠道)     │  (新建模块)      │    │
│  │  (互补)      │   subscription)│                │                 │    │
│  └──────────────┴──────────────┴──────────────┴────────────────┘    │
│                                                                      │
│  基础设施层（yudao 提供，NSCA 直接使用）                                  │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │  Nacos (注册+配置，单体阶段禁用) │ XXL-JOB (调度)               │     │
│  │  MySQL 8.0 (yudao) │ Redis 7 (Redisson) │ SkyWalking (追踪)  │     │
│  │  Flyway (迁移) │ Caffeine (本地缓存) │ 工作流: Flowable        │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  NSCA 新增外部服务                                                      │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │  Logto (OIDC) │ Stripe (国际支付) │ Elasticsearch (社区搜索)    │     │
│  │  ↓ Phase 4 升级                                                │     │
│  │  PostgreSQL 16 + JDK 21 + Spring Boot 3.x                      │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  集成边界                                                              │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │  外骨骼 ←→ 核心引擎：仅通过 HTTP Header                       │     │
│  │  X-Tenant-Id | X-User-Id | X-Job-Id | X-Features           │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## 2.6 版本兼容性声明

### 当前（Phase 1）

| 组件 | 版本 | 来源 |
|------|------|------|
| Spring Boot | 2.7.18 | yudao-dependencies |
| Spring Cloud | 2021.0.9 | yudao-dependencies |
| Spring Cloud Alibaba | 2021.0.6.2 | yudao-dependencies |
| Spring Framework | 5.3.39 | yudao-dependencies |
| Spring Security | 5.8.16 | yudao-dependencies |
| MyBatis-Plus | 3.5.15 | yudao-dependencies |
| Java | 8 | yudao 基线 |
| MySQL | 8.0 | yudao 默认 |
| Redis | 7.x | Redisson 3.52.0 |

### 目标（Phase 4）

| 组件 | 版本 | 说明 |
|------|------|------|
| Spring Boot | 3.4.x | 与 Spring Cloud 2025.x 配套 |
| Spring Cloud | 2025.x | 最新稳定版 |
| Spring Cloud Alibaba | 2023.x | Spring Boot 3.x 兼容 |
| Java | 21 LTS | 虚拟线程 + Record + 模式匹配 |
| PostgreSQL | 16 | 替换 MySQL |
| Redis | 7.x | 不变 |

> **关键约束**：Phase 1 所有 NSCA 新增代码必须兼容 JDK 8。不使用 `var` 关键字、String `formatted()`、Record、Sealed Class 等 JDK 14+ 特性。Phase 2 升级 JDK 17 后，可以在新文件中逐步使用 `var`、Text Block、Sealed Class。

---

## 参考

- [yudao-cloud 官方文档](https://doc.iocoder.cn/)
- [Spring Boot 3.x Migration Guide](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.0-Migration-Guide)
- [Nacos 官方文档](https://nacos.io/docs/latest/)
- [MyBatis-Plus 多租户文档](https://baomidou.com/plugins/tenant/)
- [Stripe Java SDK](https://github.com/stripe/stripe-java)
- [Logto 官方文档](https://docs.logto.io/)
