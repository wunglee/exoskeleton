# NSCA 外骨骼系统差距分析报告

> 综合 `docs/architecture/`、`docs/requirements/`、`docs/exoskeleton-improvement-from-core-audit.md` 与当前代码基线的全面对比
> 版本：v1.0 | 日期：2026-04-29 | 状态：待评审

---

## 执行摘要

当前代码基线（`yudao-cloud` 精简版 + `pay`/`member` 模块集成）**仅完成了外骨骼系统的 5%～10%**。已具备的能力集中在 yudao 原生框架提供的基础功能（用户认证、多租户、代码生成、文件存储、定时任务、管理后台），而 NSCA 外骨骼系统的核心差异化能力——RP 积分体系、订阅计划与功能配额、网关 Header 协议、Stripe 国际支付、API Key 管理、社区层——均未实现。

| 维度 | 满足度 | 说明 |
|------|--------|------|
| 基础平台框架 | ~60% | yudao 提供用户/角色/菜单/部门/租户/SSO/文件存储等 |
| 认证体系 | ~30% | 邮箱+OAuth 有基础，但缺少 API Key、TOTP、RS256、会话审计 |
| 计费与订阅 | ~5% | 支付模块有框架，但无订阅计划、无 RP、无配额 |
| 支付集成 | ~25% | 国内支付宝/微信可用，缺少 Stripe、订阅生命周期、对账 |
| 网关与集成 | ~0% | 无 Gateway 模块、无 Header 注入协议 |
| 会员与社区 | ~10% | member 等级/签到/积分存在，但非 RP 体系、无社区功能 |
| 管理控制台 | ~20% | yudao Admin 有基础 CRUD，缺少计费/RP/配额管理 |
| 技术栈合规 | ~15% | JDK 8 + Boot 2.7 + MySQL，与文档要求（JDK 21 + Boot 3.x + PG）差距大 |

---

## 1. 文档体系总览

### 1.1 需求文档 (requirements/)

| 文档 | 内容 | 优先级 | 当前覆盖 |
|------|------|--------|---------|
| `01-users-auth.md` | 注册/登录/认证、API Key、TOTP、会话管理 | P0 | ⚠️ 部分 |
| `02-subscription-plans.md` | 订阅计划、功能配额、RP 积分、支付方式、退款 | P0 | ❌ 无 |
| `03-community.md` | 首页门户、领域广场、项目页、个人空间、论坛 | P1 | ❌ 无 |
| `04-admin-console.md` | 租户/用户/订阅/计费/RPAudit 管理后台 | P1 | ⚠️ 部分 |

### 1.2 架构文档 (architecture/)

| 文档 | 内容 | 当前覆盖 |
|------|------|---------|
| `01-overview.md` | 外骨骼模式、模块边界、网关 Header 协议 | ❌ 无 |
| `02-tech-stack.md` | Spring Boot 3.x + JDK 21 + PG + Nacos + Gateway + Sentinel + Logto | ❌ 无 |
| `03-auth.md` | JWT RS256、Token 轮换、家族检测、API Key HMAC、会话审计 | ❌ 无 |
| `04-permissions.md` | ABAC + RBAC 动态策略引擎 | ⚠️ yudao 有 RBAC，无 ABAC |
| `05-gateway-integration.md` | Spring Cloud Gateway、Sentinel 限流、RP 消费过滤器、Header 注入 | ❌ 无 |
| `06-billing.md` | 订阅管理、Tick 计量、配额守护、RP 账户、发票 | ❌ 无 |
| `07-payment.md` | Stripe + Jeepay 多渠道路由、Webhook、对账 | ⚠️ 部分（仅 Jeepay 框架） |
| `08-membership.md` | 功能门控、升级/降级、排行榜、徽章 | ❌ 无 |
| `09-admin.md` | 管理后台 REST API | ⚠️ yudao Admin 有基础 |
| `10-deployment.md` | Docker Compose、K8s、端口规划、网络隔离 | ⚠️ 部分 |
| `11-community.md` | 社区层架构：论坛讨论、评论、关注、动态流、核心透传集成 | ✅ 已创建（2026-04-29） |

