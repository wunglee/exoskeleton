# 计划：基于 yudao member 模块重写计费与会籍架构文档

## 背景

当前 `06-billing.md` 和 `08-membership.md` 的数据模型使用独立的 Python/伪代码定义（`SubscriptionPlan`、`UserSubscription`、`ResearchPointsAccount` 等），未体现与 yudao member 模块的继承/扩展关系。用户要求将这些文档改写为**基于 yudao member 模块扩展**的方式，明确展示哪些是复用 yudao 的、哪些是新增的。

## 涉及文件

- **重写**: `docs/architecture/06-billing.md` — 计费系统 + RP 积分体系
- **重写**: `docs/architecture/08-membership.md` — 会员等级 + 功能门控 + 排行榜
- **不修改**: `docs/requirements/02-subscription-plans.md`（需求文档保持不变）

## 改写的核心策略

每个 yudao DO 对应一个扩展策略表，格式：

| yudao 字段 | NSCA 扩展 | 方式 |
|-----------|---------|------|
| `member_level.name` | 订阅计划名（Free/Pro/Team/Enterprise） | 直接使用 |
| `member_level.discountPercent` | 保留，可用于年付折扣 | 直接使用 |
| — | `price_monthly`, `price_yearly`, `currency`, `features(json)` | **新增字段** |

## 具体改写计划

### 06-billing.md 改写（计费 + RP）

**保留不变的部分**：
- §6.1 设计原则
- §6.2 计费维度
- §6.3 计费模型架构图
- §6.5 计量采集机制
- §6.6 超额计费与保护
- §6.7 配额实时守护
- §6.8 发票与税务
- §6.9 接口契约
- §6.10 计费事件流

**需要改写的部分**：

1. **§6.4 订阅计划** — 完全重写：
   - 数据模型从 Python 伪代码改为：扩展 `member_level` 表 + 新增 `subscription_plan_extension` 表
   - 新增 `user_subscription` 表（订阅状态机）
   - 展示 yudao 扩展映射表
   - 新增 `subscription_plan` 的 SQL DDL（展示新增字段）

2. **§6.11 RP 积分系统** — 完全重写：
   - 废弃独立的 `ResearchPointsAccount` Python 类
   - 改为：保留 `member_point_record` 作为流水日志，新增 `rp_account` + `rp_lot` 表
   - 新增 yudao 扩展映射表
   - 新增 RP 账户、批次、交易的 SQL DDL
   - FIFO 消费逻辑的 Java 伪代码（替代 Python）
   - 防刷机制的 Java/Redis 实现

3. **新增 §6.12 yudao 扩展总览** — 汇总所有扩展点的一张表

### 08-membership.md 改写（会员等级 + 功能门控）

**保留不变的部分**：
- §8.1 设计原则
- §8.5 功能门控实现
- §8.6 升级/降级流程
- §8.7 排行榜接口
- §8.8 接口契约
- §8.9 会员事件流

**需要改写的部分**：

1. **§8.2 会员等级体系** — 重写：
   - 从 Python 伪代码改为：扩展 `member_level` 表
   - 展示 yudao `member_level` → `subscription_plan` 扩展映射
   - `features` JSON 字段的 schema 定义

2. **新增 §8.10 yudao 扩展映射** — 汇总表：
   - `member_level` → 订阅计划
   - `member_user.levelId` → 用户当前订阅
   - `member_user.experience` → 荣誉级别分
   - `member_user.tagIds` → 专家认证徽章
   - `member_user.groupId` → 团队版用户分组

3. **§8.3-8.4** — 将原来的数据模型定义替换为基于 yudao 的扩展定义

## 代码风格

- 数据模型：优先使用 SQL DDL + Java DO 类（yudao 风格），而非 Python 伪代码
- 业务逻辑：优先使用 Java 伪代码（Spring Service 风格）
- 前端：保持 TypeScript/React 示例不变
- 表格：用于展示 yudao→NSCA 扩展映射

## 验证方法

1. 对比改写前后的需求覆盖：确保 02-subscription-plans.md 中的所有需求点仍在架构文档中有对应设计
2. 扩展映射完整性：每个 yudao 表/字段要么标记"直接复用"，要么有明确的 NSCA 扩展
3. 数据模型一致性：06-billing.md 和 08-membership.md 中的表定义不相互矛盾
