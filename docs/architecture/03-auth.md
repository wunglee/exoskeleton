## 03. 注册/登陆/认证架构

### 03.1 设计原则

**安全优先**：所有认证流程遵循 OWASP 标准，密码强制 bcrypt 哈希（cost≥12），JWT 使用 RS256 非对称签名，Token 具备完整生命周期管理。

**多端统一**：Web、桌面客户端（Electron）、未来移动端共享同一套认证服务，通过 OAuth2 + PKCE 支持公共客户端。

**渐进式认证**：访客可浏览公开内容；执行仿真、创建项目等操作时才触发登录墙，降低注册摩擦。

### 03.2 认证方式矩阵

| 方式 | 适用场景 | 安全等级 | 实现 |
|------|----------|----------|------|
| 邮箱+密码 | 主站 Web 注册 | 中 | bcrypt + TOTP 可选 |
| GitHub OAuth | 开发者快捷登录 | 高 | OAuth2 Authorization Code + PKCE |
| Google OAuth | 通用快捷登录 | 高 | OAuth2 Authorization Code + PKCE |
| API Key | SDK / 自动化脚本 | 高 | HMAC-SHA256 签名请求 |
| 个人访问令牌 (PAT) | 第三方集成、CI/CD | 高 | 短令牌，细粒度权限，可撤销 |

### 03.3 认证流程架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        认证服务层 (Auth Service)                  │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ 本地认证     │  │ OAuth2 网关  │  │ API Key / PAT 验证      │ │
│  │ - 注册       │  │ - GitHub    │  │ - HMAC 签名校验          │ │
│  │ - 登录       │  │ - Google    │  │ - 权限范围检查           │ │
│  │ - 密码找回   │  │ - 状态防固定 │  │ - 速率限制               │ │
│  │ - TOTP       │  │ - 账号关联  │  │ - 令牌轮换               │ │
│  └──────┬──────┘  └──────┬──────┘  └────────────┬────────────┘ │
│         └─────────────────┴──────────────────────┘              │
│                              │                                  │
│                    ┌─────────┴─────────┐                        │
│                    │   Token Service   │                        │
│                    │ - JWT 签发/刷新    │                        │
│                    │ - Token 黑名单     │                        │
│                    │ - 会话审计日志     │                        │
│                    └─────────┬─────────┘                        │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────┐     │
│  │                           ▼                           │     │
│  │              Redis (Token 状态 + 黑名单)               │     │
│  └───────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

### 03.4 JWT Token 设计

**Access Token**（短期，15 分钟）：
```json
{
  "sub": "user_uuid",
  "iss": "nsca-auth",
  "aud": "nsca-api",
  "iat": 1714219200,
  "exp": 1714220100,
  "jti": "unique-token-id",
  "scope": "project:read project:write simulation:run",
  "membership_tier": "pro",
  "workspace_id": "ws_default"
}
```

**Refresh Token**（长期，7-30 天，可配置）：
- 存储于 httpOnly Secure SameSite=Strict Cookie
- 每次刷新后强制轮换（Rotation）
- 家族检测：检测被盗 Refresh Token 的复用，触发全家族撤销

**ID Token**（OpenID Connect，仅 OAuth 流程）：
- 包含用户基本资料（昵称、头像、邮箱验证状态）
- 用于前端快速渲染用户状态，不用于 API 鉴权

### 03.5 注册流程

**邮箱注册**：
```
1. 用户提交邮箱 + 密码
2. 后端校验邮箱格式、密码强度（≥12位，含大小写+数字+符号）
3. 发送验证邮件（含 6 位数字验证码或 magic link，15 分钟有效）
4. 用户点击验证 → 账户激活 → 自动登录（签发 Token）
5. 记录注册来源、IP、User-Agent 到审计日志
```

**OAuth 注册/登录**：
```
1. 前端生成 PKCE code_verifier + code_challenge
2. 重定向至 OAuth Provider 授权页
3. Provider 回调带 authorization_code
4. 后端用 code + code_verifier 换取 access_token
5. 查询 Provider 用户资料，匹配或创建本地账户
6. 若 Provider 邮箱已关联本地账户 → 提示账号关联
7. 签发 NSCA JWT Token，返回前端
```

### 03.6 密码安全

- **哈希算法**：bcrypt，cost factor = 12（约 250ms/次）
- **密码策略**：最小 12 位，禁止常见密码（检查 Have I Been Pwned API 或本地字典）
- **历史密码**：禁止复用最近 5 次密码
- **暴力破解防护**：同一账户 5 次失败锁定 15 分钟；同一 IP 10 次失败要求 CAPTCHA
- **密码找回**：基于邮箱的限时重置链接（30 分钟），使用后立即失效