### 1.3 改进建议 (exoskeleton-improvement-from-core-audit.md)

| 建议 | 状态 | 优先级 |
|------|------|--------|
| RP 积分完整定义（来源/消耗/衰减/兑换） | 未实现 | P0 |
| 订阅计划价格表与功能配额矩阵 | 未实现 | P0 |
| 专家认证体系（领域贡献者/认证专家/首席科学家） | 未实现 | P1 |
| 退款政策（7 天全额/按比例/争议） | 未实现 | P0 |
| 手机号注册流程（中国区） | 未实现 | P1 |
| 社区框架重构（通用论坛 vs 核心透传 Fork/MR） | 未实现 | P1 |
| 核心配置接口 (`GET /api/v1/core/page-config`) | 未实现 | P1 |

---

## 2. 逐项差距分析

### 2.1 认证体系 (03-auth.md / 01-users-auth.md)

| 要求项 | 文档规格 | 当前实现 | 差距 |
|--------|---------|---------|------|
| 密码哈希 | bcrypt, cost ≥ 12 | yudao 使用 bcrypt（未验证 cost） | ⚠️ 需验证 cost 值 |
| JWT 签名 | RS256 非对称算法 | yudao 使用对称签名（`spring.security.token.secret-key`） | ❌ 需升级为 RSA 密钥对 |
| Access Token 有效期 | 15 分钟 | yudao 默认 30 分钟 | ⚠️ 需调整 |
| Refresh Token | httpOnly Cookie + 轮换 + 家族检测 | yudao 使用 Redis 存储 Token，无家族检测 | ❌ 需重写 |
| TOTP 多因素认证 | 可选/管理员强制 | 无 | ❌ 需新增 |
| API Key 管理 | HMAC-SHA256 签名、权限范围、速率限制 | 无 | ❌ 需新增完整模块 |
| PAT (个人访问令牌) | 短令牌、细粒度权限、可撤销 | 无 | ❌ 需新增 |
| 会话审计 | 设备指纹、IP、地理位置、活跃会话列表 | 无 | ❌ 需新增 |
| 安全告警 | 异地登录、Token 复用、泄露密码检测 | 无 | ❌ 需新增 |
| OAuth2 + PKCE | GitHub/Google 标准 PKCE 流程 | yudao 使用 JustAuth（简化 OAuth） | ⚠️ 需验证 PKCE 支持 |
| 注册来源追踪 | IP、User-Agent、审计日志 | 部分（登录日志有 IP） | ⚠️ 需补充 |
| 密码找回 | 30 分钟限时 JWT 重置链接 | yudao 有基础重置功能 | ✅ 基本覆盖 |

**关键缺口**：API Key / PAT 体系是当前认证层面最大空白。NSCA 的 CLI/SDK 访问完全依赖此能力。

---

### 2.2 网关与集成协议 (05-gateway-integration.md)

| 要求项 | 文档规格 | 当前实现 | 差距 |
|--------|---------|---------|------|
| Spring Cloud Gateway 模块 | `exoskeleton-gateway/` | 无 | ❌ 核心缺失 |
| JWT 认证过滤器 | 校验签名/过期/issuer，提取上下文 | 无（yudao 使用 Spring Security 拦截器） | ❌ 需迁移到网关层 |
| API Key 认证过滤器 | `X-API-Key` Header，bcrypt 比对 | 无 | ❌ 需新增 |
| 租户 Header 注入 | `X-Tenant-Id`、`X-User-Id` 向下游注入 | 无 | ❌ 核心缺失 |
| 功能门控过滤器 | 检查订阅层级是否允许端点 | 无 | ❌ 需新增 |
| RP 消费过滤器 | 端点级 RP 扣除（如因果发现 10 RP） | 无 | ❌ 需新增 |
| Sentinel 限流 | 租户级滑动窗口、每用户/min 限流 | yudao 有 Sentinel 依赖但未启用 | ⚠️ 需配置 |
| Resilience4j 断路器 | 业务服务保护（如 computeBreaker） | 无 | ❌ 需新增 |
| 审计日志过滤器 | 异步记录所有请求审计日志 | yudao 有操作日志，非网关级 | ⚠️ 需扩展 |
| 路由配置 | `/api/v1/auth/**` → auth-service, `/api/v1/compute/**` → nsca-compute | 无 | ❌ 需新增 |

