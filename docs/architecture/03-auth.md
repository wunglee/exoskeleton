# 03. 注册/登录/认证架构

> NSCA 外骨骼基于 yudao-module-system 的认证体系扩展，复用其 OAuth2 授权服务器、JustAuth 社交登录和 RBAC 权限框架，新增 JWT RS256 无状态令牌、API Key 管理、TOTP 多因素认证和 Logto OIDC 集成。

## 3.1 设计原则

**基于 yudao 扩展，不推翻重来**：yudao-module-system 已提供完整的登录/登出/OAuth2/社交登录/BCrypt 密码体系。NSCA 在其基础上扩展 JWT 令牌格式、API Key 渠道和 TOTP MFA，不重写 yudao 已有的认证逻辑。

**安全优先**：密码强制 bcrypt 哈希（cost≥12，高于 yudao 默认值 4），JWT 使用 RS256 非对称签名，Token 具备完整生命周期管理。

**多端统一**：Web、桌面客户端（Electron）、未来移动端共享同一套认证服务，通过 OAuth2 + PKCE 支持公共客户端。

**渐进式认证**：访客可浏览公开内容；执行仿真、创建项目等操作时才触发登录墙，降低注册摩擦。

## 3.2 yudao 认证基座

yudao-module-system 已提供以下认证能力，NSCA 直接复用：

| yudao 能力 | 实现方式 | NSCA 策略 |
|-----------|---------|----------|
| **用户名/密码登录** | `AdminAuthServiceImpl.authenticate()` → BCrypt | 复用，提升 cost 因子 |
| **OAuth2 授权服务器** | `OAuth2TokenServiceImpl` + 5 种授权模式 | 扩展 → 新增 JWT 令牌格式 |
| **令牌存储** | MySQL (`system_oauth2_access_token`) + Redis 缓存 | 扩展 → 新增 JWT + 保留不透明令牌兼容 |
| **社交登录** | JustAuth (40+ 平台: GitHub/微信/钉钉/Google 等) | 复用 + 新增 Logto OIDC |
| **RBAC 权限** | Spring Security `@PreAuthorize` + `SecurityFrameworkService` | 直接复用 |
| **多租户隔离** | `TenantBaseDO` + `TenantLineInnerInterceptor` | 直接复用 |
| **BCrypt 密码编码** | `BCryptPasswordEncoder`（默认 cost=4） | 扩展 → cost 提升至 12 |
| **滑块验证码** | AJ-Captcha | 复用，按需启用 |

### yudao 令牌系统现状

yudao 当前使用**不透明令牌**（UUID），每次 API 调用需要 Redis/MySQL 查找验证：

```
客户端 → Authorization: Bearer <UUID>
       → TokenAuthenticationFilter
       → OAuth2TokenCommonApi.checkAccessToken(token)
       → Redis 查询 (key: oauth2_access_token:{token})
       → 未命中 → MySQL 查询 → 写回 Redis
```

**NSCA 扩展方案**：引入 JWT RS256 作为主要令牌格式，网关层离线验签（无需 Redis 查询），仅在 Token 刷新/撤销时访问存储。保留不透明令牌为兼容模式。

## 3.3 认证方式矩阵

| 方式 | 适用场景 | 安全等级 | yudao 基础 | NSCA 扩展 |
|------|----------|----------|-----------|----------|
| 邮箱+密码 | 主站 Web 注册 | 中 | yudao `AdminAuthServiceImpl` | bcrypt cost=12 + TOTP 可选 |
| GitHub OAuth | 开发者快捷登录 | 高 | yudao JustAuth | — |
| Google OAuth | 通用快捷登录 | 高 | yudao JustAuth | — |
| Logto OIDC | 企业 SSO / 通用登录 | 高 | — | **新增** Spring Security OAuth2 Client |
| API Key | SDK / 自动化脚本 | 高 | — | **新增** HMAC-SHA256 签名 |
| 个人访问令牌 (PAT) | 第三方集成、CI/CD | 高 | — | **新增** 短令牌，细粒度权限 |

## 3.4 认证流程架构

