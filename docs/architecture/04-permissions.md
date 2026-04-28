## 04. 权限系统架构

### 04.1 设计原则

**ABAC 为主，RBAC 为辅**：以属性基访问控制（Attribute-Based Access Control）为核心，支持动态策略；角色（RBAC）作为常见策略的快捷方式，降低配置复杂度。

**最小权限原则**：默认拒绝（Deny-by-Default），权限显式授予。用户仅能访问其被授权的资源，系统不推断隐式权限。

**资源级隔离**：权限控制到单个资源（项目、节点、模板），而非仅系统级功能开关。

**实时评估**：权限检查走内存策略缓存（Redis），P99 < 5ms，不阻塞仿真引擎。

### 04.2 权限模型：ABAC + RBAC 混合

```
┌─────────────────────────────────────────────────────────────────┐
│                      权限决策点 (Policy Decision Point)           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐   │
│   │   Subject   │      │   Action    │      │   Resource  │   │
│   │  (用户属性)  │      │  (操作类型)  │      │  (资源属性)  │   │
│   │             │      │             │      │             │   │
│   │ user_id     │      │ read        │      │ project_id  │   │
│   │ membership  │      │ write       │      │ owner_id    │   │
│   │ role        │      │ delete      │      │ visibility  │   │
│   │ team_ids    │      │ execute     │      │ domain      │   │
│   │ mfa_status  │      │ fork        │      │ is_template │   │
│   │ quota_left  │      │ merge       │      │ tier_lock   │   │
│   └──────┬──────┘      └──────┬──────┘      └──────┬──────┘   │
│          │                    │                    │          │
│          └────────────────────┼────────────────────┘          │
│                               ▼                                 │
│                    ┌─────────────────────┐                     │
│                    │   Policy Engine     │                     │
│                    │   (OPA / 自研)       │                     │
│                    │                     │                     │
│                    │ 规则1: 资源所有者    │                     │
│                    │        → 允许全部    │                     │
│                    │ 规则2: 公开项目      │                     │
│                    │        → 允许 read   │                     │
│                    │ 规则3: 团队成员      │                     │
│                    │        → 允许 write  │                     │
│                    │ 规则4: 会员等级      │                     │
│                    │        → 功能门控    │                     │
│                    └──────────┬──────────┘                     │
│                               ▼                                 │
│                         allow / deny                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 04.3 角色定义（RBAC 层）

| 角色 | 系统级权限 | 典型用户 |
|------|-----------|----------|
| **访客 (Guest)** | 浏览公开项目、搜索、查看专家列表 | 未登录用户 |
| **普通用户 (User)** | 创建私有项目、运行仿真（配额内）、fork 公开项目 | 已注册免费用户 |
| **专家 (Expert)** | 发布公开模型包、审核社区贡献、获得认证徽章 | 通过资质审核的研究者 |
| **团队管理员 (TeamAdmin)** | 管理团队成员、团队配额、团队项目权限 | 团队版订阅者 |
| **平台管理员 (Admin)** | 用户管理、内容审核、计费查看、系统配置 | NSCA 运营人员 |
| **超级管理员 (SuperAdmin)** | 全部权限，包括数据导出、紧急冻结 | 技术负责人 |

### 04.4 资源级权限矩阵

**项目 (Project) 权限**：

| 操作 | 所有者 | 团队成员 | 访客(公开项目) | 访客(私有项目) |
|------|--------|----------|----------------|----------------|
| 查看项目元数据 | ✓ | ✓ | ✓ | ✗ |
| 查看节点/仿真 | ✓ | ✓ | ✓ | ✗ |
| 运行仿真 | ✓ | ✓ | ✗ | ✗ |
| 编辑节点/属性 | ✓ | ✓ (需授权) | ✗ | ✗ |
| 删除项目 | ✓ | ✗ | ✗ | ✗ |
| Fork | ✓ | ✓ | ✓ | ✗ |
| 导出 .nsca | ✓ | ✓ | ✓ (仅公开) | ✗ |
| 修改成员 | ✓ | ✗ | ✗ | ✗ |
| 管理分支 | ✓ | ✓ (需授权) | ✗ | ✗ |
| 提交合并请求 | ✓ | ✓ | ✗ | ✗ |
| 审核合并请求 | ✓ | ✓ (需授权) | ✗ | ✗ |

**模型包 (Template/Model Pack) 权限**：

| 操作 | 作者 | 平台管理员 | 普通用户 |
|------|------|-----------|----------|
| 查看 | ✓ | ✓ | ✓ |
| 使用/导入 | ✓ | ✓ | ✓ (等级门控) |
| 编辑 | ✓ | ✗ | ✗ |
| 发布/更新 | ✓ | ✗ | ✗ |
| 审核白名单 | ✓ | ✓ | ✗ |
| 下架 | ✓ | ✓ | ✗ |

### 04.5 权限策略语言（Rego 风格伪代码）

```rego
package nsca.project

# 默认拒绝
default allow = false

# 规则1：资源所有者拥有全部权限
allow {
    input.subject.user_id == input.resource.owner_id
}

# 规则2：公开项目允许读操作
allow {
    input.resource.visibility == "public"
    input.action == "read"
}

