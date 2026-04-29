# NSCA 外骨骼系统架构

> Spring Cloud Alibaba 微服务套件作为企业级平台外壳，提供认证、多租户、计费、支付、网关、管理后台等非业务关注点。外骨骼是独立 Maven 多模块项目，与核心业务系统通过网关 Header 协议集成，零代码耦合。

## 文档索引

### 系统定位与总览

| 文档 | 内容 |
|------|------|
| [01-overview.md](01-overview.md) | 外骨骼模式、架构全景、核心设计原则、项目边界、关键决策 |
| [02-tech-stack.md](02-tech-stack.md) | Spring Cloud Alibaba 技术栈能力匹配、选型论证、版本兼容性 |

### 认证与权限

| 文档 | 内容 |
|------|------|
| [03-auth.md](03-auth.md) | 注册/登陆/认证：JWT + OAuth2 (GitHub/Google)、Logto OIDC、API Key |
| [04-permissions.md](04-permissions.md) | 权限系统：ABAC 属性基访问控制 + RBAC 角色快捷方式、动态策略引擎 |

### 网关与集成

| 文档 | 内容 |
|------|------|
| [05-gateway-integration.md](05-gateway-integration.md) | API 网关 (Spring Cloud Gateway + Sentinel)、全局过滤器链、**网关集成协议**（外骨骼 → 业务服务 Header 约定） |

### 计费与支付

| 文档 | 内容 |
|------|------|
| [06-billing.md](06-billing.md) | 计费系统：混合模式（基础订阅 + 超额 tick 按量计费）、RP 积分系统 |
| [07-payment.md](07-payment.md) | 支付集成：Stripe (国际信用卡) + Jeepay (支付宝/微信支付)、统一支付路由 |
| [08-membership.md](08-membership.md) | 会员等级：多级订阅、功能门控、配额管理 |

### 社区层

| 文档 | 内容 |
|------|------|
| [11-community.md](11-community.md) | 社区层架构：论坛讨论、评论、关注、动态流、点赞；核心透传集成模式 |

### 管理与运维

| 文档 | 内容 |
|------|------|
| [09-admin.md](09-admin.md) | 管理控制台：用户/项目/系统/计费管理、Spring Boot Admin REST API |
| [10-deployment.md](10-deployment.md) | 部署架构：Docker Compose、端口规划、网络隔离、生产部署要点 |

---

## 架构总览图

```
┌─────────────────────────────────────────────────────────────────────┐
│                        NSCA v1.0 架构全景                            │
├─────────────────────────────────────────────────────────────────────┤
│  外骨骼平台层 (exoskeleton/)                                         │
│  ┌─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┐    │
│  │  认证    │  权限    │  计费    │  支付    │  会员    │  社区    │  管理    │    │
│  │  JWT+   │  ABAC   │  混合    │  多渠道  │  等级    │  论坛+   │  后台    │    │
│  │  OIDC   │  +RBAC  │  模式    │  路由    │  门控    │  透传    │  API    │    │
│  └────┬────┴────┬────┴────┬────┴────┬────┴────┬────┴────┬────┴────┬────┘    │
│       └─────────┴─────────┴─────────┴────┬────┴─────────┴─────────┘          │
│                                │                                     │
│                    Spring Cloud Gateway                              │
│                 (JWT校验 / 限流 / 路由 / 熔断)                        │
│                                │                                     │
│              ┌─────────────────┴─────────────────┐                  │
│              │  X-Tenant-Id, X-User-Id, X-Job-Id  │                  │
│              │  X-Features, X-Auth-Method          │                  │
│              └─────────────────┬─────────────────┘                  │
│                                │                                     │
│  核心业务层 (services/) — 任意语言/框架                              │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  核心仿真引擎 │ 认知代谢系统 │ 验证体 │ 记忆系统 │ 运行时     │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 与核心系统的边界

外骨骼**不处理**以下关注点，这些由 `../core/` 独立负责：

- 仿真引擎（节点/容器/层/Tick）→ [../core/02-core-engine.md](../core/02-core-engine.md)
- 认知代谢系统 → [../core/03b-world-sense.md](../core/03b-world-sense.md)
- 验证与监控 (Body I/II/III) → [../core/05-body-i.md](../core/05-body-i.md)
- 记忆系统 (L1/L3/L4) → [../core/08-memory-loop.md](../core/08-memory-loop.md)
- 前端 SDK → [../core/12-sdk-frontend.md](../core/12-sdk-frontend.md)

核心引擎通过网关注入的 HTTP Header（X-Tenant-Id, X-User-Id）接收已验证的上下文，不自行处理认证或计费。

---

## 与外骨骼需求文档的映射

| 架构文档 | 需求文档 |
|---------|---------|
| [03-auth.md](03-auth.md) | [../requirements/01-users-auth.md](../requirements/01-users-auth.md) |
| [04-permissions.md](04-permissions.md) | [../requirements/01-users-auth.md](../requirements/01-users-auth.md)（权限部分） |
| [06-billing.md](06-billing.md) + [07-payment.md](07-payment.md) | [../requirements/02-subscription-plans.md](../requirements/02-subscription-plans.md) |
| [08-membership.md](08-membership.md) | [../requirements/02-subscription-plans.md](../requirements/02-subscription-plans.md)（会员等级部分） |
| [11-community.md](11-community.md) | [../requirements/03-community.md](../requirements/03-community.md)（通用社区框架部分） |
| [05-gateway-integration.md](05-gateway-integration.md) §5.7 | [../requirements/03-community.md](../requirements/03-community.md)（核心透传部分） |
| [09-admin.md](09-admin.md) | [../requirements/04-admin-console.md](../requirements/04-admin-console.md) |

---

## 阅读顺序

**首次阅读建议**：
1. [01-overview.md](01-overview.md) — 理解外骨骼模式与核心设计原则
2. [02-tech-stack.md](02-tech-stack.md) — 理解技术选型与能力匹配
3. [05-gateway-integration.md](05-gateway-integration.md) — 理解网关集成协议（最核心的集成约定）
4. [03-auth.md](03-auth.md) — 理解认证架构
5. [11-community.md](11-community.md) — 理解社区层与核心透传的边界

**按角色阅读**：
- **平台工程师**：03-auth → 04-permissions → 06-billing → 07-payment → 11-community → 09-admin → 10-deployment
- **后端开发者**：01-overview → 02-tech-stack → 05-gateway-integration → 11-community
- **架构师**：01-overview → 02-tech-stack → 05-gateway-integration → 11-community → 10-deployment