**关键缺口**：网关层是整个外骨骼与核心业务解耦的唯一集成面。当前没有 Gateway 模块，意味着所有 Header 协议、限流、RP 消费、功能门控都无法落地。

---

### 2.3 计费系统 (06-billing.md / 02-subscription-plans.md)

| 要求项 | 文档规格 | 当前实现 | 差距 |
|--------|---------|---------|------|
| 订阅计划数据模型 | `free`/`pro`/`team`/`enterprise`，月付/年付 | 无 | ❌ 最大缺口 |
| 功能配额矩阵 | Tick/存储/API/并发/LLM Token/分支等 | 无 | ❌ 需新增 |
| 订阅状态机 | `active`/`cancelled`/`paused`/`past_due` | 无 | ❌ 需新增 |
| 升级/降级策略 | 立即生效补差价 / 周期结束后降级 | 无 | ❌ 需新增 |
| Tick 计量采集 | Kafka 事件流 → TimescaleDB 聚合 | 无 | ❌ 需新增 |
| 配额实时守护 | 仿真启动前预扣配额、超时释放 | 无 | ❌ 需新增 |
| 超额计费 | 阶梯单价、自动扣款、欠费保护 | 无 | ❌ 需新增 |
| 增量包 (Top-up) | Tick 包/存储包/API 包 | 无 | ❌ 需新增 |
| 发票系统 | 订阅/增量/超额发票，Stripe Tax | 无 | ❌ 需新增 |
| **RP 积分账户** | `ResearchPointsAccount` 余额/累计/流水 | 无（member 模块有普通积分，非 RP） | ❌ 需新增 |
| **RP 获取方式** | 星标/Fork/评论/MR/浏览等社区行为 | 无 | ❌ 需新增 |
| **RP 消耗方式** | 仿真/分析/抵扣会员费/兑换资源 | 无 | ❌ 需新增 |
| RP 防刷机制 | IP 去重、频率限制、NLP 质量评分 | 无 | ❌ 需新增 |
| RP 有效期 | 12 个月 FIFO 过期 | 无 | ❌ 需新增 |
| 退款政策 | 7 天全额/按比例/争议处理 | 无 | ❌ 需新增 |
| 专家认证体系 | 领域贡献者/认证专家/首席科学家 | 无 | ❌ 需新增 |
| 荣誉级别 | 探索者→学徒→研究者→学者→首席科学家 | 无 | ❌ 需新增 |

**关键缺口**：订阅计划 + RP 积分是整个外骨骼的商业核心。当前代码完全没有这些概念，需要从零设计和实现数据模型、业务逻辑、API 接口。

---

### 2.4 支付集成 (07-payment.md)

| 要求项 | 文档规格 | 当前实现 | 差距 |
|--------|---------|---------|------|
| Stripe 国际支付 | Visa/MC/AmEx + Subscription + Tax | 无 | ❌ 需新增完整 Stripe 模块 |
| Stripe Webhook | `invoice.paid`/`subscription.updated` 等 | 无 | ❌ 需新增 |
| Stripe Customer Portal | 用户自助管理订阅 | 无 | ❌ 需新增 |
| 支付宝/微信 (Jeepay) | PC/手机/扫码/JSAPI | yudao `pay` 模块有基础框架 | ⚠️ 可用，但缺少订阅周期扣款 |
| 支付路由 | 根据用户地区自动选择渠道 | 无 | ❌ 需新增 |
| 支付失败回退 | 指数退避重试、备用渠道切换 | 无 | ❌ 需新增 |
| 对账机制 | 日对账、差异报告、异常告警 | 无 | ❌ 需新增 |
| 退款状态机 | `pending → succeeded/failed` | yudao `pay_refund` 表有基础 | ⚠️ 需扩展为多渠道统一退款 |
| 争议处理 | Stripe Dispute/支付渠道争议 | 无 | ❌ 需新增 |

