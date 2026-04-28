# 02. 技术栈能力匹配

> Spring Cloud Alibaba 微服务生态与外骨骼每项能力的精确匹配论证。选型标准：生产就绪、社区活跃、Spring Boot 3.x 兼容、国内生态完备。

## 2.1 能力匹配矩阵

| 能力需求 | 选型 | 版本 | 选型理由 |
|---------|------|------|---------|
| **服务注册 + 配置中心** | Nacos | 2.4.x | 注册+配置二合一，支持 CP/AP 切换，国内生态最强 |
| **API 网关** | Spring Cloud Gateway | 2025.x | 响应式非阻塞，Spring 原生，与 Sentinel 无缝集成 |
| **限流 / 熔断 / 降级** | Sentinel | 1.8.x | 比 Hystrix 更丰富，实时 Dashboard，动态规则推送 |
| **认证** | Spring Security 6 + OAuth2 Resource Server | 6.x | 框架级安全防护，非手写中间件 |
| **外部 OIDC 提供方** | Logto | latest | 开源 OIDC，内置多租户，管理 UI 开箱即用 |
| **ORM + 多租户** | MyBatis-Plus + TenantLineInnerInterceptor | 3.5.x | 租户拦截器自动注入 WHERE 条件，零遗漏 |
| **Stripe 支付 (国际)** | stripe-java | 32.x | 官方 SDK，852 个 Release，Webhook 签名校验内置 |
| **中国支付 (支付宝/微信)** | Jeepay | 3.x | 6.1k stars，Spring Boot 3.x 原生，生产就绪 |
| **分布式调度** | XXL-JOB | 2.4.x | 分布式任务分片，失败重试，Dashboard 可视化管理 |
| **分布式追踪** | SkyWalking | 10.x | 线程级追踪，无侵入 agent，与 Spring Cloud Gateway 集成 |
| **数据库迁移** | Flyway | 10.x | 比 Liquibase 更轻，Spring Boot 内置 |
| **监控** | Spring Boot Actuator + Prometheus + Grafana | — | 业界标准，生态完备 |
| **分布式事务 (预留)** | Seata | 2.x | AT/TCC 模式，仅跨服务 RP 扣除场景按需启用 |
| **断路器 (业务服务保护)** | Resilience4j | 2.x | 轻量级，与 Spring Cloud Circuit Breaker 集成 |

## 2.2 选型论证

### 为什么选 Spring Cloud Alibaba 而非 Spring Cloud Netflix？

| 对比维度 | Netflix 栈 | Alibaba 栈 |
|---------|-----------|-----------|
| 服务注册 | Eureka 2.x (停更) | Nacos 2.4.x (活跃) |
| 配置中心 | Spring Cloud Config + Bus | Nacos Config (实时推送，无需 Bus) |
| 限流熔断 | Hystrix (停更) | Sentinel (实时 Dashboard + 动态规则) |
| Spring Boot 3.x 兼容 | 生态分裂 | **完全兼容** |
| 中文社区 | 薄弱 | **极强** (中文文档、钉钉群、RuoYi 生态) |

### 为什么选 MyBatis-Plus 而非纯 JPA/Hibernate？

| 对比维度 | Hibernate / JPA | MyBatis-Plus |
|---------|----------------|-------------|
| 多租户 | Hibernate Filter (需手写配置) | TenantLineInnerInterceptor (开箱即用) |
| 中国数据库兼容 (TiDB/OceanBase) | 方言兼容不稳定 | 多数项目直接使用，已有验证 |
| 复杂查询 (报表/聚合) | JPQL/HQL 局限 | 原生 SQL + 动态条件构造器 |
| 国内生态 (RuoYi/Jeepay) | 少 | **事实标准**，已有大量参考实现 |

### 为什么选 Logto 而非 Keycloak？

| 对比维度 | Keycloak | Logto |
|---------|----------|-------|
| 部署复杂度 | 重 (Java, 需调优) | 轻 (Node.js, Docker 一键) |
| 管理 UI | 传统，学习成本高 | 现代，开箱即用 |
| 多租户 | 通过 Realm 实现，配置重 | 内置，API 原生支持 |
| 国内生态 | 弱 | 强 (中文文档，国内团队) |

### 为什么选 XXL-JOB 而非 Quartz？

| 对比维度 | Quartz | XXL-JOB |
|---------|--------|---------|
| 分布式支持 | 需自行实现锁机制 | 原生分片，执行器自动注册 |
| 可视化管理 | 无 | Dashboard，任务日志、失败重试 |
| Spring Boot 集成 | 需额外配置 | 开箱即用 |
| 国内生态 | 弱 | **事实标准**，广泛验证 |

## 2.3 技术栈全景

```
┌─────────────────────────────────────────────────────────────────┐
│                     外骨骼技术栈全景                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  网关层                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Spring Cloud Gateway + Sentinel (限流/熔断)              │   │
│  │  Resilience4j (断路器)                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  服务层                                                          │
│  ┌───────────┬───────────┬───────────┬─────────────────────┐   │
│  │  认证      │  租户      │  计费      │  管理                │   │
│  │  Spring   │  MyBatis-  │  Stripe   │  Spring Boot        │   │
│  │  Security │  Plus      │  + Jeepay │  REST API            │   │
│  │  + Logto  │  拦截器     │  + RP     │                     │   │
│  └───────────┴───────────┴───────────┴─────────────────────┘   │
│                                                                 │
│  基础设施层                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Nacos (注册+配置) │ XXL-JOB (调度) │ SkyWalking (追踪)    │   │
│  │  PostgreSQL 16 │ Redis 7 │ Flyway (迁移)                  │   │
│  │  Prometheus + Grafana (监控)                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  集成边界                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  外骨骼 ←→ 核心业务：仅通过 HTTP Header                   │   │
│  │  X-Tenant-Id | X-User-Id | X-Job-Id | X-Features        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 2.4 版本兼容性声明

- **Spring Boot**: 3.4.x (与 Spring Cloud 2025.x 配套)
- **Spring Cloud**: 2025.x
- **Spring Cloud Alibaba**: 2023.x (兼容 Spring Boot 3.x)
- **Java**: 21 LTS
- **PostgreSQL**: 16
- **Redis**: 7.x
- **Maven**: 3.9+

所有选型均为 Spring Boot 3.x 生态原生支持，不存在版本冲突或兼容性补丁依赖。

---

## 参考

- [Nacos 官方文档](https://nacos.io/docs/latest/)
- [Sentinel 官方文档](https://sentinelguard.io/zh-cn/)
- [Spring Cloud Alibaba 参考手册](https://sca.aliyun.com/)
- [MyBatis-Plus 多租户文档](https://baomidou.com/plugins/tenant/)
