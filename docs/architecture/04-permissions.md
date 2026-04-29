# 04. 权限系统架构

> NSCA 外骨骼基于 yudao-module-system 的 RBAC 权限框架扩展，复用其角色/菜单/权限管理，新增 ABAC（属性基访问控制）引擎、资源级权限和团队/工作空间权限。

## 4.1 设计原则

**基于 yudao RBAC 扩展 ABAC**：yudao 已提供完整的角色-菜单-权限体系（`system_role` + `system_menu` + `@PreAuthorize`）。NSCA 在其之上新增 ABAC 策略引擎，用于资源级（项目/节点/模板）权限控制。

**最小权限原则**：默认拒绝（Deny-by-Default），权限显式授予。yudao 的 `@PreAuthorize` + `@PermitAll` 机制确保系统级权限不遗漏。

**资源级隔离**：ABAC 层将权限控制到单个资源（项目、节点、模板），超越 yudao RBAC 的系统级功能开关。

**实时评估**：ABAC 策略走 Redis 缓存，P99 < 5ms，不阻塞仿真引擎。RBAC 检查由 yudao `SecurityFrameworkService` 在方法级完成。

## 4.2 yudao RBAC 基座

yudao-module-system 已提供以下 RBAC 能力，NSCA 直接复用：

| yudao 能力 | 数据表 | NSCA 策略 |
|-----------|-------|----------|
| **角色管理** | `system_role` (name, code, dataScope, status) | 直接复用，新增 NSCA 角色 |
| **菜单/权限** | `system_menu` (name, permission, type) | 直接复用，新增 NSCA 权限项 |
| **角色-菜单关联** | `system_role_menu` | 直接复用 |
| **用户-角色关联** | `system_user_role` | 直接复用 |
| **方法级鉴权** | `@PreAuthorize("@ss.hasPermission('xxx')")` | 直接复用 |
| **免认证端点** | `@PermitAll` 注解自动注册 | 直接复用 |
| **多租户数据隔离** | `TenantLineInnerInterceptor` | 直接复用 |
| **数据权限范围** | `dataScope` (全部/本部门/本人等) | 扩展 → 资源级 ABAC |

### yudao 权限检查流程（现有）

```
请求 → TokenAuthenticationFilter（认证）
     → SecurityFrameworkService.hasPermission("project:write")
     → 查询当前用户角色 → 角色关联的权限列表 → 匹配
     → @PreAuthorize 拦截 → 返回 403 或放行
```

### NSCA 扩展后的双层权限

```
请求 → TokenAuthenticationFilter（认证，复用 yudao）
     → 层级 1: RBAC 检查（复用 yudao @PreAuthorize）
        → 系统级权限：管理后台菜单、API 访问、用户管理
     → 层级 2: ABAC 检查（NSCA 新增）
        → 资源级权限：项目所有权、团队成员、公开可见性、会员门控
```

## 4.3 权限模型：RBAC + ABAC 混合