```
┌──────────────────────────────────────────────────────────────────────┐
│                    认证服务层 (yudao-module-system 扩展)                │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  yudao 原有（复用）              NSCA 扩展（新增）                       │
│  ┌────────────────────┐    ┌────────────────────────────────────┐   │
│  │ 本地认证             │    │ JWT Token Service                  │   │
│  │ - 用户名/密码登录    │    │ - RS256 签发/验证                   │   │
│  │ - 短信验证码登录     │    │ - Refresh Token 轮换 + 家族检测     │   │
│  │ - 注册（用户名+密码） │    │ - Token 黑名单（Redis Set）        │   │
│  │ - 密码重置          │    └────────────────────────────────────┘   │
│  │ - BCrypt 编码       │                                            │
│  └────────────────────┘    ┌────────────────────────────────────┐   │
│                            │ API Key / PAT 服务                   │   │
│  ┌────────────────────┐    │ - HMAC-SHA256 签名校验               │   │
│  │ OAuth2 社交登录      │    │ - 权限范围检查                      │   │
│  │ - JustAuth 40+ 平台 │    │ - 速率限制                          │   │
│  │ - GitHub/Google/    │    │ - 令牌轮换                          │   │
│  │   微信/钉钉/支付宝   │    └────────────────────────────────────┘   │
│  └────────────────────┘                                            │
│                            ┌────────────────────────────────────┐   │
│  ┌────────────────────┐    │ TOTP MFA 服务                       │   │
│  │ Spring Security     │    │ - TOTP 密钥生成                     │   │
│  │ - RBAC 权限框架      │    │ - 二维码配置                        │   │
│  │ - @PreAuthorize     │    │ - 备份恢复码                        │   │
│  │ - SecurityFramework │    │ - 信任设备（30 天）                 │   │
│  └────────────────────┘    └────────────────────────────────────┘   │
│                                                                      │
│  存储层                                                               │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  MySQL (yudao system_users + system_oauth2_* 表族)            │   │
│  │  Redis (JWT 黑名单 + Rate Limit + Session 缓存)                │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## 3.5 JWT Token 设计

> **扩展点**：yudao 的不透明令牌（UUID）替换为 JWT RS256。通过 yudao 的 `OAuth2TokenServiceImpl` 扩展点注入 JWT 签发逻辑。

### Access Token（短期，15 分钟）

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
  "tenant_id": "t_abc123"
}
```

**与 yudao 不透明令牌的关键差异**：

| 维度 | yudao 不透明令牌 | NSCA JWT |
|------|-----------------|---------|
| 验证方式 | Redis/MySQL 查找 | 网关层 RSA 公钥离线验签 |
| 用户信息携带 | 查 DB 获取 | 令牌内嵌（membership_tier, tenant_id） |
| 撤销延迟 | 即时（删除 Redis/MySQL） | 需配合黑名单（最多 15min 窗口） |
| 大小 | 32 字符 | ~800 字符 |
| 适用场景 | 管理后台（低频） | API 网关（高频） |

### Refresh Token（长期，7-30 天，可配置）

- 存储于 httpOnly Secure SameSite=Strict Cookie
- 每次刷新后强制轮换（Rotation）
- **家族检测**：检测被盗 Refresh Token 的复用，触发全家族撤销

### ID Token（OpenID Connect，仅 OAuth 流程）

- 包含用户基本资料（昵称、头像、邮箱验证状态）
- 用于前端快速渲染用户状态，不用于 API 鉴权

### 网关层 JWT 验证流程

```
客户端 → Authorization: Bearer <JWT>
       → yudao-gateway (扩展 JwtAuthFilter)
       → 读取 JWKS (RSA 公钥)
       → 离线验签 (签名 + 过期 + 黑名单检查)
       → 注入 Header: X-User-Id, X-Tenant-Id, X-Features
       → 转发至 yudao-module-system 或核心引擎
```

> yudao-gateway 的 `TokenAuthenticationFilter` 当前通过 Feign RPC 调用 system 模块验证令牌。NSCA 扩展一个前置的 `JwtAuthFilter`，在 RPC 调用前先尝试 JWT 离线验签，仅在不透明令牌场景回退到原有 RPC 流程。

## 3.6 注册流程

### 邮箱注册（扩展 yudao AdminAuthServiceImpl.register）

```
1. 用户提交邮箱 + 密码
2. 后端校验邮箱格式、密码强度（≥12位，含大小写+数字+符号）
3. yudao UserService 检查用户名/邮箱唯一性
4. 发送验证邮件（含 6 位数字验证码或 magic link，15 分钟有效）
5. 用户点击验证 → 账户激活 → 自动登录（签发 JWT）
6. 记录注册来源、IP、User-Agent 到审计日志（复用 yudao system_login_log）
```

### OAuth 注册/登录（复用 yudao JustAuth + 扩展 Logto OIDC）

```
1. 前端生成 PKCE code_verifier + code_challenge
2. 重定向至 OAuth Provider 授权页
3. Provider 回调带 authorization_code
4. 后端用 code + code_verifier 换取 access_token
5. 查询 Provider 用户资料，匹配或创建本地账户
6. 若 Provider 邮箱已关联本地账户 → 提示账号关联
7. 签发 NSCA JWT Token，返回前端
```

**Logto OIDC 集成**：在 yudao JustAuth 之外新增 Spring Security OAuth2 Client 注册，配置 Logto 为 OIDC Provider：