**关键缺口**：Stripe 国际支付和订阅生命周期管理是当前支付层最大缺口。yudao 的 pay 模块只支持国内一次性支付，没有订阅制。

---

### 2.5 会员等级 (08-membership.md)

| 要求项 | 文档规格 | 当前实现 | 差距 |
|--------|---------|---------|------|
| 四级订阅体系 | Free/Pro/Team/Enterprise | 无 | ❌ 需新增 |
| 功能门控 (前端) | `<FeatureGate>` 组件 + 升级提示 | 无 | ❌ 需前端实现 |
| 功能门控 (后端) | `@require_feature` + `@require_quota` | 无 | ❌ 需新增 |
| 升级/降级事件流 | `membership.tier.changed` | 无 | ❌ 需新增 |
| 排行榜 | 按领域/周期/分类的排行榜 | 无 | ❌ 需新增 |
| 徽章系统 | 专家认证徽章、贡献徽章 | 无 | ❌ 需新增 |
| 团队扩展 | 个人版→团队版数据迁移 | 无 | ❌ 需新增 |

---

### 2.6 社区层 (03-community.md / 11-community.md)

> **更新 (2026-04-29)**：`docs/architecture/11-community.md` 已创建，覆盖外骨骼通用社区框架（论坛/评论/关注/动态流/点赞）的数据模型、API 契约、核心透传集成模式。`docs/architecture/05-gateway-integration.md` §5.7 新增核心透传配置接口规格。

| 要求项 | 文档规格 | 架构覆盖 | 当前实现 | 差距 |
|--------|---------|---------|---------|------|
| 首页门户 (Landing) | Hero/数据栏/专家列席/领域入口/热门项目 | 11-community.md §11.5 | 无 | ❌ 需前端实现 |
| 论坛讨论系统 | 发帖/回复/点赞/@用户/Markdown | 11-community.md §11.3.1 + §11.4.1 | 无 | ❌ 需新增 |
| 用户关注/粉丝 | 关注/取消/粉丝列表 | 11-community.md §11.3.4 + §11.4.3 | 无 | ❌ 需新增 |
| 动态流 | 用户活动时间线 | 11-community.md §11.3.5 + §11.4.4 | 无 | ❌ 需新增 |
| 评论系统 | Markdown 编辑/嵌套回复 | 11-community.md §11.3.3 + §11.4.2 | 无 | ❌ 需新增 |
| 核心透传功能 | Fork 按钮/MR 按钮/仿真预览/排行榜 | 05-gateway-integration.md §5.7 | 无（核心配置接口已规格化） | ❌ 需核心配合 |

> 改进建议文档强调：社区框架应拆分为**外骨骼通用社区**（论坛/评论/关注）和**核心透传功能**（Fork/MR/仿真预览由核心通过配置接口驱动）。架构文档现已完整覆盖此边界。

---

### 2.7 管理控制台 (04-admin-console.md / 09-admin.md)

| 要求项 | 文档规格 | 当前实现 | 差距 |
|--------|---------|---------|------|
| 运营仪表板 | DAU/MAU/订阅分布/收入/RPAudit | yudao 有基础统计 | ⚠️ 需扩展 |
| 租户管理 | 创建/配置/暂停/删除/软删除 | yudao 有租户管理 | ⚠️ 基本覆盖，需扩展 |
| 用户 RP 管理 | 手动发放/扣除 RP、填写原因 | 无 | ❌ 需新增 |
| 订阅查询与操作 | 升级/降级/取消/退款 | 无 | ❌ 需新增 |
| 支付记录对账 | Stripe + Jeepay 统一流水 | 无 | ❌ 需新增 |
| Webhook 事件重试 | 查看/重试失败 Webhook | 无 | ❌ 需新增 |
| 套餐管理 | 创建/编辑/下线套餐计划 | 无 | ❌ 需新增 |
| Sentinel 面板 | 实时限流/熔断状态调整 | 无 | ❌ 需新增 |
| RP 汇率配置 | CNY/USD ↔ RP 汇率调整 | 无 | ❌ 需新增 |
| 功能开关 | 灰度/上线/回滚 | 无 | ❌ 需新增 |
| 审计日志保留 | 7 年 | yudao 有操作日志 | ⚠️ 需确认保留策略 |