```
┌──────────────────────────────────────────────────────────────────────┐
│                      权限决策点 (Policy Decision Point)                │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   yudao RBAC 层（复用）                                                │
│   ┌────────────────────────────────────────────────────────────┐    │
│   │  @PreAuthorize("@ss.hasPermission('project:write')")       │    │
│   │  system_role → system_role_menu → system_menu               │    │
│   │  系统级：是否允许访问「项目管理」功能                            │    │
│   └────────────────────────────────────┬───────────────────────┘    │
│                                        ▼                              │
│   NSCA ABAC 层（新增）                                                  │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐    │
│   │   Subject   │  │   Action    │  │   Resource              │    │
│   │  (用户属性)  │  │  (操作类型)  │  │  (资源属性)              │    │
│   │             │  │             │  │                         │    │
│   │ user_id     │  │ read        │  │ project_id              │    │
│   │ membership  │  │ write       │  │ owner_id                │    │
│   │ role        │  │ delete      │  │ visibility              │    │
│   │ team_ids    │  │ execute     │  │ team_id                 │    │
│   │ mfa_status  │  │ fork        │  │ tier_lock               │    │
│   │ quota_left  │  │ merge       │  │ is_template             │    │
│   └──────┬──────┘  └──────┬──────┘  └────────────┬────────────┘    │
│          └─────────────────┼──────────────────────┘                 │
│                            ▼                                         │
│                 ┌─────────────────────┐                             │
│                 │   ABAC Policy       │                             │
│                 │   Engine (自研)      │                             │
│                 │                     │                             │
│                 │ 规则1: 资源所有者     │                             │
│                 │ 规则2: 公开项目 read  │                             │
│                 │ 规则3: 团队成员 write │                             │
│                 │ 规则4: 会员等级门控   │                             │
│                 └──────────┬──────────┘                             │
│                            ▼                                         │
│                      allow / deny                                    │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## 4.4 角色定义（yudao RBAC 层扩展）

> yudao 原有角色（超级管理员、租户管理员、普通租户）保留。以下为 NSCA 业务角色，通过 yudao `system_role` 表新增记录实现。

| 角色 | yudao role_code | 系统级权限 | 典型用户 |
|------|----------------|-----------|----------|
| **访客 (Guest)** | `nsca_guest` | 浏览公开项目、搜索、查看专家列表 | 未登录用户 (anonymous) |
| **普通用户 (User)** | `nsca_user` | 创建私有项目、运行仿真（配额内）、fork 公开项目 | 已注册免费用户 |
| **专家 (Expert)** | `nsca_expert` | 发布公开模型包、审核社区贡献、获得认证徽章 | 通过资质审核的研究者 |
| **团队管理员** | `nsca_team_admin` | 管理团队成员、团队配额、团队项目权限 | 团队版订阅者 |
| **平台管理员** | `nsca_admin` | 用户管理、内容审核、计费查看、系统配置 | NSCA 运营人员 |
| **超级管理员** | `nsca_super_admin` | 全部权限，包括数据导出、紧急冻结 | 技术负责人 |

> **yudao 角色映射**：NSCA 角色通过 `system_role` 表的 `code` 字段区分。yudao 原有的 `super_admin`、`tenant_admin`、`tenant_user` 继续用于管理后台，NSCA 的业务角色作为**额外 role** 授予用户。

## 4.5 资源级权限矩阵（ABAC 层）

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

## 4.6 权限策略引擎（NSCA 新增）

> yudao 无策略引擎。NSCA 新增轻量 ABAC 引擎（Java 实现，不引入 OPA），策略存储于 MySQL + Redis 缓存。

### 策略优先级（数字越小优先级越高）

1. **系统策略**（100）：硬编码安全基线，如禁止访客执行仿真，不可覆盖
2. **组织策略**（200）：企业客户自定义（如强制 MFA、IP 白名单）
3. **资源策略**（300）：项目/模板所有者自定义（如邀请协作者、设置可见性）
4. **临时策略**（400）：限时访问链接、一次性分享 Token

### 策略评估流程

```
ABAC 请求 → 解析 Subject/Action/Resource
         → 查询关联策略（Redis 缓存，未命中查 MySQL system_policy 表）
         → 按优先级降序评估（100 → 400）
         → 遇任一 DENY → 立即拒绝
         → 需至少一条 ALLOW → 放行
         → 无匹配策略 → 默认拒绝
```

### 策略规则定义（Java 风格）

策略规则存储于 `system_policy` 表（NSCA 新增）：

```sql
CREATE TABLE system_policy (
    id          BIGINT PRIMARY KEY AUTO_INCREMENT,
    name        VARCHAR(100) NOT NULL COMMENT '策略名称',
    priority    INT NOT NULL DEFAULT 300,
    subject_cond JSON COMMENT 'Subject 条件: {"membership":["pro","team"]}',
    action_cond  JSON COMMENT 'Action 条件: ["read","write","fork"]',
    resource_cond JSON COMMENT 'Resource 条件: {"visibility":"public"}',
    effect      VARCHAR(10) NOT NULL COMMENT 'ALLOW 或 DENY',
    enabled     TINYINT DEFAULT 1,
    created_at  DATETIME NOT NULL
);
```

### 策略评估 Java 伪代码

```java
// NSCA 新增 AbacPolicyEngine (yudao 无对应组件)
@Service
public class AbacPolicyEngine {

