# 09. 总控配置后台架构

> NSCA 外骨骼基于 yudao-module-system 的管理后台框架扩展。yudao 已提供用户/角色/菜单/部门/租户/字典/通知等完整管理功能及其管理 UI。NSCA 新增会员等级管理、专家认证、内容审核、计费管理和运营分析等业务管理功能。

## 9.1 设计原则

**基于 yudao 管理后台扩展**：yudao-module-system + yudao-ui-admin 已提供开箱即用的后台管理界面（Vue3 + Element Plus）。NSCA 在 yudao 后台框架中新增菜单页面，而非重建管理后台。

**操作可审计**：yudao 已集成操作日志（`@OperateLog` 注解 + `system_operate_log` 表）。NSCA 所有管理操作遵循 yudao 的操作日志规范。

**最小权限**：复用 yudao 的角色-菜单-权限体系（`system_role` + `system_menu` + `@PreAuthorize`）。

**实时生效**：配置变更写入 yudao Nacos 配置中心（微服务模式）或 Redis（单体模式），无需重启。

**多租户隔离**：复用 yudao `TenantLineInnerInterceptor`，企业版客户的自定义配置与平台全局配置隔离。

## 9.2 yudao 管理后台基座

yudao 已提供以下管理功能，NSCA 直接复用：

| yudao 管理功能 | 数据表 | 是否存在 UI | NSCA 策略 |
|-------------|-------|-----------|----------|
| **用户管理** | `system_users` | 是 (Vue3) | 复用，新增会员等级/专家认证字段 |
| **角色管理** | `system_role` | 是 | 复用，新增 NSCA 业务角色 |
| **菜单管理** | `system_menu` | 是 | 复用，新增 NSCA 菜单项 |
| **部门管理** | `system_dept` | 是 | 直接复用 |
| **租户管理** | `system_tenant` + `system_tenant_package` | 是 | 直接复用 |
| **字典管理** | `system_dict_type` + `system_dict_data` | 是 | 复用，新增 NSCA 字典项 |
| **通知管理** | `system_notify_template` + `system_notify_message` | 是 | 复用，新增 NSCA 通知模板 |
| **操作日志** | `system_operate_log` | 是 | 直接复用 |
| **文件管理** | yudao-module-infra 文件服务 | 是 | 直接复用 |
| **代码生成** | yudao-module-infra 代码生成器 | 是 | 直接复用（加速 NSCA 模块开发） |
| **定时任务** | yudao-module-infra XXL-JOB 集成 | 是 | 复用，新增 NSCA 定时任务 |

## 9.3 后台架构

```
┌──────────────────────────────────────────────────────────────────────┐
│                  NSCA 管理后台 (yudao-ui-admin 扩展)                    │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  yudao 原有管理页面（复用）            NSCA 新增管理页面                   │
│  ┌────────────────────────┐    ┌────────────────────────────────┐   │
│  │ 用户管理 (system_users) │    │ 会员等级管理                      │   │
│  │ 角色管理 (system_role)  │    │ - member_level 管理 + 定价配置    │   │
│  │ 菜单管理 (system_menu)  │    │ - 专家认证审核                    │   │
│  │ 部门管理 (system_dept)  │    │ - 标签/徽章管理 (member_tag)      │   │
│  │ 租户管理 (system_tenant)│    └────────────────────────────────┘   │
│  │ 字典管理 (system_dict)  │                                        │
│  │ 通知管理 (system_notify)│    ┌────────────────────────────────┐   │
│  │ 文件管理 (infra)       │    │ 项目管理                         │   │
│  │ 定时任务 (infra)       │    │ - 核心透传项目列表                │   │
│  └────────────────────────┘    │ - 内容审核（举报队列）             │   │
│                                │ - 模型包审核                      │   │
│  ┌────────────────────────┐    └────────────────────────────────┘   │
│  │ 操作日志 (复用)         │                                        │
│  │ API 日志  (复用)        │    ┌────────────────────────────────┐   │
│  └────────────────────────┘    │ 计费管理                         │   │
│                                │ - 订阅订单查看                    │   │
│                                │ - 发票管理                        │   │
│                                │ - 退款处理                        │   │
│                                │ - 优惠码管理 (新增表)              │   │
│                                │ - 对账报告                        │   │
│                                └────────────────────────────────┘   │
│                                                                      │
│  ┌────────────────────────┐    ┌────────────────────────────────┐   │
│  │                        │    │ 运营分析                         │   │
│  │                        │    │ - DAU/MAU 仪表盘                 │   │
│  │                        │    │ - 转化漏斗                        │   │
│  │                        │    │ - 收入报表 (MRR/ARR)             │   │
│  │                        │    │ - 领域热度                        │   │
│  └────────────────────────┘    └────────────────────────────────┘   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## 9.4 用户管理（扩展 yudao system_users）

yudao 已提供用户列表、角色分配、状态管理。NSCA 新增会员和认证管理功能。

### 用户列表扩展字段

```yaml
GET /admin/api/v1/users (在 yudao /system/user/page 基础上扩展)
query:
  search: string?           # 邮箱/昵称/手机号模糊搜索
  levelId: int?             # member_level.id 筛选
  status: string?           # active | suspended | deleted
  expert_tag: string?       # 专家标签筛选
  registered_after: date?
  sort: string              # created_at | last_login | total_ticks

