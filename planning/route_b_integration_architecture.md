# Route B: SaaS 集成架构

> Spring Cloud Alibaba 微服务套件作为企业级外骨骼，通过网关与业务服务集成。外骨骼是独立项目，与核心业务在不同目录中完全并行开发。

## 目录

1. [架构概览：外骨骼模式](#1-架构概览外骨骼模式)
2. [项目边界：外骨骼 vs 核心业务](#2-项目边界外骨骼-vs-核心业务)
3. [Spring Cloud Alibaba 技术栈能力匹配](#3-spring-cloud-alibaba-技术栈能力匹配)
4. [外骨骼微服务详解](#4-外骨骼微服务详解)
   - 4.1 [认证服务（Spring Security + Logto OIDC）](#41-认证服务spring-security--logto-oidc)
   - 4.2 [租户服务（MyBatis-Plus 行级隔离）](#42-租户服务mybatis-plus-行级隔离)
   - 4.3 [支付服务（Stripe Java SDK + Jeepay）](#43-支付服务stripe-java-sdk--jeepay)
   - 4.4 [订阅与 RP 计费服务](#44-订阅与-rp-计费服务)
   - 4.5 [API 网关（Spring Cloud Gateway + Sentinel）](#45-api-网关spring-cloud-gateway--sentinel)
   - 4.6 [管理控制台服务](#46-管理控制台服务)
   - 4.7 [定时任务服务（XXL-JOB）](#47-定时任务服务xxl-job)
5. [网关集成协议：外骨骼 → 业务服务](#5-网关集成协议外骨骼--业务服务)
6. [数据库模式（完整 DDL）](#6-数据库模式完整-ddl)
7. [部署架构](#7-部署架构)
8. [关键设计决策](#8-关键设计决策)

---

## 1. 架构概览：外骨骼模式

```
                              ┌──────────────────────────────┐
                              │       终端用户 / API 客户端      │
                              └──────────────┬───────────────┘
                                             │
                              ┌──────────────┴───────────────┐
                              │     Spring Cloud Gateway      │  ← 唯一入口
                              │  (JWT校验 / 限流 / 路由 / 熔断)  │
                              └──────┬───────────────┬───────┘
                                     │               │
              ┌──────────────────────┘               └──────────────────────┐
              │  /api/v1/auth/**    /api/v1/billing/**                      │  /api/v1/compute/**
              │  /api/v1/admin/**   /api/v1/webhooks/**                     │  /api/v1/agent/**
              │  /api/v1/api-keys/**                                        │
              ▼                                                             ▼
┌─────────────────────────────────────────┐    ┌──────────────────────────────┐
│         外骨骼系统 (exoskeleton/)         │    │      核心业务系统 (services/)    │
│       Spring Cloud Alibaba 微服务         │    │    任意语言 / 任意框架          │
│                                         │    │                              │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐  │    │  ┌────────────────────────┐  │
│  │ 认证服务  │ │ 租户服务  │ │ 支付服务 │  │    │  │  NSCA 计算引擎 (Python) │  │
│  │ Spring   │ │MyBatis-  │ │Stripe   │  │    │  │  FastAPI + NumPy        │  │
│  │ Security │ │Plus      │ │+ Jeepay │  │    │  │  /internal/compute/**   │  │
│  │ + Logto  │ │租户拦截器 │ │@Transact│  │    │  └────────────────────────┘  │
│  └──────────┘ └──────────┘ └─────────┘  │    │                              │
│                                         │    │  ┌────────────────────────┐  │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐  │    │  │  未来业务服务 (Go/Rust/…) │  │
│  │ 管理API  │ │ 调度服务  │ │ 审计服务 │  │    │  │  /internal/xxx/**       │  │
│  │REST API  │ │ XXL-JOB  │ │Spring   │  │    │  └────────────────────────┘  │
│  │          │ │          │ │AOP      │  │    │                              │
│  └──────────┘ └──────────┘ └─────────┘  │    │                              │
│                                         │    │                              │
│  ┌──────────────────────────────────┐   │    │                              │
│  │  基础设施                          │   │    │                              │
│  │  Nacos (注册+配置) | Sentinel     │   │    │                              │
│  │  SkyWalking (追踪) | Prometheus   │   │    │                              │
│  └──────────────────────────────────┘   │    │                              │
│                                         │    │                              │
│  PostgreSQL │ Redis                     │    │  (使用外骨骼的 PostgreSQL)      │
└─────────────────────────────────────────┘    └──────────────────────────────┘
```

**核心原则**：

- **外骨骼不感知业务**：不知道 NSCA 是做什么的，不知道输入/输出格式
- **业务不处理企业逻辑**：不知道用户密码、租户隔离、余额扣除、支付回调
- **网关是唯一的集成面**：外骨骼与业务之间只有这一条通道
- **两个独立项目，零代码耦合**：各自有独立的 CI/CD、独立的目录、独立的版本号

---

## 2. 项目边界：外骨骼 vs 核心业务

```
NSCA/
├── exoskeleton/                          ← 外骨骼系统（本项目 — 全新独立项目）
│   ├── pom.xml                           ← Maven 多模块父 POM
│   ├── exoskeleton-gateway/              ← API 网关模块
│   ├── exoskeleton-auth/                 ← 认证服务模块
│   ├── exoskeleton-tenant/               ← 租户服务模块
│   ├── exoskeleton-billing/              ← 计费服务模块
│   ├── exoskeleton-admin/                ← 管理 API 模块
│   ├── exoskeleton-scheduler/            ← 定时任务模块 (XXL-JOB)
│   ├── exoskeleton-common/               ← 公共模块 (DTO / 工具类 / 异常)
│   └── docker-compose.yml                ← 外骨骼基础设施
│
├── services/                             ← 核心业务系统（不修改！仅定义集成协议）
│   └── nsca-compute/                     ← NSCA 计算引擎 (Python) — 现有代码不改
│       ├── main.py                       ← FastAPI 入口
│       └── nsca/
│           └── engine.py                 ← 核心计算逻辑
│
├── web/                                  ← 用户 Web 应用 (Next.js) — 现有代码不改
├── admin/                                ← 管理控制台 (Refine + Ant Design)
├── docs/                                 ← 文档 — 本文件所在位置
└── experiments/                          ← NSCA 实验 — 绝不修改
```

> **红线**：`services/`、`experiments/`、`web/` 下的任何代码都不会被外骨骼项目触碰。外骨骼只通过网关 HTTP Header 向业务服务传递已验证的上下文。

---

## 3. Spring Cloud Alibaba 技术栈能力匹配

每一项外骨骼能力与 Spring 微服务生态的精确匹配：

| 能力需求 | 选型 | 版本 | 选型理由 |
|---------|------|------|---------|
| **服务注册 + 配置中心** | Nacos | 2.4.x | 注册+配置二合一，支持 CP/AP 切换，国内生态最强 |
| **API 网关** | Spring Cloud Gateway | 2025.x | 响应式非阻塞，Spring 原生，与 Sentinel 无缝集成 |
| **限流 / 熔断 / 降级** | Sentinel | 1.8.x | 比 Hystrix 更丰富，实时 Dashboard，动态规则推送 |
| **认证** | Spring Security 6 + OAuth2 Resource Server | 6.x | 框架级安全防护，非手写中间件 |
| **外部 OIDC 提供方** | Logto | latest | 开源 OIDC，内置多租户，管理 UI 开箱即用 |
| **ORM + 多租户** | MyBatis-Plus + TenantLineInnerInterceptor | 3.5.x | 租户拦截器自动注入 WHERE 条件，零遗漏 |
| **Stripe 支付 (国际)** | stripe-java | 32.x | 官方 SDK，852 个 Release，Webhook 签名校验内置 |
| **中国支付 (支付宝/微信)** | Jeepay | 3.x | 6.1k stars，Spring Boot 3.x 原生，生产就绪 |
| **分布式调度** | XXL-JOB | 2.4.x | 分布式任务分片，失败重试，Dashboard 可视化管理 |
| **分布式追踪** | SkyWalking | 10.x | 线程级追踪，无侵入 agent，与 Spring Cloud Gateway 集成 |
| **数据库迁移** | Flyway | 10.x | 比 Liquibase 更轻，Spring Boot 内置 |
| **监控** | Spring Boot Actuator + Prometheus + Grafana | — | 业界标准，生态完备 |
| **分布式事务 (预留)** | Seata | 2.x | AT/TCC 模式，仅跨服务 RP 扣除场景按需启用 |

### 为什么选 Spring Cloud Alibaba 而非 Spring Cloud Netflix？

| 对比维度 | Netflix 栈 | Alibaba 栈 |
|---------|-----------|-----------|
| 服务注册 | Eureka 2.x (停更) | Nacos 2.4.x (活跃) |
| 配置中心 | Spring Cloud Config + Bus | Nacos Config (实时推送，无需 Bus) |
| 限流熔断 | Hystrix (停更) | Sentinel (实时 Dashboard + 动态规则) |
| Spring Boot 3.x 兼容 | 生态分裂 | **完全兼容** |
| 中文社区 | 薄弱 | **极强** (中文文档、钉钉群、RuoYi 生态) |

### 为什么选 MyBatis-Plus 而非纯 JPA/Hibernate？

| 对比维度 | Hibernate / JPA | MyBatis-Plus |
|---------|----------------|-------------|
| 多租户 | Hibernate Filter (需手写配置) | TenantLineInnerInterceptor (开箱即用) |
| 中国数据库兼容 (TiDB/OceanBase) | 方言兼容不稳定 | 多数项目直接使用，已有验证 |
| 复杂查询 (报表/聚合) | JPQL/HQL 局限 | 原生 SQL + 动态条件构造器 |
| 国内生态 (RuoYi/Jeepay) | 少 | **事实标准**，已有大量参考实现 |

---

## 4. 外骨骼微服务详解

### 4.1 认证服务（Spring Security + Logto OIDC）

#### 4.1.1 认证架构

```
用户 → Logto 登录页 → 输入凭证 → Logto 签发 JWT
                                       │
          ┌────────────────────────────┘
          ▼
  每次 API 请求携带 Authorization: Bearer <jwt>
          │
          ▼
   Spring Cloud Gateway
   ┌─────────────────────────┐
   │ AuthGlobalFilter        │  ← 校验 JWT 签名/过期/issuer
   │ 提取 tenant_id, role    │  ← 从 JWT claims
   │ 注入 X-Tenant-Id header │  ← 向下游服务传递
   └─────────┬───────────────┘
             │
    ┌────────┴────────┐
    ▼                 ▼
   外骨骼服务         业务服务
   (从 SecurityContext  (从 X-Tenant-Id header
   读取 AuthContext)    读取租户上下文)
```

#### 4.1.2 Logto JWT 声明结构

```json
{
  "sub": "logto_user_uuid",
  "email": "user@example.com",
  "tenant_id": "tenant_uuid",
  "role": "user",
  "scope": "read write",
  "iss": "https://auth.nsca.example.com/oidc",
  "exp": 1715000000,
  "iat": 1714990000
}
```

`tenant_id` 由 Logto 自定义声明注入，是整个外骨骼多租户隔离的信任根。

#### 4.1.3 Spring Security 配置

```java
// exoskeleton-auth/src/main/java/com/nsca/exoskeleton/auth/SecurityConfig.java

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/v1/webhooks/stripe").permitAll()
                .requestMatchers("/api/v1/webhooks/jeepay").permitAll()
                .requestMatchers("/api/v1/admin/**").hasAnyRole("admin", "super_admin")
                .requestMatchers("/api/v1/compute/**").authenticated()
                .requestMatchers("/internal/**").authenticated()
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(jwtConverter()))
            )
            .sessionManagement(session ->
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS)
            )
            .csrf(AbstractHttpConfigurer::disable);
        return http.build();
    }

    @Bean
    public JwtAuthenticationConverter jwtConverter() {
        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(jwt -> {
            String role = jwt.getClaimAsString("role");
            if (role == null) return List.of();
            return List.of(new SimpleGrantedAuthority("ROLE_" + role.toUpperCase()));
        });
        return converter;
    }
}
```

#### 4.1.4 认证上下文（所有微服务共享）

```java
// exoskeleton-common/src/main/java/com/nsca/exoskeleton/common/auth/AuthContext.java

public record AuthContext(
    String userId,      // sub — Logto 用户 UUID
    String tenantId,    // tenant_id — 租户 UUID
    String role,        // user | admin | super_admin
    String email,
    boolean isApiKey,  // API Key 认证时为 true
    List<String> scopes
) {
    public static AuthContext fromJwt(Jwt jwt) {
        return new AuthContext(
            jwt.getSubject(),
            jwt.getClaimAsString("tenant_id"),
            jwt.getClaimAsString("role"),
            jwt.getClaimAsString("email"),
            false,
            List.of()
        );
    }
}
```

#### 4.1.5 API 密钥认证

API 密钥用于 CLI/SDK 等程序化访问，与 JWT 互为补充：

```java
// exoskeleton-gateway/src/main/java/com/nsca/exoskeleton/gateway/filter/ApiKeyFilter.java

@Component
public class ApiKeyAuthGatewayFilter implements GlobalFilter, Ordered {

    private final ApiKeyRepository apiKeyRepository;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String apiKey = exchange.getRequest().getHeaders().getFirst("X-API-Key");
        if (apiKey == null) return chain.filter(exchange);

        // bcrypt 哈希比对
        ApiKeyRecord record = apiKeyRepository.findByHash(apiKey);
        if (record == null || record.isRevoked()) {
            exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
            return exchange.getResponse().setComplete();
        }

        // 更新最后使用时间（异步）
        apiKeyRepository.updateLastUsed(record.getId());

        // 注入认证上下文到 Header
        exchange.getRequest().mutate()
            .header("X-User-Id", record.getUserId())
            .header("X-Tenant-Id", record.getTenantId())
            .header("X-Auth-Method", "api_key");

        return chain.filter(exchange);
    }

    @Override
    public int getOrder() { return -1; } // 最先执行
}
```

#### 4.1.6 用户 JIT 预创建

不与 Logto 维护同步服务——用户在首次 API 请求时自动创建：

```java
// exoskeleton-tenant/src/main/java/com/nsca/exoskeleton/tenant/UserSyncService.java

@Service
public class UserSyncService {

    @Transactional
    public User ensureUserExists(AuthContext ctx) {
        return userRepository.findById(ctx.userId())
            .orElseGet(() -> {
                User user = new User();
                user.setId(ctx.userId());
                user.setTenantId(ctx.tenantId());
                user.setEmail(ctx.email());
                user.setRpBalance(BigDecimal.ZERO);
                user.setDefaultCurrency("cny");
                return userRepository.save(user);
            });
    }
}
```

---

### 4.2 租户服务（MyBatis-Plus 行级隔离）

#### 4.2.1 MyBatis-Plus 租户拦截器

```java
// exoskeleton-tenant/src/main/java/com/nsca/exoskeleton/tenant/config/TenantConfig.java

@Configuration
public class MyBatisPlusTenantConfig {

    @Bean
    public MybatisPlusInterceptor mybatisPlusInterceptor() {
        MybatisPlusInterceptor interceptor = new MybatisPlusInterceptor();
        interceptor.addInnerInterceptor(new TenantLineInnerInterceptor(
            new TenantLineHandler() {
                @Override
                public Expression getTenantId() {
                    AuthContext ctx = AuthContextHolder.get();
                    if (ctx == null) return new NullValue();
                    return new StringValue(ctx.tenantId());
                }

                @Override
                public String getTenantIdColumn() {
                    return "tenant_id";
                }

                @Override
                public boolean ignoreTable(String tableName) {
                    return Set.of("plans", "webhook_events").contains(tableName);
                }
            }
        ));
        return interceptor;
    }
}
```

**效果**：所有 MyBatis-Plus 查询自动追加 `WHERE tenant_id = ?`，开发者无需手动处理。

#### 4.2.2 租户上下文传递（通过 ThreadLocal）

```java
// exoskeleton-common/src/main/java/com/nsca/exoskeleton/common/auth/AuthContextHolder.java

public class AuthContextHolder {
    private static final ThreadLocal<AuthContext> HOLDER = new ThreadLocal<>();

    public static void set(AuthContext ctx) { HOLDER.set(ctx); }
    public static AuthContext get() { return HOLDER.get(); }
    public static void clear() { HOLDER.remove(); }
}
```

Gateway Filter 在请求进入时设置，在响应返回时清除。

#### 4.2.3 租户隔离的多层防护

| 防护层 | 机制 | 失败后果 |
|--------|------|---------|
| Gateway | JWT/API Key 中提取 tenant_id，不可伪造 | 请求被拒 (401) |
| Interceptor | MyBatis-Plus 自动注入 WHERE tenant_id | 零行返回或 SQL 报错 |
| Repository | 所有 DAO 查询经过拦截器 | 不可绕过 |
| Audit | 每条操作记录绑定 tenant_id | 事后可追溯 |
| Admin RBAC | tenant_admin 只能操作自己租户的数据 | 越权被拒 (403) |

#### 4.2.4 租户入驻流程

```
super_admin 调用 POST /api/v1/admin/tenants
    { "name": "Acme Corp", "slug": "acme-corp", "adminEmail": "admin@acme.com" }
         │
         ▼
TenantProvisioningService.createTenant()
    ├── 1. INSERT INTO tenants → 获得 tenant_id
    ├── 2. INSERT INTO tenant_configs (默认配额)
    ├── 3. 调用 Logto Admin API → 创建 Logto 租户
    ├── 4. 调用 Logto Admin API → 创建首个管理员用户 (role=admin, custom_data.tenant_id=xxx)
    └── 5. Logto 发送邀请邮件 → 管理员设置密码 → 登录管理控制台
```

---

### 4.3 支付服务（Stripe Java SDK + Jeepay）

#### 4.3.1 统一支付抽象

```java
// exoskeleton-billing/src/main/java/com/nsca/exoskeleton/billing/payment/PaymentService.java

public interface PaymentService {

    /** 创建一次性支付（RP 购买） */
    PaymentResult createPaymentIntent(PaymentRequest request);

    /** 创建定期订阅 */
    SubscriptionResult createSubscription(SubscriptionRequest request);

    /** 取消订阅 */
    boolean cancelSubscription(String subscriptionExternalId);

    /** 构造并校验 Webhook 事件 */
    WebhookEvent constructEvent(String payload, String signature);
}

public record PaymentRequest(
    String userId, String tenantId,
    long amountCents, String currency,
    String paymentMethod,         // card | alipay | wechat_pay
    String idempotencyKey,
    Map<String, String> metadata
) {}

public record PaymentResult(
    boolean success,
    String paymentIntentId,
    String clientSecret,         // 前端完成 3DS 认证
    String redirectUrl,          // 支付宝/微信跳转 URL
    String errorMessage
) {}
```

#### 4.3.2 Stripe 实现

```java
// exoskeleton-billing/src/main/java/com/nsca/exoskeleton/billing/payment/StripePaymentService.java

@Service
@ConditionalOnProperty(name = "payment.provider", havingValue = "stripe")
public class StripePaymentService implements PaymentService {

    @Value("${stripe.api-key}")
    private String apiKey;

    @PostConstruct
    public void init() {
        Stripe.apiKey = apiKey;
    }

    @Override
    public PaymentResult createPaymentIntent(PaymentRequest req) {
        var params = PaymentIntentCreateParams.builder()
            .setAmount(req.amountCents())
            .setCurrency(req.currency())
            .addPaymentMethodType(req.paymentMethod())
            .putMetadata("user_id", req.userId())
            .putMetadata("tenant_id", req.tenantId())
            .putMetadata("charge_type", "rp_purchase")
            .setIdempotencyKey(req.idempotencyKey())
            .build();

        try {
            PaymentIntent intent = PaymentIntent.create(params);
            return new PaymentResult(
                true, intent.getId(), intent.getClientSecret(),
                intent.getNextAction() != null
                    ? intent.getNextAction().getRedirectToUrl().getUrl()
                    : null,
                null
            );
        } catch (StripeException e) {
            return new PaymentResult(false, null, null, null, e.getMessage());
        }
    }

    @Override
    public SubscriptionResult createSubscription(SubscriptionRequest req) {
        // 附加支付方式 → 设为默认 → 创建订阅
        var attachParams = PaymentMethodAttachParams.builder()
            .setCustomer(req.userId()).build();
        PaymentMethod.attach(req.paymentMethodId(), attachParams);

        var customerParams = CustomerUpdateParams.builder()
            .setInvoiceSettings(CustomerUpdateParams.InvoiceSettings.builder()
                .setDefaultPaymentMethod(req.paymentMethodId()).build())
            .build();
        Customer.update(req.userId(), customerParams);

        var subParams = SubscriptionCreateParams.builder()
            .setCustomer(req.userId())
            .addItem(SubscriptionCreateParams.Item.builder()
                .setPrice(req.stripePriceId()).build())
            .putMetadata("user_id", req.userId())
            .putMetadata("tenant_id", req.tenantId())
            .setPaymentBehavior(SubscriptionCreateParams.PaymentBehavior.DEFAULT_INCOMPLETE)
            .addExpand("latest_invoice.payment_intent")
            .build();

        try {
            Subscription sub = Subscription.create(subParams);
            String clientSecret = sub.getLatestInvoice() != null
                && sub.getLatestInvoice().getPaymentIntent() != null
                ? sub.getLatestInvoice().getPaymentIntent().getClientSecret()
                : null;
            return new SubscriptionResult(true, sub.getId(), clientSecret, null);
        } catch (StripeException e) {
            return new SubscriptionResult(false, null, null, e.getMessage());
        }
    }

    @Override
    public WebhookEvent constructEvent(String payload, String signature) {
        return WebhookUtil.constructEvent(
            payload, signature, webhookSecret
        );
    }
}
```

#### 4.3.3 Jeepay 实现（中国支付）

```java
// exoskeleton-billing/src/main/java/com/nsca/exoskeleton/billing/payment/JeepayPaymentService.java

@Service
@ConditionalOnProperty(name = "payment.provider", havingValue = "jeepay")
public class JeepayPaymentService implements PaymentService {

    @Override
    public PaymentResult createPaymentIntent(PaymentRequest req) {
        PayOrderCreateRequest jeepayReq = new PayOrderCreateRequest();
        jeepayReq.setMchNo(jeepayConfig.getMchNo());
        jeepayReq.setAppId(jeepayConfig.getAppId());
        jeepayReq.setMchOrderNo(req.idempotencyKey());
        jeepayReq.setWayCode(mapWayCode(req.paymentMethod())); // ALIPAY_WAP / WX_H5
        jeepayReq.setAmount(req.amountCents());
        jeepayReq.setCurrency("cny");
        jeepayReq.setSubject("NSCA RP 充值");
        jeepayReq.setNotifyUrl(jeepayConfig.getNotifyUrl());

        PayOrderCreateResponse resp = jeepayClient.createOrder(jeepayReq);
        return new PaymentResult(true, resp.getPayOrderId(), null, resp.getPayUrl(), null);
    }
}
```

#### 4.3.4 支付策略路由

```
用户发起 RP 购买 (POST /api/v1/billing/purchase-rp)
              │
              ▼
    BillingController
              │
              ▼
    PaymentRouter.choose(paymentMethod, currency)
              │
    ┌─────────┼─────────┐
    ▼         ▼         ▼
  Stripe   Stripe    Jeepay
  (card)   (alipay)  (alipay/wechat)
  USD/CNY  CNY       CNY
```

```java
// exoskeleton-billing/src/main/java/com/nsca/exoskeleton/billing/payment/PaymentRouter.java

@Component
public class PaymentRouter {

    private final StripePaymentService stripePaymentService;
    private final JeepayPaymentService jeepayPaymentService;

    public PaymentService route(PaymentMethod method, String currency) {
        return switch (method) {
            case CARD -> stripePaymentService;
            case ALIPAY, WECHAT_PAY -> {
                if ("cny".equalsIgnoreCase(currency)) yield jeepayPaymentService;
                yield stripePaymentService;  // 海外支付宝
            }
        };
    }
}
```

#### 4.3.5 Webhook 处理

```java
// exoskeleton-billing/src/main/java/com/nsca/exoskeleton/billing/webhook/WebhookController.java

@RestController
@RequestMapping("/api/v1/webhooks")
public class WebhookController {

    @PostMapping("/stripe")
    @Transactional
    public ResponseEntity<Map<String, String>> stripeWebhook(
            @RequestBody String payload,
            @RequestHeader("Stripe-Signature") String signature) {

        WebhookEvent event = stripePaymentService.constructEvent(payload, signature);

        // 幂等性
        if (webhookEventRepository.existsByEventId(event.getId())) {
            return ResponseEntity.ok(Map.of("status", "already_processed"));
        }

        webhookEventRepository.save(WebhookEventEntity.from(event));
        stripeEventHandler.dispatch(event);
        return ResponseEntity.ok(Map.of("status", "ok"));
    }

    @PostMapping("/jeepay")
    @Transactional
    public ResponseEntity<Map<String, String>> jeepayNotify(@RequestBody String payload) {
        // Jeepay 回调处理 — 验签 → 幂等 → 更新状态 → 发放 RP
        jeepayEventHandler.handle(payload);
        return ResponseEntity.ok(Map.of("status", "ok"));
    }
}
```

---

### 4.4 订阅与 RP 计费服务

#### 4.4.1 RP 余额扣除（@Transactional 原子操作）

```java
// exoskeleton-billing/src/main/java/com/nsca/exoskeleton/billing/rp/RPService.java

@Service
public class RPService {

    @Transactional
    public void deduct(String userId, String tenantId, BigDecimal amount, String description) {
        User user = userRepository.findById(userId)
            .orElseThrow(() -> new UserNotFoundException(userId));

        if (user.getRpBalance().compareTo(amount) < 0) {
            throw new InsufficientRPException(amount, user.getRpBalance());
        }

        user.setRpBalance(user.getRpBalance().subtract(amount));
        userRepository.save(user);

        rpTransactionRepository.save(RPTransaction.builder()
            .userId(userId).tenantId(tenantId)
            .amount(amount.negate()).type("consumption")
            .description(description).build()
        );
    }
}
```

#### 4.4.2 RP 消费网关过滤器

```java
// exoskeleton-gateway/src/main/java/com/nsca/exoskeleton/gateway/filter/RPConsumptionFilter.java

@Component
public class RPConsumptionFilter implements GlobalFilter, Ordered {

    // 端点 → 每次调用的 RP 成本
    private static final Map<String, Integer> RP_COST = Map.of(
        "/api/v1/compute/causal-discovery", 10,
        "/api/v1/compute/batch-analysis", 50,
        "/api/v1/compute/advanced-simulation", 100
    );

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String path = exchange.getRequest().getURI().getPath();
        Integer cost = RP_COST.get(path);
        if (cost == null) return chain.filter(exchange);

        // 功能门控：某些套餐/租户配置允许无限计算
        String featureGate = exchange.getAttribute("feature_gate");
        if ("unlimited".equals(featureGate)) return chain.filter(exchange);

        AuthContext ctx = exchange.getAttribute("authContext");

        return Mono.fromCallable(() -> {
            rpService.deduct(ctx.userId(), ctx.tenantId(), BigDecimal.valueOf(cost),
                             "API调用: " + path);
            return true;
        }).onErrorMap(InsufficientRPException.class, e -> {
            exchange.getResponse().setStatusCode(HttpStatus.PAYMENT_REQUIRED);
            throw new ResponseStatusException(HttpStatus.PAYMENT_REQUIRED,
                String.format("RP 不足: 需要 %d，当前 %.2f", cost, e.getCurrent()));
        }).then(chain.filter(exchange));
    }

    @Override
    public int getOrder() { return 30; }
}
```

#### 4.4.3 功能门控过滤器

```java
// exoskeleton-gateway/src/main/java/com/nsca/exoskeleton/gateway/filter/FeatureGateFilter.java

@Component
public class FeatureGateFilter implements GlobalFilter, Ordered {

    // 端点模式 → 所需的 plans.features JSONB 键
    private static final Map<String, String> FEATURE_REQUIREMENTS = Map.of(
        "/api/v1/compute/advanced-simulation", "advanced_algorithms",
        "/api/v1/api-keys", "api_access",
        "/api/v1/data/export", "data_export"
    );

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String path = exchange.getRequest().getURI().getPath();
        String requiredFeature = FEATURE_REQUIREMENTS.get(path);
        if (requiredFeature == null) return chain.filter(exchange);

        AuthContext ctx = exchange.getAttribute("authContext");
        SubscriptionTier tier = subscriptionService.getCurrentTier(ctx.userId());

        if (!tier.features().getOrDefault(requiredFeature, false)) {
            exchange.getResponse().setStatusCode(HttpStatus.FORBIDDEN);
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                "功能 '" + requiredFeature + "' 需要升级套餐");
        }

        exchange.getAttributes().put("feature_gate", tier.features());
        return chain.filter(exchange);
    }

    @Override
    public int getOrder() { return 20; }
}
```

#### 4.4.4 RP 系统生命周期

```
┌────────────────────────────────────────────────────────────────┐
│                         RP 系统                                 │
│                                                                │
│  流入                         流出                              │
│  ┌──────────┐               ┌──────────┐                      │
│  │ Stripe   │──► purchase   │          │                      │
│  │ Jeepay   │──► purchase   │          │                      │
│  │ 月度配额  │──► grant      │ rp_balance                      │
│  │ 退款     │──► refund     │          │──► consumption ──► API调用│
│  └──────────┘               │          │──► expiration  ──► 过期 │
│                              └──────────┘                      │
│                                                                │
│  汇率: 1 CNY = 10 RP | 1 USD = 70 RP                           │
│  最低购买: 1,000 RP (¥100 / ~$14)                               │
│  所有变动记录在 rp_transactions 表，可审计                        │
└────────────────────────────────────────────────────────────────┘
```

#### 4.4.5 套餐种子数据

```sql
INSERT INTO plans (name, tier, price_monthly_cents, price_yearly_cents, rp_allowance, features, sort_order) VALUES
('Free', 'free', NULL, NULL, 100,
 '{"max_compute_minutes":60,"max_concurrent_jobs":1,"data_export":false,"api_access":true,"advanced_algorithms":false,"priority_support":false,"team_seats":1}',
 1),
('Pro', 'pro', 29900, 299000, 1000,
 '{"max_compute_minutes":600,"max_concurrent_jobs":3,"data_export":true,"api_access":true,"advanced_algorithms":true,"priority_support":false,"team_seats":1}',
 2),
('Team', 'team', 99900, 999000, 5000,
 '{"max_compute_minutes":3000,"max_concurrent_jobs":10,"data_export":true,"api_access":true,"advanced_algorithms":true,"priority_support":true,"team_seats":5}',
 3),
('Enterprise', 'enterprise', NULL, NULL, 50000,
 '{"max_compute_minutes":99999,"max_concurrent_jobs":50,"data_export":true,"api_access":true,"advanced_algorithms":true,"priority_support":true,"team_seats":999,"custom_branding":true}',
 4);
```

---

### 4.5 API 网关（Spring Cloud Gateway + Sentinel）

`★ Insight ─────────────────────────────────────`
网关是外骨骼与业务服务之间的**唯一接触面**。业务服务不需要知道 JWT 格式、租户隔离策略、收费规则。它只需要信任网关注入的 HTTP Header（X-Tenant-Id, X-User-Id），专注处理核心计算。
`─────────────────────────────────────────────────`

#### 4.5.1 路由配置

```yaml
# exoskeleton-gateway/src/main/resources/application.yml

spring:
  cloud:
    gateway:
      routes:
        # ============ 外骨骼内部路由 ============
        - id: auth-service
          uri: lb://exoskeleton-auth
          predicates: Path=/api/v1/auth/**
        - id: billing-service
          uri: lb://exoskeleton-billing
          predicates: Path=/api/v1/billing/**,/api/v1/webhooks/**
        - id: admin-service
          uri: lb://exoskeleton-admin
          predicates: Path=/api/v1/admin/**
        - id: api-key-service
          uri: lb://exoskeleton-auth
          predicates: Path=/api/v1/api-keys/**

        # ============ 业务服务路由（核心业务 — 不修改！） ============
        - id: nsca-compute
          uri: lb://nsca-compute-service
          predicates: Path=/api/v1/compute/**
          filters:
            - StripPrefix=0
            - name: CircuitBreaker
              args:
                name: computeBreaker
                fallbackUri: forward:/fallback/compute
            - name: RequestSize
              args:
                maxSize: 10MB

      default-filters:
        - RateLimit=60,60
        - RemoveRequestHeader=Cookie
        - RemoveRequestHeader=Origin
```

#### 4.5.2 全局过滤器执行顺序

```
客户端请求
    │
    ▼
[-1] ApiKeyAuthFilter       ← API 密钥认证（如有 X-API-Key header）
    │
    ▼
[0]  JwtAuthFilter          ← JWT 签名/过期/issuer 校验
    │                         提取 tenant_id, user_id, role → AuthContext
    ▼
[10] TenantHeaderFilter     ← 向下游注入 X-Tenant-Id, X-User-Id headers
    │
    ▼
[20] FeatureGateFilter      ← 检查订阅层级是否允许此端点
    │
    ▼
[30] RPConsumptionFilter    ← 计算端点扣除 RP
    │
    ▼
[40] RateLimitFilter        ← 租户级别滑动窗口限流 (Sentinel)
    │
    ▼
[50] RouteToTarget          ← 路由到外骨骼服务 或 业务服务
    │
    ▼
[99] AuditLogFilter         ← 异步记录审计日志
```

#### 4.5.3 Sentinel 限流与熔断配置

```yaml
# Nacos 动态配置 sentinel-rules.yaml

spring:
  cloud:
    sentinel:
      transport:
        dashboard: sentinel-dashboard:8080
      datasource:
        flow-rules:
          nacos:
            server-addr: nacos:8848
            group-id: EXOSKELETON
            data-id: sentinel-flow-rules

# Sentinel Dashboard 中配置的规则：
# ┌──────────────────┬─────────┬──────────┬───────┐
# │ 资源              │ 阈值     │ 限流模式  │ 效果   │
# ├──────────────────┼─────────┼──────────┼───────┤
# │ gateway-common   │ 1000    │ 每租户    │ 快速失败│
# │ compute-causal   │ 10      │ 每用户/min│ 排队等待│
# │ compute-batch    │ 5       │ 每用户/min│ 快速失败│
# │ admin-read       │ 100     │ 全局      │ 快速失败│
# └──────────────────┴─────────┴──────────┴───────┘
```

#### 4.5.4 断路器（Resilience4j — 业务服务保护）

```yaml
resilience4j:
  circuitbreaker:
    instances:
      computeBreaker:
        slidingWindowSize: 20
        failureRateThreshold: 50
        waitDurationInOpenState: 30s
        permittedNumberOfCallsInHalfOpenState: 5
        slowCallRateThreshold: 100
        slowCallDurationThreshold: 120s
  timelimiter:
    instances:
      computeTimeout:
        timeoutDuration: 120s  # AI 计算允许长超时
```

---

### 4.6 管理控制台服务

Refine + Ant Design 前端，后端由 Spring Boot Admin Controller 提供 REST API：

```java
// exoskeleton-admin/src/main/java/com/nsca/exoskeleton/admin/TenantAdminController.java

@RestController
@RequestMapping("/api/v1/admin")
@PreAuthorize("hasAnyRole('admin', 'super_admin')")
public class TenantAdminController {

    @GetMapping("/tenants")
    public PageResponse<TenantDTO> listTenants(
            @CurrentUser AuthContext ctx,
            @PageableDefault(size = 20) Pageable pageable) {

        Page<Tenant> page = tenantRepository.findAll(
            TenantSpecs.accessibleBy(ctx), pageable
        );
        return PageResponse.from(page.map(TenantDTO::from));
    }

    @PostMapping("/tenants")
    @PreAuthorize("hasRole('super_admin')")
    @Transactional
    public TenantDTO createTenant(@Valid @RequestBody CreateTenantRequest req) {
        return tenantProvisioningService.createTenant(
            req.name(), req.slug(), req.adminEmail()
        );
    }

    @GetMapping("/tenants/{id}")
    @PreAuthorize("hasRole('super_admin') or @tenantOwnershipValidator.isOwner(#id)")
    public TenantDTO getTenant(@PathVariable String id) {
        return TenantDTO.from(tenantRepository.findById(id)
            .orElseThrow(() -> new TenantNotFoundException(id)));
    }
}
```

---

### 4.7 定时任务服务（XXL-JOB）

```java
// exoskeleton-scheduler/src/main/java/com/nsca/exoskeleton/scheduler/RPJobs.java

@Component
public class RPJobs {

    /**
     * 月度 RP 配额发放 — 每月 1 日 00:00:00 执行
     * XXL-JOB cron: 0 0 0 1 * ?
     */
    @XxlJob("grantMonthlyRPAllowance")
    @Transactional
    public void grantMonthlyAllowance() {
        List<Subscription> activeSubs = subscriptionRepository
            .findByStatusAndPeriodStart("active", LocalDateTime.now());

        for (Subscription sub : activeSubs) {
            boolean alreadyGranted = rpTransactionRepository
                .existsGrantInPeriod(sub.getUserId(), sub.getCurrentPeriodStart());
            if (alreadyGranted) continue;

            Plan plan = planRepository.findById(sub.getPlanId()).orElseThrow();
            rpService.grant(sub.getUserId(), sub.getTenantId(),
                BigDecimal.valueOf(plan.getRpAllowance()), "月度配额");
        }
    }

    /**
     * RP 余额过期检查 — 每天 03:00:00 执行
     */
    @XxlJob("expireRPBalances")
    @Transactional
    public void expireBalances() {
        List<User> expired = userRepository.findExpiredRPBalances(LocalDateTime.now());
        for (User user : expired) {
            BigDecimal amount = user.getRpBalance();
            user.setRpBalance(BigDecimal.ZERO);
            user.setRpBalanceExpiresAt(null);
            userRepository.save(user);

            rpTransactionRepository.save(RPTransaction.builder()
                .userId(user.getId()).tenantId(user.getTenantId())
                .amount(amount.negate()).type("expiration")
                .description("RP 余额过期").build()
            );
        }
    }

    /**
     * Webhook 事件失败重试 — 每 5 分钟执行
     */
    @XxlJob("retryFailedWebhooks")
    public void retryFailedWebhooks() {
        webhookEventRepository.findUnprocessed(24, TimeUnit.HOURS)
            .forEach(event -> eventDispatcher.retry(event));
    }
}
```

---

## 5. 网关集成协议：外骨骼 → 业务服务

`★ Insight ─────────────────────────────────────`
这是整个架构中最核心的约定：外骨骼与业务服务之间的接口只由 HTTP Header 定义。没有共享代码、没有 SDK 依赖、没有数据库共享。换语言、换框架、换团队，都不影响对方。
`─────────────────────────────────────────────────`

### 5.1 外骨骼向业务服务注入的 Header

网关在完成所有校验（JWT/API Key、租户、功能门控、RP 扣除）后，向业务服务请求注入以下 Header：

```
X-User-Id:     logto_user_uuid
X-Tenant-Id:   tenant_uuid
X-Request-Id:  uuid-v4
X-Job-Id:      uuid-v4 (仅计算端点)
X-Features:    base64(json)  ← 当前套餐的功能集
X-Auth-Method: jwt | api_key
```

### 5.2 业务服务的责任（最小化）

```python
# services/nsca-compute/main.py
# 业务服务不需要导入任何外骨骼的代码，不需要知道 JWT 格式
# 它只需信任网关注入的 Header

from fastapi import FastAPI, Request, Header
import uuid

app = FastAPI()


@app.post("/api/v1/compute/causal-discovery")
async def causal_discovery(
    request: Request,
    x_tenant_id: str = Header(...),
    x_user_id: str = Header(...),
    x_job_id: str = Header(...),
):
    """
    业务服务责任：
    1. 信任 X-Tenant-Id 和 X-User-Id（外骨骼已验证）
    2. 执行核心计算
    3. 记录 tenant_id 到日志（用于审计追溯）
    4. 不处理认证、计费、租户隔离
    """
    body = await request.json()

    # 核心计算逻辑 — 与现有代码完全一致，不需要任何修改
    from nsca.engine import CausalDiscoveryEngine
    engine = CausalDiscoveryEngine(method=body.get("method", "pc"))
    result = engine.run(body["data"])

    return {
        "job_id": x_job_id,
        "tenant_id": x_tenant_id,
        "graph_edges": result.edges,
        "confidence_scores": result.scores,
    }
```

### 5.3 业务服务的硬性约定

| 规则 | 说明 |
|------|------|
| **不自行认证** | 信任 X-User-Id 和 X-Tenant-Id。不要在业务服务中写 JWT 校验 |
| **不暴露公网端口** | 业务服务端口只在 Docker 内网可达，外部只能通过网关访问 |
| **不处理计费** | RP 扣除已完成，不要在业务服务中调用支付 API |
| **不存储用户数据** | 用户/套餐/订阅数据都在外骨骼 PostgreSQL 中，业务服务不建用户表 |
| **记录 tenant_id** | 日志/审计必须包含 X-Tenant-Id，确保事后可追溯 |

---

## 6. 数据库模式（完整 DDL）

```sql
-- ============================================================
-- 外骨骼数据库模式 — 与核心业务完全独立
-- PostgreSQL 16 + Flyway 管理迁移
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. TENANTS
-- ============================================================
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(200) NOT NULL,
    slug VARCHAR(100) NOT NULL UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'suspended', 'deleted')),
    billing_email VARCHAR(255),
    stripe_customer_id VARCHAR(255) UNIQUE,
    logto_tenant_id VARCHAR(100),
    settings JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 2. USERS (Logto 身份的本地镜像 — JIT 创建)
-- ============================================================
CREATE TABLE users (
    id UUID PRIMARY KEY,  -- 与 Logto 用户 sub 一致
    tenant_id UUID NOT NULL,
    email VARCHAR(255),
    name VARCHAR(255),
    avatar_url TEXT,
    rp_balance NUMERIC(12, 2) NOT NULL DEFAULT 0,
    rp_balance_expires_at TIMESTAMPTZ,
    default_currency VARCHAR(3) NOT NULL DEFAULT 'cny',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_user_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);
CREATE INDEX idx_users_tenant ON users(tenant_id);

-- ============================================================
-- 3. PLANS
-- ============================================================
CREATE TABLE plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    tier VARCHAR(20) NOT NULL
        CHECK (tier IN ('free', 'pro', 'team', 'enterprise')),
    description TEXT,
    price_monthly_cents INT,
    price_yearly_cents INT,
    currency VARCHAR(3) NOT NULL DEFAULT 'cny',
    stripe_price_monthly_id VARCHAR(100),
    stripe_price_yearly_id VARCHAR(100),
    rp_allowance INT NOT NULL DEFAULT 0,
    rp_rollover BOOLEAN NOT NULL DEFAULT false,
    features JSONB NOT NULL DEFAULT '{}',
    is_active BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 4. SUBSCRIPTIONS
-- ============================================================
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    tenant_id UUID NOT NULL,
    plan_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL
        CHECK (status IN ('active','past_due','cancelled','expired','trialing','paused')),
    billing_cycle VARCHAR(10) NOT NULL DEFAULT 'monthly'
        CHECK (billing_cycle IN ('monthly', 'yearly')),
    current_period_start TIMESTAMPTZ NOT NULL,
    current_period_end TIMESTAMPTZ NOT NULL,
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT false,
    cancelled_at TIMESTAMPTZ,
    stripe_subscription_id VARCHAR(255) UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_sub_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_sub_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    CONSTRAINT fk_sub_plan FOREIGN KEY (plan_id) REFERENCES plans(id)
);
CREATE INDEX idx_subs_user ON subscriptions(user_id);
CREATE INDEX idx_subs_stripe ON subscriptions(stripe_subscription_id);

-- ============================================================
-- 5. RP TRANSACTIONS
-- ============================================================
CREATE TABLE rp_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    tenant_id UUID NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    type VARCHAR(20) NOT NULL
        CHECK (type IN ('purchase','consumption','grant','refund','expiration')),
    description TEXT,
    reference_id VARCHAR(255),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_rp_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_rp_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);
CREATE INDEX idx_rp_tx_user ON rp_transactions(user_id, created_at DESC);
CREATE INDEX idx_rp_tx_tenant ON rp_transactions(tenant_id, created_at DESC);

-- ============================================================
-- 6. API KEYS
-- ============================================================
CREATE TABLE api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    tenant_id UUID NOT NULL,
    label VARCHAR(200) NOT NULL,
    key_prefix VARCHAR(12) NOT NULL,
    key_hash TEXT NOT NULL,           -- bcrypt 哈希
    scopes TEXT[] NOT NULL DEFAULT '{read}',
    rate_limit_per_min INT DEFAULT 60,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    revoked BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT fk_apikey_user FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_apikey_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);
CREATE INDEX idx_apikeys_user ON api_keys(user_id);
CREATE INDEX idx_apikeys_hash ON api_keys(key_hash);

-- ============================================================
-- 7. TENANT CONFIGS
-- ============================================================
CREATE TABLE tenant_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL UNIQUE,
    rate_limit_per_min INT NOT NULL DEFAULT 1000,
    max_users INT NOT NULL DEFAULT 10,
    max_api_keys INT NOT NULL DEFAULT 5,
    storage_limit_gb NUMERIC(6, 1) DEFAULT 0.5,
    custom_domain VARCHAR(255),
    features JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_tc_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

-- ============================================================
-- 8. AUDIT LOGS
-- ============================================================
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID,
    tenant_id UUID,
    user_id UUID,
    method VARCHAR(10) NOT NULL,
    path VARCHAR(500) NOT NULL,
    status_code INT,
    duration_ms FLOAT,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_tenant ON audit_logs(tenant_id, created_at DESC);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);

-- ============================================================
-- 9. WEBHOOK EVENTS (幂等性)
-- ============================================================
CREATE TABLE webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id VARCHAR(255) NOT NULL UNIQUE,
    event_type VARCHAR(100) NOT NULL,
    payload TEXT NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_webhook_event_id ON webhook_events(event_id);
```

---

## 7. 部署架构

### 7.1 Docker Compose（开发环境）

```yaml
# exoskeleton/docker-compose.yml
# 外骨骼基础设施 — 独立于核心业务服务

version: "3.8"

services:
  # ============ 基础设施 ============

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: nsca
      POSTGRES_PASSWORD: nsca_dev
      POSTGRES_DB: nsca
    ports: ["5432:5432"]
    volumes: [pgdata:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U nsca"]
      interval: 5s

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    volumes: [redisdata:/data]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s

  # Nacos (服务注册 + 配置中心)
  nacos:
    image: nacos/nacos-server:v2.4.0
    environment:
      MODE: standalone
      SPRING_DATASOURCE_PLATFORM: embedded
    ports:
      - "8848:8848"
      - "9848:9848"

  # Sentinel Dashboard
  sentinel:
    image: bladex/sentinel-dashboard:1.8.8
    ports: ["8858:8858"]

  # XXL-JOB Admin
  xxl-job-admin:
    image: xuxueli/xxl-job-admin:2.4.0
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/nsca
      SPRING_DATASOURCE_USERNAME: nsca
      SPRING_DATASOURCE_PASSWORD: nsca_dev
    ports: ["8088:8088"]

  # ============ 认证 ============

  logto:
    image: ghcr.io/logto-io/logto:latest
    depends_on:
      logto-postgres: { condition: service_healthy }
    environment:
      DB_URL: postgres://logto:logto_dev@logto-postgres:5432/logto
      ENDPOINT: http://localhost:3001
      ADMIN_ENDPOINT: http://localhost:3002
    ports:
      - "3001:3001"
      - "3002:3002"
    env_file: ./config/logto.env

  logto-postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: logto
      POSTGRES_PASSWORD: logto_dev
      POSTGRES_DB: logto
    volumes: [logto_pgdata:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U logto"]
      interval: 5s

  # ============ 外骨骼微服务 ============

  gateway:
    build: { context: ./exoskeleton-gateway, dockerfile: Dockerfile }
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
      nacos: { condition: service_healthy }
    ports: ["8080:8080"]
    environment:
      NACOS_SERVER_ADDR: nacos:8848
      SENTINEL_DASHBOARD: sentinel:8858

  auth-service:
    build: { context: ./exoskeleton-auth, dockerfile: Dockerfile }
    depends_on: [postgres, redis, nacos]

  tenant-service:
    build: { context: ./exoskeleton-tenant, dockerfile: Dockerfile }
    depends_on: [postgres, nacos]

  billing-service:
    build: { context: ./exoskeleton-billing, dockerfile: Dockerfile }
    depends_on: [postgres, redis, nacos]

  admin-service:
    build: { context: ./exoskeleton-admin, dockerfile: Dockerfile }
    depends_on: [postgres, nacos]

  scheduler-service:
    build: { context: ./exoskeleton-scheduler, dockerfile: Dockerfile }
    depends_on: [postgres, xxl-job-admin]

  # ============ 业务服务（不修改！仅作为依赖） ============

  nsca-compute:
    build: { context: ../services/nsca-compute, dockerfile: Dockerfile }
    # 注意：不对外暴露端口，仅内网可达
    command: uvicorn main:app --host 0.0.0.0 --port 8100

  # ============ 前端 ============

  web:
    build: { context: ../web, dockerfile: Dockerfile }
    depends_on: [gateway]
    environment:
      NEXT_PUBLIC_API_URL: http://localhost:8080
      NEXT_PUBLIC_LOGTO_ENDPOINT: http://localhost:3001
      NEXT_PUBLIC_LOGTO_APP_ID: ${LOGTO_APP_ID}
    ports: ["3000:3000"]

  admin-ui:
    build: { context: ../admin, dockerfile: Dockerfile }
    depends_on: [gateway]
    environment:
      VITE_API_URL: http://localhost:8080
      VITE_LOGTO_ENDPOINT: http://localhost:3001
      VITE_LOGTO_APP_ID: ${LOGTO_ADMIN_APP_ID}
    ports: ["3005:3005"]

  # ============ 监控 ============

  prometheus:
    image: prom/prometheus:latest
    volumes: [./config/prometheus.yml:/etc/prometheus/prometheus.yml]
    ports: ["9090:9090"]

  grafana:
    image: grafana/grafana:latest
    ports: ["3003:3003"]
    volumes: [grafana_data:/var/lib/grafana]

  skywalking-oap:
    image: apache/skywalking-oap-server:10.0.0
    environment:
      SW_STORAGE: postgresql
      SW_JDBC_URL: jdbc:postgresql://postgres:5432/skywalking
    ports: ["11800:11800", "12800:12800"]

volumes:
  pgdata:
  redisdata:
  logto_pgdata:
  grafana_data:
```

### 7.2 外部环境变量

```bash
# exoskeleton/config/.env
LOGTO_APP_ID=xxx
LOGTO_APP_SECRET=xxx
LOGTO_ADMIN_APP_ID=xxx
STRIPE_API_KEY=sk_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
JEEPAY_BASE_URL=https://pay.jeepay.vip
JEEPAY_MCH_NO=xxx
JEEPAY_APP_ID=xxx
JEEPAY_API_KEY=xxx
```

---

## 8. 关键设计决策

### 决策 1：外骨骼作为独立 Maven 多模块项目

**理由**：外骨骼与核心业务零代码耦合。独立仓库意味着独立的 CI/CD、独立的版本号、独立的发布节奏。网关 Header 协议是唯一的接口约定——任何一方的修改不影响另一方，只要 Header 不变。

### 决策 2：Spring Cloud Alibaba 替代 Spring Cloud Netflix

**理由**：Netflix 栈（Eureka、Hystrix）已进入维护模式，Spring Boot 3.x 兼容性差。Alibaba 栈（Nacos、Sentinel）是国内微服务事实标准，社区活跃，中文文档完备。Nacos 同时提供服务注册和配置中心，比 Eureka + Config Server 更简洁。

### 决策 3：MyBatis-Plus TenantLineInnerInterceptor 实现多租户

**理由**：与 Hibernate Filter 相比，TenantLineInnerInterceptor 自动注入 WHERE tenant_id = ?，开发者不需要在每个查询中手动添加。RuoYi-Vue-Pro、Jeepay 等验证了该方案的生产可行性。全局表（plans、webhook_events）可通过 `ignoreTable` 排除。

### 决策 4：RP 点作为统一消费度量

**理由**：弥合了中国支付和 Stripe 订阅之间的差距。中国用户不能通过支付宝/微信自动订阅，但可以购买 RP 包（一次性付款）。API 调用统一消耗 RP，不管 RP 来自何种渠道。汇率清晰（1 CNY = 10 RP，1 USD = 70 RP）。

### 决策 5：网关 Header 作为唯一集成协议

**理由**：业务服务不导入任何外骨骼代码、不调用外骨骼 API、不共享数据库。它只信任网关注入的 X-Tenant-Id 和 X-User-Id。这确保业务服务可以独立演进，用任意语言重写，不受外骨骼约束。

### 决策 6：Logto 管理用户身份，Spring Security 管理访问控制

**理由**：Logto 是 OIDC Provider，负责用户注册、登录、JWT 签发。Spring Security 是 OAuth2 Resource Server，负责 JWT 校验、角色提取、端点保护。两者职责清晰——切换 OIDC Provider 只需更改 Spring Security 的 issuer-uri。

### 决策 7：Stripe Webhook 作为支付状态的唯一权威来源

**理由**：所有订阅状态由 Webhook 事件驱动，不在应用代码中主动修改。`webhook_events` 表提供幂等性保证（event_id 唯一约束）。Jeepay 回调同理。

### 决策 8：核心业务代码零修改

**理由**：外骨骼是包装层，不应污染核心计算代码。`services/`、`experiments/`、`web/` 下的现有代码保持不变。业务服务只需在入口处多读几个 Header，其余逻辑完全不受影响。
