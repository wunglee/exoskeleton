# 01. 外骨骼系统架构总览

> NSCA 外骨骼系统基于 **yudao-cloud**（芋道云后台）二次开发，通过扩展 yudao 各业务模块实现认证、多租户、计费、支付、会员、社区、管理后台等非业务关注点。外骨骼与核心仿真引擎完全解耦，通过网关 Header 协议实现唯一集成。

## 1.1 yudao-cloud 基座

yudao-cloud 是基于 Spring Cloud Alibaba 的微服务快速开发平台，提供以下开箱即用的能力：

| yudao 模块 | 提供的基础能力 | NSCA 扩展方向 |
|-----------|-------------|-------------|
| `yudao-module-system` | 用户/角色/菜单/部门/租户/字典/通知/社交登录/OAuth2 | 扩展为 NSCA 认证 + 权限体系 |
| `yudao-module-infra` | 文件存储/代码生成/定时任务/API 日志/配置中心 | 直接复用 |
| `yudao-module-member` | 会员用户/等级/积分/经验/签到/标签/分组 | **核心扩展** → 订阅计划 + RP 积分 |
| `yudao-module-pay` | 支付应用/渠道/订单/退款/回调通知 | 扩展 Stripe 渠道 + 订阅支付 |
| `yudao-gateway` | Spring Cloud Gateway + 安全过滤器 + 限流 | 扩展 NSCA 过滤器链 |
| `yudao-framework` | MyBatis-Plus 多租户/数据权限/敏感数据/操作日志/OSS | 直接复用 |
| `yudao-server` | 单体启动模块（Admin + App 合并部署） | 用 NSCA 服务替代 |

### yudao 模块与 NSCA 外骨骼的对应关系

```
yudao-cloud (基座)                        NSCA 外骨骼 (扩展层)
─────────────────                        ──────────────────
yudao-module-system/
  ├── 用户管理 ──────────扩展──────────→ 认证服务 (JWT RS256, API Key, TOTP)
  ├── 角色管理 ──────────复用──────────→ RBAC 权限
  ├── 菜单管理 ──────────复用──────────→ 管理后台菜单
  ├── 租户管理 ──────────复用──────────→ 多租户隔离
  ├── 社交登录 ──────────扩展──────────→ Logto OIDC + GitHub/Google OAuth2
  └── OAuth2 ────────────扩展──────────→ JWT + Refresh Token 轮换

yudao-module-member/
  ├── 会员等级 ──────────扩展──────────→ 订阅计划 (Free/Pro/Team/Enterprise)
  ├── 积分系统 ──────────扩展──────────→ RP 积分体系 (rp_account + rp_lot)
  ├── 经验系统 ──────────复用──────────→ 荣誉级别 (探索者→首席科学家)
  ├── 标签系统 ──────────扩展──────────→ 专家认证徽章
  ├── 分组系统 ──────────复用──────────→ 团队协作分组
  └── 签到系统 ──────────扩展──────────→ RP 签到奖励

yudao-module-pay/
  ├── 支付订单 ──────────复用──────────→ 统一支付订单
  ├── 支付渠道 ──────────扩展──────────→ + Stripe 国际支付
  ├── 退款管理 ──────────扩展──────────→ 多渠道统一退款
  └── 回调通知 ──────────扩展──────────→ Stripe Webhook + 对账

yudao-gateway/
  └── Gateway 基础 ──────扩展──────────→ NSCA 过滤器链 + 核心透传路由

yudao-module-infra/
  └── 全部 ────────────直接复用────────→ 文件/代码生成/定时任务/日志
```

## 1.2 外骨骼模式