---

### 2.8 技术栈合规 (02-tech-stack.md)

| 要求项 | 文档规格 | 当前实现 | 差距 |
|--------|---------|---------|------|
| Java 版本 | JDK 21 LTS | JDK 8 | ❌ 大版本差距 |
| Spring Boot | 3.4.x | 2.7.18 | ❌ 大版本差距 |
| Spring Cloud | 2025.x | 2021.0.4.0 | ❌ 大版本差距 |
| Spring Cloud Alibaba | 2023.x (兼容 Boot 3.x) | 2021.0.4.0 | ❌ 大版本差距 |
| 数据库 | PostgreSQL 16 | MySQL 8.0 | ❌ 数据库迁移 |
| Redis | 7.x | 未确认版本 | ⚠️ 需确认 |
| Nacos | 2.4.x 注册+配置中心 | 未启用 | ❌ 需部署 |
| Gateway | Spring Cloud Gateway 2025.x | 无 | ❌ 需新增 |
| Sentinel | 1.8.x | 有依赖但未启用 | ⚠️ 需配置 |
| Logto OIDC | 外部认证提供方 | 本地 Spring Security | ❌ 需部署 Logto |
| Flyway | 数据库迁移 | 手动 SQL 脚本 | ❌ 需引入 |
| XXL-JOB | 2.4.x | 2.3.1 (配置中 enabled=false) | ⚠️ 需升级并启用 |
| SkyWalking | 10.x | 8.12.0 | ⚠️ 需升级 |
| Resilience4j | 2.x | 无 | ❌ 需引入 |

**关键缺口**：JDK 8 → 21 + Boot 2.7 → 3.x 是一次大规模技术栈升级。如果当前目标是快速验证外骨骼概念，可以在旧版本上先实现功能，再择机升级；如果目标是生产就绪，升级应在功能开发之前完成。

---

## 3. 差距热力图

```
                    已实现    部分实现    未实现
                    ████      ██░░      ░░░░
基础平台框架        ████████░░
用户认证            ███░░░░░░░
网关与集成          ░░░░░░░░░░
计费与订阅          ░░░░░░░░░░
RP 积分体系         ░░░░░░░░░░
支付集成 (国内)     ██████░░░░
支付集成 (国际)     ░░░░░░░░░░
会员等级            ░░░░░░░░░░
功能门控            ░░░░░░░░░░
社区层              ░░░░░░░░░░
管理控制台          ███░░░░░░░
技术栈合规          ██░░░░░░░░
```

---

## 4. 风险识别

| 风险 | 等级 | 影响 | 缓解措施 |
|------|------|------|---------|
| 技术栈版本差距过大 | 🔴 高 | Boot 2.7→3.x 不兼容改动多，升级成本高 | 评估是否先功能后升级，或逐步迁移 |
| 网关层缺失导致业务耦合 | 🔴 高 | 无法通过 Header 协议与核心业务解耦 | 优先搭建 Gateway 模块 |
| RP 积分体系设计复杂 | 🟡 中 | 防刷/衰减/有效期/FIFO 消费逻辑复杂 | 先做 MVP（简单积分+兑换），再迭代 |
| Stripe 订阅集成复杂度 | 🟡 中 | Subscription/Invoice/Tax/Portal 链路过长 | 分阶段：先 Payment Intent，再 Subscription |
| 数据库从 MySQL 迁移到 PostgreSQL | 🟡 中 | SQL 方言差异、JSON 操作、分区表 | 使用 JPA/MP 抽象，减少原生 SQL |
| yudao 代码与 NSCA 需求耦合 | 🟡 中 | yudao 是通用后台，很多字段/逻辑不匹配 | 明确改造边界，不追求完全复用 |

---

## 5. 建议执行顺序

