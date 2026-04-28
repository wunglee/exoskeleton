# NSCA 外骨骼系统产品需求规约（PRD）

> 平台基础服务需求文档集。涵盖用户认证、订阅计费、社区层、管理后台等外骨骼系统的产品需求。**不含核心研究智能体需求**（仿真工作台、认知代谢、科研智能体等），这些内容归属核心系统。

## 文档索引

| 分册 | 内容 | 对应架构 | 优先级 |
|------|------|---------|--------|
| [01-users-auth.md](01-users-auth.md) | 用户注册/登录/认证流程、API Key 管理 | [../architecture/exoskeleton/03-auth.md](../architecture/exoskeleton/03-auth.md) | P0 |
| [02-subscription-plans.md](02-subscription-plans.md) | 订阅计划、功能配额、RP 积分体系 | [../architecture/exoskeleton/06-billing.md](../architecture/exoskeleton/06-billing.md), [07-payment.md](../architecture/exoskeleton/07-payment.md), [08-membership.md](../architecture/exoskeleton/08-membership.md) | P0 |
| [03-community.md](03-community.md) | 社区层：首页门户、领域广场、项目公共页、个人空间、Fork/合并请求 | [../architecture/exoskeleton/09-admin.md](../architecture/exoskeleton/09-admin.md) | P1 |
| [04-admin-console.md](04-admin-console.md) | 管理控制台：用户管理、租户管理、计费管理、系统配置 | [../architecture/exoskeleton/09-admin.md](../architecture/exoskeleton/09-admin.md) | P1 |

---

## 与外骨骼架构文档的完整映射

```
requirements/exoskeleton/              architecture/exoskeleton/
├── 01-users-auth.md        ──→   ├── 03-auth.md
├── 02-subscription-plans.md ──→   ├── 06-billing.md
│                                  ├── 07-payment.md
│                                  └── 08-membership.md
├── 03-community.md         ──→   ├── 09-admin.md
└── 04-admin-console.md     ──→   ├── 09-admin.md
```

---

## 与核心系统的边界

核心产品需求**不包含**以下内容，这些由外骨骼系统独立负责：

- 用户注册/登录/认证流程 → [01-users-auth.md](01-users-auth.md)
- 订阅计划与功能配额 → [02-subscription-plans.md](02-subscription-plans.md)
- 社区层（首页门户/领域广场/个人空间）→ [03-community.md](03-community.md)
- 管理控制台 → [04-admin-console.md](04-admin-console.md)

核心产品专注研究智能体的交互体验，平台能力由外骨骼通过 API 提供。

---

## 阅读顺序

**首次阅读建议**：
1. [01-users-auth.md](01-users-auth.md) — 理解用户认证体系
2. [02-subscription-plans.md](02-subscription-plans.md) — 理解订阅与计费模式
3. [03-community.md](03-community.md) — 理解社区层设计
4. [04-admin-console.md](04-admin-console.md) — 理解管理控制台

**按角色阅读**：
- **产品经理**：01 → 02 → 03
- **UX 设计师**：01 → 03
- **平台工程师**：01 → 02 → 04