```
                             ┌──────────────────────────────┐
                             │       终端用户 / API 客户端      │
                             └──────────────┬───────────────┘
                                            │
                             ┌──────────────┴───────────────┐
                             │     yudao-gateway (扩展后)     │  ← 唯一入口
                             │  JWT校验 / API Key / 限流     │
                             │  租户注入 / 功能门控 / RP扣除  │
                             └──────┬───────────────┬───────┘
                                    │               │
             ┌──────────────────────┘               └──────────────────────┐
             │  /api/v1/auth/**    /api/v1/billing/**                      │  /api/v1/core/**
             │  /api/v1/admin/**   /api/v1/community/**                    │  /api/v1/compute/**
             ▼                                                             ▼
┌─────────────────────────────────────────┐    ┌──────────────────────────────┐
│      外骨骼系统 (yudao 扩展模块)          │    │      核心业务系统 (不修改)       │
│                                         │    │                              │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐  │    │  ┌────────────────────────┐  │
│  │ 认证服务  │ │ 会员服务  │ │ 支付服务 │  │    │  │  NSCA 仿真引擎 (Python)  │  │
│  │ 扩展     │ │ 扩展     │ │ 扩展    │  │    │  │  FastAPI + NumPy        │  │
│  │ system   │ │ member   │ │ pay     │  │    │  └────────────────────────┘  │
│  └──────────┘ └──────────┘ └─────────┘  │    │                              │
│                                         │    │  ┌────────────────────────┐  │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐  │    │  │  认知代谢 / 记忆系统      │  │
│  │ 管理API  │ │ 社区服务  │ │ 基础设施 │  │    │  │  (独立演进，不修改)        │  │
│  │ 扩展     │ │ 新建     │ │ 直接复用 │  │    │  └────────────────────────┘  │
│  │ system   │ │ community│ │ infra   │  │    │                              │
│  └──────────┘ └──────────┘ └─────────┘  │    │                              │
│                                         │    │                              │
│  MySQL 8.0 / PostgreSQL 16 │ Redis 7    │    │  (不自行认证，不处理计费)       │
└─────────────────────────────────────────┘    └──────────────────────────────┘
```

## 1.3 核心设计原则

| 原则 | 说明 | yudao 基座体现 |
|------|------|-------------|
| **基于 yudao 扩展，不推翻重来** | 复用 yudao 的分层架构、DO/Mapper/Service/Controller 模式 | MyBatis-Plus 多租户拦截器、RBAC 权限框架 |
| **外骨骼不感知业务** | NSCA 仿真引擎细节不外泄到平台层 | yudao 通用模块不导入任何 NSCA 业务类 |
| **业务不处理企业逻辑** | 仿真引擎只信任网关注入的 Header | X-User-Id, X-Tenant-Id 由 yudao-gateway 注入 |
| **网关是唯一集成面** | 外骨骼与核心之间的所有通信通过网关 | yudao-gateway 扩展过滤器链 |
| **扩展而非修改** | 新增表/字段/Service 追加在 yudao 模块中，不改 yudao 核心逻辑 | 新增 `rp_*` 表族、新增 Stripe 支付渠道 |

## 1.4 项目结构

```
NSCA/
├── exoskeleton/                              ← 外骨骼系统（yudao-cloud 扩展版）
│   ├── pom.xml                               ← Maven 父 POM（yudao 依赖管理）
│   ├── yudao-dependencies/                   ← yudao 版本管理（直接复用）
│   ├── yudao-framework/                      ← yudao 框架层（直接复用）
│   ├── yudao-gateway/                        ← 网关模块（扩展过滤器链）
│   ├── yudao-server/                         ← 启动模块
│   ├── yudao-module-system/                  ← 系统模块（扩展认证/权限）
│   │   └── src/main/java/.../system/
│   │       ├── controller/admin/auth/        ← 扩展：认证 API
│   │       ├── service/oauth2/               ← 扩展：Logto OIDC 集成
│   │       └── dal/dataobject/               ← 复用 yudao 原有 DO
│   ├── yudao-module-member/                  ← 会员模块（核心扩展）
│   │   └── src/main/java/.../member/
│   │       ├── dal/dataobject/
│   │       │   ├── level/MemberLevelDO.java  ← 扩展：订阅计划字段
│   │       │   └── point/                     ← 新增：rp_account, rp_lot
│   │       └── service/
│   │           ├── subscription/              ← 新增：订阅管理 Service
│   │           └── rp/                        ← 新增：RP 积分 Service
│   ├── yudao-module-pay/                     ← 支付模块（扩展 Stripe）
│   │   └── src/main/java/.../pay/
│   │       ├── channel/stripe/               ← 新增：Stripe 支付渠道
│   │       └── service/subscription/          ← 新增：订阅支付 Service
│   ├── yudao-module-infra/                   ← 基础设施（直接复用）
│   ├── yudao-module-community/               ← 新增：社区模块
│   └── docker-compose.yml                    ← 基础设施部署
│
├── services/                                 ← 核心业务系统（不修改）
│   └── nsca-compute/                         ← NSCA 仿真引擎 (Python)
│
├── web/                                      ← 用户 Web 应用
├── admin/                                    ← 管理控制台
└── docs/                                     ← 文档
```

