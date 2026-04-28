# PRD 分册：管理控制台

> **NSCA 外骨骼系统产品需求规约说明书（PRD）分册**
> 本文档是外骨骼 PRD 的拆分模块，对应架构文档：[../architecture/exoskeleton/09-admin.md](../architecture/exoskeleton/09-admin.md)
> 完整 PRD 索引见 [README.md](./README.md)
> 版本：v1.0 | 日期：2026-04-28

---

## 1. 管理控制台概述

管理控制台是平台运营的核心工具，面向管理员角色（Admin / Super Admin）提供用户管理、租户管理、计费管理、系统配置等功能。

## 2. 角色与权限

| 角色 | 权限范围 | 典型使用者 |
|------|---------|-----------|
| **Super Admin** | 全平台管理，可创建/删除租户 | 平台运营方 |
| **Tenant Admin** | 仅管理自己所辖租户的用户和配置 | 企业客户管理员 |
| **Support** | 只读查看用户、订阅、审计日志 | 客服团队 |

## 3. 功能模块

### 3.1 仪表板

进入管理控制台的首要页面，提供关键运营指标概览：

- 总用户数、今日新增、活跃用户（DAU/MAU）
- 各订阅计划分布（Free / Pro / Team / Enterprise）
- 当月收入（按渠道分：Stripe / 支付宝 / 微信）
- RP 总发行量 vs 总消耗量
- 系统健康状态（微服务存活、数据库连接、Redis 状态）

### 3.2 租户管理

| 功能 | 说明 | 角色 |
|------|------|------|
| 租户列表 | 分页查看所有租户，支持搜索、筛选、排序 | Super Admin |
| 创建租户 | 输入名称、Slug、管理员邮箱，自动创建 Logto 租户和管理员账号 | Super Admin |
| 租户详情 | 查看基本信息、成员列表、订阅状态、存储使用量 | Super Admin |
| 租户配置 | 编辑速率限制、最大用户数、存储上限、自定义域名 | Super Admin |
| 暂停/恢复 | 暂停租户（所有用户不可用）或恢复 | Super Admin |
| 删除租户 | 软删除，30 天后物理删除 | Super Admin |

### 3.3 用户管理

| 功能 | 说明 | 角色 |
|------|------|------|
| 用户列表 | 分页查看所有用户，支持按租户、角色、状态筛选 | Admin |
| 用户详情 | 查看基本信息、订阅历史、RP 余额与流水、API Key 列表 | Admin |
| 角色变更 | 手动升级/降级用户角色 | Super Admin |
| 状态管理 | 暂停/激活/封禁用户 | Admin |
| RP 调整 | 手动发放或扣除 RP（需填写原因，记录审计日志）| Super Admin |
| 强制密码重置 | 要求用户下次登录修改密码 | Admin |

### 3.4 订阅与计费管理

| 功能 | 说明 | 角色 |
|------|------|------|
| 订阅查询 | 按用户、租户、状态、计划类型搜索订阅 | Admin |
| 手动操作 | 升级/降级订阅、取消订阅、退款处理 | Super Admin |
| 支付记录 | 查看所有支付流水（Stripe + Jeepay），支持对账导出 | Admin |
| Webhook 事件 | 查看 Stripe/Jeepay Webhook 事件历史，重试失败事件 | Admin |
| RP 流水 | 全局 RP 交易记录查询与导出 | Admin |
| 套餐管理 | 创建/编辑/下线套餐计划 | Super Admin |

### 3.5 系统监控

| 功能 | 说明 |
|------|------|
| 服务健康 | 查看所有微服务状态（通过 Nacos 注册中心） |
| Sentinel 面板 | 实时限流/熔断状态，动态调整规则 |
| API 调用统计 | 按端点、租户、时间段查 API 调用量 |
| 错误监控 | 4xx/5xx 错误比例，异常趋势告警 |
| 审计日志 | 全局审计日志查询，按用户、操作、时间过滤 |

### 3.6 系统配置

| 配置项 | 说明 | 角色 |
|--------|------|------|
| 全局限流 | 默认租户速率限制、最大并发 | Super Admin |
| RP 汇率 | CNY ↔ RP / USD ↔ RP 汇率调整 | Super Admin |
| 支付配置 | Stripe API Key / Jeepay 商户信息配置 | Super Admin |
| 邮件模板 | 注册验证、密码重置、告警通知模板 | Super Admin |
| 功能开关 | 全局功能发布开关（灰度/上线/回滚）| Super Admin |

## 4. 管理控制台入口

- **URL**：`/admin`（独立前端应用，基于 Refine + Ant Design）
- **认证**：使用与主站相同的 Logto 认证，仅 admin / super_admin 角色可访问
- **前端**：`admin/` 目录下的独立 React 应用

## 5. 审计要求

- 所有管理操作记录审计日志：操作人、操作时间、操作内容、IP 地址
- RP 手动调整必须填写原因并经过二次确认
- 租户删除操作有 30 天冷静期
- 审计日志保留 7 年

---

## 对应架构文档

- [../architecture/exoskeleton/09-admin.md](../architecture/exoskeleton/09-admin.md) — 管理控制台架构（Spring Boot Admin REST API）
- [../architecture/exoskeleton/05-gateway-integration.md](../architecture/exoskeleton/05-gateway-integration.md) — 网关限流与监控集成
