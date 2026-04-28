## 09. 总控配置后台架构

### 09.1 设计原则

**操作可审计**：管理员所有操作记录完整审计日志，支持回滚与追责。

**最小权限**：管理员按角色分配最小必要权限，超级管理员操作需二次确认。

**实时生效**：配置变更即时同步到各服务，无需重启，支持灰度发布。

**多租户隔离**：企业版客户的自定义配置与平台全局配置隔离，互不影响。

### 09.2 后台架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    总控后台 (Admin Console)                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ 用户管理     │  │ 项目管理     │  │ 系统配置                 │ │
│  │ - 用户列表   │  │ - 项目列表   │  │ - 全局开关               │ │
│  │ - 权限调整   │  │ - 内容审核   │  │ - 费率设置               │ │
│  │ - 账户冻结   │  │ - 强制下架   │  │ - 维护模式               │ │
│  │ - 专家认证   │  │ - 资源统计   │  │ - 公告管理               │ │
│  └──────┬──────┘  └──────┬──────┘  └────────────┬────────────┘ │
│         │                │                      │              │
│  ┌──────┴──────┐  ┌──────┴──────┐  ┌────────────┴────────────┐ │
│  │ 计费管理     │  │ 审计日志     │  │ 运营分析                 │ │
│  │ - 发票查看   │  │ - 操作追踪   │  │ - DAU/MAU               │ │
│  │ - 退款处理   │  │ - 安全事件   │  │ - 转化漏斗               │ │
│  │ - 优惠码     │  │ - 登录审计   │  │ - 收入报表               │ │
│  │ - 对账      │  │ - 数据导出   │  │ - 领域热度               │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 09.3 用户管理

**用户列表**：
```yaml
GET /admin/api/v1/users
query:
  search: string?           # 邮箱/昵称模糊搜索
  tier: string?             # 等级筛选
  status: string?           # active | suspended | deleted
  expert_status: string?    # none | contributor | expert | chief
  registered_after: date?
  registered_before: date?
  sort: string              # created_at | last_login | total_ticks
  order: string             # asc | desc
  page: int
  per_page: int

response:
  users:
    - user_id: string
      email: string
      display_name: string
      avatar_url: string
      tier: string
      status: string
      expert_badges: string[]
      created_at: datetime
      last_login_at: datetime
      total_projects: int
      total_ticks: int
      storage_used_gb: float
      mfa_enabled: boolean
```

**用户操作**：
| 操作 | 所需角色 | 二次确认 | 审计记录 |
|------|----------|----------|----------|
| 查看用户详情 | Admin+ | 否 | 是 |
| 修改用户等级 | Admin+ | 是 | 是 |
| 冻结账户 | Admin+ | 是 | 是 |
| 删除账户 | SuperAdmin | 是（需理由） | 是 |
| 授予专家认证 | Admin+ | 是 | 是 |
| 撤销专家认证 | Admin+ | 是 | 是 |
| 重置用户密码 | Admin+ | 是 | 是 |
| 查看用户审计日志 | Admin+ | 否 | 是 |

### 09.4 项目管理

**项目列表**：
```yaml
GET /admin/api/v1/projects
query:
  search: string?
  visibility: string?       # public | private | team
  domain: string?           # 领域筛选
  status: string?           # active | archived | flagged
  is_template: boolean?
  sort: string              # created_at | star_count | fork_count
  page: int
  per_page: int

response:
  projects:
    - project_id: string
      name: string
      owner: UserSummary
      visibility: string
      domain: string
      status: string
      star_count: int
      fork_count: int
      total_ticks: int
      created_at: datetime
      last_active_at: datetime
      is_flagged: boolean     # 被举报标记
```

**内容审核**：
```yaml
# 举报队列
GET /admin/api/v1/reports
response:
  reports:
    - report_id: string
      type: string            # project | comment | user
      target_id: string
      reason: string          # spam | abuse | copyright | misinformation
      reporter: UserSummary
      reported_at: datetime
      status: string          # pending | reviewing | resolved

# 审核操作
POST /admin/api/v1/reports/{id}/resolve
request:
  action: string            # dismiss | hide | delete | warn_user | suspend_user
  reason: string            # 处理理由
  notify_reporter: boolean
```

### 09.5 系统配置

**全局开关**：
```yaml
GET /admin/api/v1/settings

settings:
  registration:
    enabled: boolean          # 是否开放注册
    require_invitation: boolean   # 是否需要邀请码
    allowed_domains: string[]     # 允许注册的邮箱域名

  simulation:
    max_tick_per_run: int         # 单次仿真最大 tick
    global_rate_limit: int        # 全局每秒最大仿真启动数
    maintenance_mode: boolean     # 维护模式
    maintenance_message: string

  billing:
    plans:
      - plan_id: string
        enabled: boolean
        price_monthly: string
        price_yearly: string
    tax_enabled: boolean
    default_currency: string

  community:
    require_expert_approval: boolean   # 发布模型包是否需要审核
    auto_flag_threshold: int           # 举报数自动标记阈值
    featured_projects: string[]        # 首页推荐项目 ID

  security:
    require_mfa_for_admin: boolean
    max_login_attempts: int
    session_timeout_hours: int
    ip_whitelist: string[]            # 管理后台 IP 白名单
```