> **扩展约定**：yudao 原有代码标记 `// YUDAO: keep` 表示不修改。NSCA 扩展代码标记 `// NSCA: extend` 表示追加逻辑。新增表使用独立 migration 脚本（如 `V2__nsca_rp_account.sql`），不修改 yudao 原有 migration。

## 1.5 关键设计决策

### 决策 1：基于 yudao-cloud 二次开发，而非从零搭建

**理由**：yudao-cloud 已经提供了用户/角色/菜单/租户/支付/会员等完整的后台基础能力及其管理 UI。自建这些需要 6 个月以上，基于 yudao 扩展只需聚焦 NSCA 差异化部分（RP 积分、Stripe 支付、订阅管理、社区层）。

**边界**：yudao 原有的 CRUD 逻辑不改动，NSCA 扩展通过以下方式追加：
- 新增数据库表（`rp_*`、`subscription_*`）
- 新增 Service 类（`RpAccountService`、`SubscriptionService`）
- 扩展现有 Controller（新增 `@RestController` 方法或新建 Controller）
- 新增 Maven 模块（`yudao-module-community`）

### 决策 2：保留 yudao 分层架构，不引入新的架构范式

**理由**：yudao 的 DO→Mapper→Service→Controller→VO 分层已经在国内 Java 生态中广泛验证。NSCA 扩展遵循同一套分层规范，降低团队学习成本。

### 决策 3：网关 Header 作为与核心业务唯一集成协议

**理由**：扩展 yudao-gateway 的过滤器链，注入 X-Tenant-Id、X-User-Id、X-Features 等 Header。核心仿真引擎只信任这些 Header，不导入任何 yudao 代码。这确保核心业务可以独立演进。

### 决策 4：yudao 原表扩展字段，而非新建替代表

**理由**：`member_level` 表加 `price_monthly`、`price_yearly`、`currency`、`features` 字段即可承载订阅计划，不需要新建 `subscription_plan` 表替代它。这保留了 yudao 管理后台对等级配置的现有 UI，只需加几个表单字段。

**例外**：RP 积分因 FIFO 批次追踪需求与 yudao `member_point_record` 的单余额模型根本不同，必须新建 `rp_account` + `rp_lot` 表族。

---

## 与需求文档的映射

| 架构文档 | 对应需求文档 | yudao 基础 |
|---------|------------|----------|
| [03-auth.md](03-auth.md) | [../requirements/01-users-auth.md](../requirements/01-users-auth.md) | yudao-module-system (用户/社交登录/OAuth2) |
| [04-permissions.md](04-permissions.md) | [../requirements/01-users-auth.md](../requirements/01-users-auth.md)（权限部分） | yudao-module-system (角色/菜单) |
| [06-billing.md](06-billing.md) | [../requirements/02-subscription-plans.md](../requirements/02-subscription-plans.md) | yudao-module-member (等级/积分/经验) |
| [07-payment.md](07-payment.md) | [../requirements/02-subscription-plans.md](../requirements/02-subscription-plans.md)（支付部分） | yudao-module-pay (渠道/订单/退款) |
| [08-membership.md](08-membership.md) | [../requirements/02-subscription-plans.md](../requirements/02-subscription-plans.md)（会员部分） | yudao-module-member (标签/分组/配置) |
| [11-community.md](11-community.md) | [../requirements/03-community.md](../requirements/03-community.md) | 新建 yudao-module-community |
| [05-gateway-integration.md](05-gateway-integration.md) §5.7 | [../requirements/03-community.md](../requirements/03-community.md)（核心透传） | yudao-gateway (路由扩展) |
| [09-admin.md](09-admin.md) | [../requirements/04-admin-console.md](../requirements/04-admin-console.md) | yudao-module-system (管理后台框架) |
| [10-deployment.md](10-deployment.md) | — | yudao Docker Compose 基础 |

---

## 与核心系统的边界

外骨骼**不处理**以下关注点，这些由 `services/` 独立负责：

- 仿真引擎（节点/容器/层/Tick）
- 认知代谢系统
- 验证与监控
- 记忆系统
- 前端 SDK

核心引擎通过 yudao-gateway 注入的 HTTP Header（X-Tenant-Id, X-User-Id）接收已验证的上下文，不自行处理认证或计费。