### 03.7 会话管理

| 场景 | 会话策略 |
|------|----------|
| Web 浏览器 | Access Token 存内存（JS 变量），Refresh Token 存 httpOnly Cookie |
| 桌面客户端 | Access + Refresh 均存系统密钥链（Keychain / Windows Credential） |
| SDK/API | API Key 或 PAT，请求头 `Authorization: ApiKey <key>` |
| 多设备登录 | 默认允许，用户可在设置中查看活跃会话并撤销 |

**会话审计**：
- 每个 Token 签发记录：设备指纹、IP、地理位置、时间
- 用户可查看 "活跃会话" 列表，远程撤销可疑会话
- 检测到异常（新国家、新设备）发送安全告警邮件

### 03.8 接口契约

```yaml
# POST /api/v1/auth/register
request:
  email: string        # 合法邮箱
  password: string     # ≥12位，满足复杂度
  display_name: string # 2-30字符
  invitation_code: string?  # 可选邀请码

response_201:
  user_id: string
  email: string
  verification_sent: true
  message: "验证邮件已发送"

# POST /api/v1/auth/verify-email
request:
  email: string
  code: string         # 6位数字

response_200:
  access_token: string
  refresh_token: string
  expires_in: 900
  user: UserProfile

# POST /api/v1/auth/login
request:
  email: string
  password: string
  remember_me: boolean  # true → Refresh Token 30 天

response_200:
  access_token: string
  refresh_token: string
  expires_in: 900
  user: UserProfile

# POST /api/v1/auth/refresh
request:
  refresh_token: string  # Cookie 自动携带

response_200:
  access_token: string
  refresh_token: string   # 新轮换的 Token
  expires_in: 900

# POST /api/v1/auth/logout
response_204:
  # 清除 Cookie，将 Refresh Token 加入 Redis 黑名单

# POST /api/v1/auth/forgot-password
request:
  email: string

response_200:
  message: "如果该邮箱存在，重置链接已发送"

# POST /api/v1/auth/reset-password
request:
  token: string          # 重置链接中的 JWT
  new_password: string

# POST /api/v1/auth/oauth/github
# POST /api/v1/auth/oauth/google
request:
  code: string
  code_verifier: string   # PKCE
  redirect_uri: string

response_200:
  access_token: string
  refresh_token: string
  is_new_user: boolean
  user: UserProfile

# POST /api/v1/auth/api-keys
request:
  name: string
  scope: string[]         # 权限范围子集
  expires_days: int?      # null 表示永不过期

response_201:
  key_id: string
  api_key: string         # 仅返回一次，格式: nsca_live_xxx
  created_at: datetime

# GET /api/v1/auth/me
response_200:
  user_id: string
  email: string
  display_name: string
  avatar_url: string?
  email_verified: boolean
  membership_tier: string   # free | pro | team | enterprise
  created_at: datetime
  mfa_enabled: boolean
  has_password: boolean     # OAuth-only 用户可能无密码
```

### 03.9 用户模型扩展

```python
class User:
    user_id: UUID              # 全局唯一
    email: str                 # 唯一，验证后可用
    email_verified: bool
    display_name: str          # 展示名
    avatar_url: Optional[str]
    password_hash: Optional[str]   # OAuth-only 可能为空
    mfa_secret: Optional[str]      # TOTP 密钥（加密存储）
    membership_tier: str       # free | pro | team | enterprise
    workspace_id: UUID         # 默认工作区
    status: str                # active | suspended | deleted
    created_at: datetime
    last_login_at: datetime
    login_count: int

class OAuthAccount:
    oauth_id: UUID
    user_id: UUID
    provider: str              # github | google
    provider_account_id: str   # Provider 侧用户 ID
    access_token: str          # 加密存储
    refresh_token: Optional[str]
    expires_at: Optional[datetime]
    email: str                 # Provider 返回的邮箱
    avatar_url: Optional[str]

class Session:
    session_id: UUID
    user_id: UUID
    refresh_token_jti: str     # 关联的 Refresh Token
    device_fingerprint: str    # 设备指纹哈希
    ip_address: str
    user_agent: str
    created_at: datetime
    last_used_at: datetime
    expires_at: datetime
    revoked: bool
```

### 03.10 安全告警触发条件

| 条件 | 响应 |
|------|------|
| 短时间多国家 IP 登录 | 锁定账户，发送验证邮件 |
| Refresh Token 复用（家族检测） | 撤销整个 Token 家族，强制全设备重新登录 |
| 异常高频 API 调用 | 触发速率限制，CAPTCHA 挑战 |
| 密码出现在泄露数据库 | 登录时强制密码重置 |
| 新设备首次登录 | 发送邮件通知，用户可一键撤销 |