    public boolean evaluate(Subject subject, String action, Resource resource) {
        List<Policy> policies = policyCache.getApplicablePolicies(
            subject.userId(), action, resource.type());

        for (Policy policy : policies) {  // 按 priority ASC 排列
            if (!policy.matches(subject, action, resource)) continue;

            if (policy.effect() == Effect.DENY) return false;  // 遇 DENY 立即拒绝
        }

        // 至少需要一条 ALLOW 策略匹配
        return policies.stream()
            .filter(p -> p.matches(subject, action, resource))
            .anyMatch(p -> p.effect() == Effect.ALLOW);
    }
}
```

## 4.7 团队/工作空间权限（NSCA 新增）

> yudao 的部门（`system_dept`）是组织架构树，不支持跨部门协作。NSCA 新增团队模型独立于部门体系。

### 团队数据模型

```sql
-- NSCA 新增表族（不影响 yudao 原有表）
CREATE TABLE nsca_team (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    name            VARCHAR(100) NOT NULL,
    owner_id        BIGINT NOT NULL COMMENT '关联 system_users.id',
    tenant_id       BIGINT NOT NULL COMMENT 'yudao 租户隔离',
    max_projects    INT DEFAULT 5,
    max_members     INT DEFAULT 10,
    max_ticks_per_month BIGINT DEFAULT 10000,
    created_at      DATETIME NOT NULL,
    FOREIGN KEY (owner_id) REFERENCES system_users(id)
);

CREATE TABLE nsca_team_member (
    id          BIGINT PRIMARY KEY AUTO_INCREMENT,
    team_id     BIGINT NOT NULL,
    user_id     BIGINT NOT NULL,
    role        VARCHAR(20) NOT NULL COMMENT 'owner | admin | editor | viewer',
    joined_at   DATETIME NOT NULL,
    FOREIGN KEY (team_id) REFERENCES nsca_team(id),
    FOREIGN KEY (user_id) REFERENCES system_users(id),
    UNIQUE(team_id, user_id)
);
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

## 4.8 邀请与分享机制

**项目邀请**（NSCA 新增端点，挂载在 yudao-module-system Controller）：

```yaml
# POST /api/v1/projects/{id}/invites
request:
  emails: string[]           # 被邀请人邮箱
  role: string              # viewer | editor | admin
  message: string?          # 附言
  expires_days: int         # 默认 7 天
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

## 4.9 接口契约

```yaml
# GET /api/v1/permissions/check
# 前端按钮显隐控制（RBAC 由 @PreAuthorize 处理，此端点用于 ABAC 资源级检查）
request:
  resource_type: string     # project | template | team
  resource_id: string
  action: string

response_200:
  allowed: boolean
  reason: string?           # 拒绝原因
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
```

## 4.10 缓存与性能

- **RBAC 权限缓存**：yudao `SecurityFrameworkService` 内部缓存用户权限列表，权限变更时主动失效
- **ABAC 策略缓存**：`system_policy` 表对应的策略缓存于 Redis，TTL = 5 分钟
- **热点资源**：公开项目、热门模板走 Caffeine 本地缓存 + Redis 二级缓存
- **批量预加载**：前端页面加载时批量查询 ABAC 权限，单次请求返回整页所需的所有判定结果

## 4.11 yudao 扩展映射

| yudao 原有 | 方式 | NSCA 扩展 |
|-----------|------|----------|
| `system_role` 表 | 新增记录 | NSCA 业务角色（nsca_user, nsca_expert, nsca_team_admin 等） |
| `system_menu` 表 | 新增记录 | NSCA 权限项（project:write, simulation:execute, template:publish 等） |
| `@PreAuthorize("@ss.hasPermission('xxx')")` | 直接复用 | 系统级 API 权限检查 |
| `SecurityFrameworkService` | 直接复用 | 用户权限列表查询、角色判断 |
| `TokenAuthenticationFilter` | 直接复用 | 提取 LoginUser 供 ABAC 引擎使用 |
| — | **新增表** | `system_policy`（ABAC 策略）, `nsca_team`, `nsca_team_member`, `nsca_project_acl` |
| — | **新增 Service** | `AbacPolicyEngine`, `TeamService`, `ProjectPermissionService` |

---

## 参考

- [yudao 权限认证文档](https://doc.iocoder.cn/ruoyi-vue-pro/auth/)
- [Spring Security Method Security](https://docs.spring.io/spring-security/reference/servlet/authorization/method-security.html)
- [ABAC 模型 NIST SP 800-162](https://csrc.nist.gov/publications/detail/sp/800-162/final)