**配置变更流程**：
```
管理员修改配置
    ↓
保存草稿（可选）
    ↓
提交变更
    ↓
影响分析（自动计算受影响的活跃用户）
    ↓
二次确认（影响 > 1000 用户需确认）
    ↓
写入配置中心（Consul / etcd）
    ↓
各服务监听变更，热更新
    ↓
记录审计日志
    ↓
发送变更通知（如维护公告）
```

### 09.6 计费管理

**发票管理**：
```yaml
GET /admin/api/v1/invoices
query:
  status: string?           # open | paid | past_due | refunded
  user_id: string?
  date_from: date?
  date_to: date?

response:
  invoices:
    - invoice_id: string
      user: UserSummary
      amount: string
      currency: string
      status: string
      created_at: datetime
      due_date: datetime
      paid_at: datetime?
      stripe_invoice_id: string?
```

**退款处理**：
```yaml
POST /admin/api/v1/invoices/{id}/refund
request:
  amount: string?           # 部分退款时指定
  reason: string
  processed_by: string      # 管理员 ID

response:
  refund_id: string
  status: string
```

**优惠码管理**：
```yaml
POST /admin/api/v1/promo-codes
request:
  code: string              # 如 "WELCOME2026"
  description: string
  discount_type: string     # percentage | fixed_amount
  discount_value: string    # 20 或 10.00
  applicable_plans: string[]
  max_uses: int             # 总使用次数上限
  max_uses_per_user: int    # 每用户使用次数
  valid_from: datetime
  valid_until: datetime
  first_time_only: boolean  # 仅新用户

GET /admin/api/v1/promo-codes
response:
  promo_codes:
    - code: string
      description: string
      uses_count: int
      max_uses: int
      valid: boolean
      created_at: datetime
```

### 09.7 审计日志

**操作审计**：
```yaml
GET /admin/api/v1/audit-logs
query:
  actor_type: string?       # user | admin | system
  actor_id: string?
  action: string?           # login | logout | create | update | delete
  resource_type: string?    # user | project | template | setting
  resource_id: string?
  date_from: datetime?
  date_to: datetime?
  page: int
  per_page: int

response:
  logs:
    - log_id: string
      actor_type: string
      actor_id: string
      actor_email: string
      action: string
      resource_type: string
      resource_id: string
      resource_name: string
      changes: object         # 变更前后对比
      ip_address: string
      user_agent: string
      timestamp: datetime
```

**安全事件**：
```yaml
GET /admin/api/v1/security-events
response:
  events:
    - event_id: string
      type: string           # suspicious_login | token_reuse | brute_force | data_export
      severity: string       # low | medium | high | critical
      user_id: string?
      description: string
      metadata: object
      detected_at: datetime
      status: string         # open | investigating | resolved | false_positive
```

### 09.8 运营分析

**仪表盘指标**：
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
    mrr_usd: string          # Monthly Recurring Revenue
    arr_usd: string          # Annual Recurring Revenue

  conversion:
    visitor_to_signup: float     # 访客到注册转化率
    signup_to_free_project: float
    free_to_pro: float
    pro_to_team: float

  top_domains:
    - domain: string
      project_count: int
      active_users: int
      total_ticks: int
```

**领域热度**：
```yaml
GET /admin/api/v1/analytics/domains
response:
  domains:
    - name: string           # 社会心理学 | 金融市场 | 地缘政治
      project_count: int
      public_projects: int
      total_ticks: int
      active_researchers: int
      trending_score: float   # 综合热度分
```

### 09.9 管理员角色

| 角色 | 权限范围 |
|------|----------|
| **运营专员 (Operator)** | 查看用户/项目列表、处理举报、查看分析报表、发送公告 |
| **客服专员 (Support)** | 查看用户详情、处理退款（限额内）、查看审计日志、重置用户密码 |
| **计费管理员 (BillingAdmin)** | 管理发票、处理退款、管理优惠码、查看收入报表、修改定价 |
| **平台管理员 (Admin)** | 全部后台功能，但不能修改超级管理员权限 |
| **超级管理员 (SuperAdmin)** | 全部功能 + 修改管理员权限 + 紧急系统冻结 + 数据导出 |

### 09.10 接口契约

```yaml
# 所有 /admin/api/v1/* 端点要求：
# - 请求头: Authorization: Bearer <admin_jwt>
# - 管理员 JWT 包含 scope: "admin" 或 "superadmin"
# - 来源 IP 需在白名单内（如配置了白名单）
# - 敏感操作需要 MFA（如配置了 require_mfa_for_admin）

# GET /admin/api/v1/me
response_200:
  admin_id: string
  email: string
  role: string
  permissions: string[]
  last_login_at: datetime
  mfa_enabled: boolean

# POST /admin/api/v1/settings
request:
  key: string
  value: any
  reason: string            # 变更理由，记录审计日志

# GET /admin/api/v1/health
response_200:
  services:
    - name: string
      status: string        # healthy | degraded | down
      latency_ms: int
      last_checked: datetime
```