response:
  users:
    - user_id: long
      nickname: string
      email: string
      avatar_url: string
      level_name: string     # 从 member_user.levelId → member_level.name
      status: string
      honor_title: string    # 从 member_user.experience 计算荣誉级别
      badges: string[]       # 从 member_user.tagIds → member_tag.name
      created_at: datetime
      last_login_at: datetime
      mfa_enabled: boolean
```

### 管理员操作权限

| 操作 | 所需角色 | 二次确认 | yudao 操作日志 |
|------|----------|----------|-------------|
| 授予专家认证 | nsca_admin+ | 是 | @OperateLog 自动记录 |
| 撤销专家认证 | nsca_admin+ | 是 | @OperateLog 自动记录 |
| 修改用户等级 | nsca_admin+ | 是 | @OperateLog 自动记录 |
| 冻结/解冻账户 | nsca_admin+ | 是 | 复用 yudao 用户状态管理 |
| 删除账户 | nsca_super_admin | 是（需理由） | @OperateLog |
| 查看用户审计日志 | nsca_admin+ | 否 | 仅查询 |

## 9.5 内容审核

> yudao 无内容审核模块。NSCA 新增审核队列，通过 `system_menu` 新增菜单项接入。

```yaml
# 举报队列 (NSCA 新增)
GET /admin/api/v1/reports
response:
  reports:
    - report_id: string
      type: string            # project | comment | user | forum_post
      target_id: string
      reason: string
      reporter: UserSummary
      reported_at: datetime
      status: string          # pending | reviewing | resolved
      auto_flagged: boolean   # 是否自动标记

# 审核操作 (NSCA 新增)
POST /admin/api/v1/reports/{id}/resolve
request:
  action: string            # dismiss | hide | delete | warn_user | suspend_user
  reason: string
  notify_reporter: boolean
```

## 9.6 系统配置（扩展 yudao 配置体系）

### 全局配置

yudao 通过 Nacos Config / `application.yaml` 管理配置。NSCA 新增的业务配置通过 `system_config` 表管理（复用 yudao 的配置框架）：

| 配置分类 | NSCA 新增配置项 | 存储 |
|---------|---------------|------|
| registration | 是否开放注册、邮箱域名白名单 | system_config 表 |
| simulation | 单次仿真最大 Tick、全局限流 | system_config 表 |
| billing | 计划启用/禁用、定价、币种、税率 | member_level 表 + system_config |
| community | 专家审核开关、举报自动标记阈值、推荐项目 | system_config 表 |
| security | 管理员 MFA 强制、最大登录尝试次数、IP 白名单 | system_config 表 |

```
管理员修改配置
    ↓
POST /admin/api/v1/settings → 写入 system_config 表
    ↓