### Phase 1：基础设施（1～2 周）
1. 搭建 `exoskeleton-gateway` 模块（基础路由 + JWT 过滤器）
2. 实现网关 Header 注入协议（`X-Tenant-Id`、`X-User-Id`）
3. 引入 Nacos（注册中心 + 配置中心）
4. 评估技术栈升级可行性（Boot 2.7→3.x）

### Phase 2：核心数据模型（2～3 周）
5. 设计并实现订阅计划数据模型（`subscription_plan`、`user_subscription`）
6. 设计并实现 RP 积分账户体系（`rp_account`、`rp_transaction`）
7. 设计并实现功能配额矩阵（`quota_definition`、`user_quota`）
8. 实现订阅状态机（升级/降级/取消/过期）

### Phase 3：支付与计费（2～3 周）
9. 集成 Stripe（Payment Intent → Subscription → Webhook）
10. 改造 Jeepay 模块支持订阅周期扣款
11. 实现 RP 兑换/抵扣现金支付（混合支付）
12. 实现对账机制（日对账 + 差异报告）

### Phase 4：网关高级能力（1～2 周）
13. 实现 API Key 认证过滤器
14. 实现功能门控过滤器
15. 实现 RP 消费过滤器
16. 配置 Sentinel 限流规则

### Phase 5：会员与社区（2～3 周）
17. 实现功能门控后端注解（`@require_feature`、`@require_quota`）
18. 实现专家认证体系
19. 实现荣誉级别体系
20. 实现通用社区框架（论坛/评论/关注/动态流）

### Phase 6：管理后台（1～2 周）
21. 扩展 Admin 控制台（订阅/RPAudit/配额/对账）
22. 实现运营仪表板

### Phase 7：技术栈升级（视评估结果）
23. JDK 8 → 21
24. Boot 2.7 → 3.x
25. MySQL → PostgreSQL

---

## 6. 与 yudao 原生能力的映射建议

| yudao 已有 | NSCA 需求 | 建议处理方式 |
|-----------|----------|------------|
| `system_user` 表 | User 模型（需扩展 `membership_tier`） | 扩展字段，不替换 |
| `system_tenant` 表 | Tenant 模型 | ✅ 基本可用 |
| `system_role` + `system_menu` | RBAC 权限 | ✅ 保留，新增 ABAC 层 |
| `pay_app`/`pay_channel`/`pay_order` | 支付订单 | ⚠️ 保留框架，新增 Stripe 渠道和订阅订单 |
| `member_user` 表 | 会员用户 | ⚠️ 保留基础，新增 RP 账户关联 |
| `member_level` 表 | 会员等级 | ⚠️ 需改造为订阅计划（Free/Pro/Team/Enterprise） |
| `member_point` 表 | 积分 | ❌ 普通积分 ≠ RP，需新建 `rp_account` |
| `infra_file` | 文件存储 | ✅ 基本可用 |
| `infra_codegen` | 代码生成 | ✅ 保留 |
| `infra_job` | 定时任务 | ✅ 保留，启用 XXL-JOB |

---

## 7. 结论

当前代码基线是一个**可编译运行的 Java 后台**，提供了基础的用户认证、多租户、国内支付和管理后台能力，但距离 NSCA 外骨骼系统的完整定义**差距显著**。核心缺口按影响排序：

1. **网关层缺失** — 无法与核心业务解耦， Header 协议无法落地
2. **订阅计划缺失** — 无法定义 Free/Pro/Team/Enterprise 四级体系
3. **RP 积分缺失** — 无法建立平台内经济系统
4. **Stripe 缺失** — 无法支持国际用户订阅
5. **API Key / PAT 缺失** — 无法支持 CLI/SDK 访问
6. **技术栈版本差距** — 长期维护风险

建议优先完成 Phase 1（网关基础设施）和 Phase 2（核心数据模型），这是后续所有功能的前置依赖。

---

> **报告生成依据**：
> - `docs/architecture/*.md` (01～10)
> - `docs/requirements/*.md` (01～04)
> - `docs/exoskeleton-improvement-from-core-audit.md`
> - 当前代码基线：`pom.xml`、`yudao-server/`、`yudao-module-system/`、`yudao-module-infra/`、`yudao-module-pay/`、`yudao-module-member/`