```yaml
spring:
  security:
    oauth2:
      client:
        registration:
          logto:
            client-id: ${LOGTO_CLIENT_ID}
            client-secret: ${LOGTO_CLIENT_SECRET}
            authorization-grant-type: authorization_code
            redirect-uri: "{baseUrl}/login/oauth2/code/logto"
            scope: openid, profile, email
        provider:
          logto:
            issuer-uri: ${LOGTO_ISSUER_URI}
```

## 3.7 密码安全

> **扩展点**：提升 yudao `SecurityProperties.passwordEncoderLength` 从默认 4 → 12。

| 安全措施 | yudao 现状 | NSCA 扩展 |
|---------|----------|----------|
| **哈希算法** | BCrypt (cost=4 默认) | BCrypt (cost=12，约 250ms/次) |
| **密码策略** | 无强制复杂度 | 最小 12 位，含大小写+数字+符号 |
| **历史密码** | 无 | 禁止复用最近 5 次密码（新增 `system_user_password_history` 表） |
| **暴力破解防护** | 无 | 同一账户 5 次失败锁定 15 分钟；同一 IP 10 次失败要求 CAPTCHA |
| **密码泄露检测** | 无 | 检查 Have I Been Pwned API（k-anonymity 模型，仅发送 hash 前缀） |
| **密码找回** | 短信验证码重置 | 基于邮箱的限时重置链接（30 分钟），使用后立即失效 |

**BCrypt cost 升级实现**：修改 yudao 配置 `yudao.security.passwordEncoderLength=12` 即可生效，`YudaoSecurityAutoConfiguration` 的 `passwordEncoder()` Bean 会读取该配置。已有的低 cost hash 在用户下次登录成功后自动重新哈希。

## 3.8 会话管理

| 场景 | 会话策略 |
|------|----------|
| Web 浏览器 | Access Token 存内存（JS 变量），Refresh Token 存 httpOnly Cookie |
| 桌面客户端 | Access + Refresh 均存系统密钥链（Keychain / Windows Credential） |
| SDK/API | API Key 或 PAT，请求头 `Authorization: ApiKey <key>` |
| 多设备登录 | 默认允许，用户可在设置中查看活跃会话并撤销 |

**会话审计**（扩展 yudao `system_login_log` 表）：
- 每个 Token 签发记录：设备指纹、IP、地理位置、时间
- 用户可查看 "活跃会话" 列表，远程撤销可疑会话
- 检测到异常（新国家、新设备）发送安全告警邮件

**yudao 登出流程扩展**：

```
原有：yudao logout → 删除 MySQL/Redis 中的 accessToken + refreshToken
扩展：NSCA logout → 上述 + 将 JWT jti 加入 Redis 黑名单 (TTL = exp - now)
```

## 3.9 API Key 管理

> **新增能力**：yudao 不提供 API Key 管理。NSCA 新增 `system_api_key` 表 + Service。

```
POST /api/v1/auth/api-keys
→ 生成 key_id + api_key (仅返回一次)
→ 存储 HMAC-SHA256 哈希 (key_id 明文，api_key 仅存 hash)
→ API 请求: Authorization: ApiKey <key_id>:<signature>
  签名 = HMAC-SHA256(key_secret, method + path + timestamp + body)
```

### API Key 数据模型

```sql
-- NSCA 新增表（不影响 yudao system_users 表）
CREATE TABLE system_api_key (
    id          BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id     BIGINT NOT NULL COMMENT '关联 yudao system_users.id',
    name        VARCHAR(100) NOT NULL COMMENT '密钥名称',
    key_id      VARCHAR(32) NOT NULL UNIQUE COMMENT '密钥 ID（明文）',
    key_hash    VARCHAR(255) NOT NULL COMMENT '密钥哈希（HMAC-SHA256）',
    scope       VARCHAR(500) COMMENT '权限范围（逗号分隔）',
    last_used_at DATETIME COMMENT '最后使用时间',
    expires_at  DATETIME COMMENT '过期时间（NULL = 永不过期）',
    status      TINYINT DEFAULT 1 COMMENT '1=active 0=revoked',
    created_at  DATETIME NOT NULL,
    FOREIGN KEY (user_id) REFERENCES system_users(id)
);
```

## 3.10 接口契约

> 以下接口均为 NSCA 扩展端点，挂载在 yudao-module-system 的 Controller 中。yudao 原有端点（`/system/auth/login` 等）继续可用。