Nacos Config 广播变更（微服务模式）或 Redis Pub/Sub（单体模式）
    ↓
各服务监听 → 热更新
    ↓
@OperateLog 记录审计日志
```

## 9.7 计费管理

> yudao-module-pay 提供订单查询和退款接口。NSCA 新增优惠码管理、发票管理和收入报表。

```yaml
# 优惠码管理 (NSCA 新增表 nsca_promo_code)
POST /admin/api/v1/promo-codes
request:
  code: string              # "WELCOME2026"
  discount_type: string     # percentage | fixed_amount
  discount_value: string
  applicable_plan_ids: long[]  # member_level.id 列表
  max_uses: int
  valid_from: datetime
  valid_until: datetime
  first_time_only: boolean

# 发票管理 (NSCA 新增 billing_invoice 表)
GET /admin/api/v1/invoices
query:
  status: string?
  user_id: long?
  date_from: date?
  date_to: date?

# 退款处理 (复用 yudao PayRefundService + 新增审核流程)
POST /admin/api/v1/invoices/{id}/refund
```

## 9.8 运营分析

```yaml
GET /admin/api/v1/analytics/dashboard
response:
  today:
    new_users: int
    active_users: int
    simulation_runs: int
    ticks_consumed: int
    revenue_usd: string
    revenue_cny: string
  this_month:
    mau: int
    new_subscriptions: int
    churned_subscriptions: int
    mrr_usd: string
    arr_usd: string
  conversion:
    visitor_to_signup: float
    signup_to_free_project: float
    free_to_pro: float
    pro_to_team: float
  top_domains:
    - domain: string
      project_count: int
      active_users: int
```

## 9.9 管理员角色（扩展 yudao system_role）

| 角色 | yudao role_code | 权限范围 |
|------|----------------|---------|
| **运营专员** | `nsca_operator` | 查看用户/项目列表、处理举报、查看分析报表、发送公告 |
| **客服专员** | `nsca_support` | 查看用户详情、处理退款（限额内）、查看审计日志 |
| **计费管理员** | `nsca_billing_admin` | 管理发票、处理退款、管理优惠码、查看收入报表 |
| **平台管理员** | `nsca_admin` | 全部后台功能，但不能修改超级管理员权限 |
| **超级管理员** | `nsca_super_admin` | 全部功能 + 修改管理员权限 + 系统冻结 + 数据导出 |

## 9.10 yudao 扩展映射

| yudao 原有 | 方式 | NSCA 扩展 |
|-----------|------|----------|
| `system_users` 表 | 扩展（间接） | member_user 关联 + 会员等级/荣誉/徽章字段 |
| `system_role` 表 | 新增记录 | nsca_operator, nsca_support, nsca_billing_admin, nsca_admin, nsca_super_admin |
| `system_menu` 表 | 新增记录 | NSCA 管理菜单项（会员管理/内容审核/计费管理/运营分析） |
| `system_dict` 表 | 新增字典项 | NSCA 业务字典（领域分类、举报类型、折扣类型等） |
| `system_operate_log` 表 | 直接复用 | @OperateLog 注解自动记录 |
| `system_notify` 表 | 新增模板 | NSCA 业务通知模板（订阅到期提醒、专家认证通知等） |
| yudao-ui-admin | 新增页面 | Vue3 组件：会员等级管理、内容审核、优惠码管理、运营仪表盘 |
| yudao-module-infra 文件服务 | 直接复用 | 用户头像、模型包文件 |
| yudao-module-infra 代码生成 | 直接复用 | 加速 NSCA 新增表的 CRUD 代码生成 |
| — | **新增表** | `nsca_promo_code`、`nsca_report`、`billing_invoice` |
| — | **新增 Controller** | `NscaAdminController`（挂载在 yudao-module-system） |

---

## 参考

- [yudao 管理后台文档](https://doc.iocoder.cn/admin-ui/)
- [yudao 操作日志文档](https://doc.iocoder.cn/operate-log/)
- [yudao 代码生成器](https://doc.iocoder.cn/code-generator/)