# 规则3：团队成员权限
allow {
    input.resource.visibility == "team"
    input.subject.team_ids[_] == input.resource.team_id
    input.action in ["read", "write", "execute"]
}

# 规则4：Fork 公开项目
allow {
    input.resource.visibility == "public"
    input.action == "fork"
    input.subject.membership != "guest"
}

# 规则5：会员等级功能门控 - 运行仿真需要至少 free
deny {
    input.action == "execute_simulation"
    input.subject.membership == "guest"
}

# 规则6：会员等级功能门控 - 蒙特卡洛需要 pro
deny {
    input.action == "run_monte_carlo"
    input.subject.membership in ["free", "guest"]
}

# 规则7：专家认证才能发布模型包
allow {
    input.action == "publish_template"
    input.subject.role == "expert"
}

# 规则8：配额检查
allow {
    input.action == "execute_simulation"
    input.subject.remaining_ticks >= input.resource.estimated_ticks
}
```

### 04.6 动态策略引擎

**策略存储层级**：
1. **系统策略**：硬编码安全基线（如禁止访客执行仿真），不可覆盖
2. **组织策略**：企业客户自定义（如强制 MFA、IP 白名单）
3. **资源策略**：项目/模板所有者自定义（如邀请协作者、设置可见性）
4. **临时策略**：限时访问链接、一次性分享 Token

**策略评估流程**：
```
请求到达 → 解析 Subject/Action/Resource → 查询相关策略
    → 按优先级合并（系统 > 组织 > 资源 > 临时）
    → 任一 deny 则拒绝
    → 无 deny 且有 allow 则允许
    → 默认拒绝
```

### 04.7 团队/工作空间权限

```python
class Team:
    team_id: UUID
    name: str
    owner_id: UUID              # 团队创建者
    members: List[TeamMember]
    quota: TeamQuota            # 共享配额
    settings: TeamSettings

class TeamMember:
    team_id: UUID
    user_id: UUID
    role: str                   # owner | admin | editor | viewer
    joined_at: datetime
    invited_by: UUID

class TeamQuota:
    team_id: UUID
    max_projects: int
    max_storage_mb: int
    max_ticks_per_month: int
    max_members: int
    current_usage: UsageSnapshot
```

**团队角色权限**：

| 操作 | Owner | Admin | Editor | Viewer |
|------|-------|-------|--------|--------|
| 管理团队设置 | ✓ | ✓ | ✗ | ✗ |
| 邀请/移除成员 | ✓ | ✓ | ✗ | ✗ |
| 创建团队项目 | ✓ | ✓ | ✓ | ✗ |
| 编辑所有团队项目 | ✓ | ✓ | ✓ | ✗ |
| 仅编辑被指派项目 | ✓ | ✓ | ✓ | ✓ |
| 查看团队项目 | ✓ | ✓ | ✓ | ✓ |
| 管理团队配额 | ✓ | ✗ | ✗ | ✗ |
| 删除团队 | ✓ | ✗ | ✗ | ✗ |

### 04.8 邀请与分享机制

**项目邀请**：
```yaml
# POST /api/v1/projects/{id}/invites
request:
  emails: string[]           # 被邀请人邮箱
  role: string              # viewer | editor | admin
  message: string?          # 附言
  expires_days: int         # 默认 7 天

# 受邀人收到邮件 → 点击链接 → 若未注册则先注册 → 自动加入项目
```

**限时分享链接**：
```yaml
# POST /api/v1/projects/{id}/share-links
request:
  access_level: string      # read | write
  expires_hours: int        # 默认 24
  password: string?         # 可选密码保护
  allow_fork: boolean       # 是否允许 fork

response:
  share_url: "https://nsca.io/s/abc123"
  expires_at: datetime
```

### 04.9 接口契约

```yaml
# GET /api/v1/permissions/check
# 用于前端按钮显隐控制
request:
  resource_type: string     # project | template | team
  resource_id: string
  action: string

response_200:
  allowed: boolean
  reason: string?           # 拒绝原因（调试用途）
  required_tier: string?    # 如需升级，返回所需等级

# POST /api/v1/permissions/batch-check
# 批量检查，用于页面加载时批量判断按钮状态
request:
  checks:
    - resource_type: project
      resource_id: p1
      action: read
    - resource_type: project
      resource_id: p1
      action: write

response_200:
  results:
    - allowed: true
    - allowed: false
      reason: "您不是该项目的协作者"

# GET /api/v1/projects/{id}/members
response_200:
  owner: UserSummary
  members:
    - user: UserSummary
      role: editor
      joined_at: datetime
  pending_invites:
    - email: string
      role: viewer
      invited_at: datetime
      expires_at: datetime

# PUT /api/v1/projects/{id}/members/{user_id}
request:
  role: string              # viewer | editor | admin

# DELETE /api/v1/projects/{id}/members/{user_id}
# 移除成员（Owner 不能被移除）
```

### 04.10 缓存与性能

- **策略缓存**：用户权限矩阵缓存于 Redis，TTL = 5 分钟，权限变更时主动失效
- **热点资源**：公开项目、热门模板走 CDN + 本地缓存，绕过权限检查
- **批量预加载**：前端页面加载时批量查询权限，单次请求返回整页所需的所有 allow/deny 结果