```yaml
# POST /api/v1/auth/register (NSCA 扩展)
request:
  email: string
  password: string          # ≥12位，满足复杂度
  display_name: string      # 2-30字符
  invitation_code: string?  # 可选邀请码

response_201:
  user_id: string
  email: string
  verification_sent: true

# POST /api/v1/auth/verify-email (NSCA 扩展)
request:
  email: string
  code: string              # 6位数字

response_200:
  access_token: string      # JWT
  refresh_token: string
  expires_in: 900
  user: UserProfile

# POST /api/v1/auth/login (复用 yudao 端点，扩展返回 JWT)
request:
  email: string
  password: string
  remember_me: boolean      # true → Refresh Token 30 天

response_200:
  access_token: string      # JWT
  refresh_token: string
  expires_in: 900
  user: UserProfile

# POST /api/v1/auth/refresh (NSCA 扩展)
response_200:
  access_token: string
  refresh_token: string     # 新轮换的 Token
  expires_in: 900

# POST /api/v1/auth/logout (复用 yudao 端点，扩展 JWT 黑名单)
response_204: {}

# POST /api/v1/auth/forgot-password (NSCA 扩展)
request:
  email: string
response_200:
  message: "如果该邮箱存在，重置链接已发送"

# POST /api/v1/auth/reset-password (NSCA 扩展)
request:
  token: string             # 重置链接中的 JWT
  new_password: string

# POST /api/v1/auth/oauth/github (复用 yudao JustAuth)
# POST /api/v1/auth/oauth/google (复用 yudao JustAuth)
# POST /api/v1/auth/oauth/logto (NSCA 新增 OIDC)
request:
  code: string
  code_verifier: string     # PKCE
  redirect_uri: string

response_200:
  access_token: string      # JWT
  refresh_token: string
  is_new_user: boolean
  user: UserProfile

# POST /api/v1/auth/api-keys (NSCA 新增)
request:
  name: string
  scope: string[]           # 权限范围子集
  expires_days: int?        # null = 永不过期

response_201:
  key_id: string
  api_key: string           # 仅返回一次，格式: nsca_live_xxx

# GET /api/v1/auth/me (复用 yudao 端点)
response_200:
  user_id: string
  email: string
  display_name: string
  avatar_url: string?
  email_verified: boolean
  membership_tier: string   # free | pro | team | enterprise
  mfa_enabled: boolean
  has_password: boolean     # OAuth-only 用户可能无密码

# POST /api/v1/auth/mfa/setup (NSCA 新增)
response_200:
  secret: string
  qr_code_url: string
  backup_codes: string[]    # 仅返回一次

# POST /api/v1/auth/mfa/verify (NSCA 新增)
request:
  code: string              # 6位 TOTP

response_200:
  access_token: string      # MFA 完成后的完整 JWT
  refresh_token: string
```

## 3.11 yudao 扩展映射

| yudao 原有 | 方式 | NSCA 扩展 |
|-----------|------|----------|
| `system_users` 表 | 新增字段 | `mfa_secret`（加密）, `password_updated_at`, `login_failures`, `locked_until` |
| `system_oauth2_access_token` 表 | 保留兼容 + 新增 JWT 签发 | JWT RS256 令牌，网关离线验签 |
| `system_oauth2_refresh_token` 表 | 扩展 | `family_id`（家族检测）, `device_fingerprint` |
| `system_login_log` 表 | 扩展 | 新增设备指纹、地理位置字段 |
| `AdminAuthServiceImpl` | 扩展 | `login()` 返回 JWT；新增 `register()` 邮箱验证 |
| `OAuth2TokenServiceImpl` | 扩展 | `createAccessToken()` 支持 JWT 格式 |
| `TokenAuthenticationFilter` | 扩展 | 网关新增前置 `JwtAuthFilter` |
| `BCryptPasswordEncoder` | 配置提升 | `yudao.security.passwordEncoderLength=12` |
| JustAuth 社交登录 | 复用 + 新增 | 新增 Logto OIDC Provider |
| — | **新增表** | `system_api_key`, `system_user_password_history`, `system_user_mfa` |
| — | **新增 Service** | `ApiKeyService`, `TotpService`, `JwtTokenService` |

## 3.12 安全告警触发条件

| 条件 | 响应 |
|------|------|
| 短时间多国家 IP 登录 | 锁定账户，发送验证邮件 |
| Refresh Token 复用（家族检测） | 撤销整个 Token 家族，强制全设备重新登录 |
| 异常高频 API 调用 | 触发速率限制（复用 yudao Sentinel） |
| 密码出现在泄露数据库 | 登录时强制密码重置 |
| 新设备首次登录 | 发送邮件通知，用户可一键撤销 |
| 同一账户 5 次登录失败 | 锁定 15 分钟（Redis 计数器） |
| API Key 异常使用模式 | 自动撤销 + 邮件告警 |

---

## 参考

- [yudao 权限认证文档](https://doc.iocoder.cn/ruoyi-vue-pro/auth/)
- [Spring Security OAuth2 Resource Server](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/index.html)
- [JustAuth 文档](https://justauth.wiki/)
- [Logto OIDC 集成文档](https://docs.logto.io/docs/recipes/integrate-with-spring-boot/)
- [JWT Best Practices (IETF RFC 8725)](https://datatracker.ietf.org/doc/html/rfc8725)
