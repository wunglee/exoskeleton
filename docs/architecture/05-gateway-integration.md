# 05. API 网关与集成协议

> NSCA 外骨骼基于 yudao-gateway 扩展，复用其 Spring Cloud Gateway + Sentinel + Resilience4j 基础，新增 JWT 离线验签、API Key 认证、功能门控、RP 消费和核心透传路由。网关是外骨骼系统唯一入口，也是外骨骼与核心业务服务之间的唯一集成面。

## 5.1 网关架构

### 5.1.1 yudao-gateway 基座

yudao-gateway 已提供以下能力，NSCA 直接复用：

| yudao 能力 | 实现 | NSCA 策略 |
|-----------|------|----------|
| **Spring Cloud Gateway** | 响应式非阻塞路由 | 直接复用 |
| **Sentinel 限流/熔断** | 网关层 Sentinel Filter | 直接复用，新增 NSCA 限流规则 |
| **Resilience4j 断路器** | `spring-cloud-starter-circuitbreaker-reactor-resilience4j` | 直接复用 |
| **令牌验证过滤** | `TokenAuthenticationFilter`（Feign RPC 调用 system 模块验签） | 扩展 → 前置 JWT 离线验签 |
| **安全配置** | CSRF 关闭、无状态 Session、`@PermitAll` 端点 | 直接复用 |
| **多租户 Web 过滤器** | `TenantWebFilter`（从 Header/Domain/参数提取租户 ID） | 直接复用 |

### 5.1.2 NSCA 扩展后的过滤器链

```
客户端请求
    │
    ▼
[-1] ApiKeyAuthFilter       ← ★ NSCA 新增：API 密钥认证 (X-API-Key header)
    │
    ▼
[0]  JwtAuthFilter          ← ★ NSCA 新增：JWT RS256 离线验签
    │                          提取 user_id, tenant_id → AuthContext
    │                          失败则回退到 yudao TokenAuthenticationFilter
    ▼
[10] TenantHeaderFilter     ← 复用 yudao: TenantWebFilter 注入 X-Tenant-Id
    │
    ▼
[20] FeatureGateFilter      ← ★ NSCA 新增：订阅层级功能门控
    │
    ▼
[30] RPConsumptionFilter    ← ★ NSCA 新增：API 端点 RP 扣除
    │
    ▼
[40] RateLimitFilter        ← 复用 yudao: Sentinel Gateway Flow Control
    │
    ▼
[50] RouteToTarget          ← 复用 yudao: Spring Cloud Gateway 路由
    │                          外骨骼服务 (system/member/pay/community)
    │                          或核心业务服务 (nsca-compute)
    ▼
[99] AuditLogFilter         ← 复用 yudao: 异步审计日志
```

> **过滤器顺序说明**：顺序决定了过滤器执行优先级。NSCA 新增过滤器（前缀 ★）插入 yudao 已有的过滤器链中，不替换 yudao 原有过滤器。

## 5.2 路由配置

> 以下路由基于 yudao-gateway 的 `application.yaml` 扩展。yudao 原有路由（system、infra、member、pay 等模块）保留，NSCA 新增核心透传和社区路由。

```yaml
spring:
  cloud:
    gateway:
      routes:
        # ============ yudao 原有路由（直接复用） ============
        - id: yudao-module-system
          uri: lb://yudao-module-system
          predicates: Path=/api/v1/auth/**,/api/v1/admin/**
        - id: yudao-module-member
          uri: lb://yudao-module-member
          predicates: Path=/api/v1/billing/**,/api/v1/subscriptions/**
        - id: yudao-module-pay
          uri: lb://yudao-module-pay
          predicates: Path=/api/v1/pay/**,/api/v1/webhooks/**
        - id: yudao-module-infra
          uri: lb://yudao-module-infra
          predicates: Path=/api/v1/infra/**

        # ============ NSCA 扩展路由 ============
        - id: nsca-community
          uri: lb://yudao-module-community
          predicates: Path=/api/v1/community/**

        # ============ 核心业务路由（透传，不修改） ============
        - id: nsca-core
          uri: lb://nsca-core-service
          predicates: Path=/api/v1/core/**
          filters:
            - name: CircuitBreaker
              args:
                name: coreBreaker
                fallbackUri: forward:/fallback/core
            - name: RequestSize
              args:
                maxSize: 10MB

      default-filters:
        - RateLimit=60,60                                  # 复用 yudao Sentinel
        - RemoveRequestHeader=Cookie
        - RemoveRequestHeader=Origin
```

## 5.3 网关集成协议（外骨骼 → 核心业务）

这是整个架构中最核心的约定：外骨骼与核心业务服务之间的接口**只由 HTTP Header 定义**。没有共享代码、没有 SDK 依赖、没有数据库共享。

### 5.3.1 外骨骼向核心业务注入的 Header

网关在完成所有校验（JWT/API Key、租户、功能门控、RP 扣除）后，向核心业务请求注入以下 Header：

```
X-User-Id:     user_uuid
X-Tenant-Id:   tenant_uuid
X-Request-Id:  uuid-v4
X-Job-Id:      uuid-v4 (仅计算端点)
X-Features:    base64(json)  ← 当前套餐的功能集
X-Auth-Method: jwt | api_key
```

### 5.3.2 核心业务服务的责任（最小化）

```python
# services/nsca-core/main.py
# 核心业务不导入任何外骨骼代码，不自行认证
# 它只需信任网关注入的 Header

from fastapi import FastAPI, Request, Header

app = FastAPI()

@app.post("/api/v1/core/causal-discovery")
async def causal_discovery(
    request: Request,
    x_tenant_id: str = Header(...),
    x_user_id: str = Header(...),
    x_job_id: str = Header(...),
):
    """
    核心业务责任：
    1. 信任 X-Tenant-Id 和 X-User-Id（外骨骼已验证）
    2. 执行核心计算
    3. 记录 tenant_id 到日志（用于审计追溯）
    4. 不处理认证、计费、租户隔离
    """
    body = await request.json()
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

### 5.3.3 核心业务的硬性约定

| 规则 | 说明 |
|------|------|
| **不自行认证** | 信任 X-User-Id 和 X-Tenant-Id。不要在核心服务中写 JWT 校验 |
| **不暴露公网端口** | 核心服务端口只在 Docker 内网可达，外部只能通过网关访问 |
| **不处理计费** | RP 扣除已在网关层完成，核心服务不调用支付 API |
| **不存储用户数据** | 用户/套餐/订阅数据都在外骨骼 MySQL 中，核心服务不建用户表 |
| **记录 tenant_id** | 日志/审计必须包含 X-Tenant-Id，确保事后可追溯 |

## 5.4 Sentinel 限流与熔断

> Sentinel 已由 yudao-gateway 集成。NSCA 只需新增限流规则，无需替代组件。

### 5.4.1 限流规则

```
┌──────────────────┬─────────┬──────────────┬──────────┐
│ 资源              │ 阈值    │ 限流模式      │ 效果     │
├──────────────────┼─────────┼──────────────┼──────────┤
│ gateway-common   │ 1000    │ 每租户/秒    │ 快速失败 │
│ core-causal      │ 10      │ 每用户/分钟  │ 排队等待 │
│ core-batch       │ 5       │ 每用户/分钟  │ 快速失败 │
│ admin-read       │ 100     │ 全局/秒      │ 快速失败 │
└──────────────────┴─────────┴──────────────┴──────────┘
```

### 5.4.2 断路器（Resilience4j — 核心服务保护，yudao 已集成）

```yaml
resilience4j:
  circuitbreaker:
    instances:
      coreBreaker:
        slidingWindowSize: 20
        failureRateThreshold: 50
        waitDurationInOpenState: 30s
        permittedNumberOfCallsInHalfOpenState: 5
        slowCallRateThreshold: 100
        slowCallDurationThreshold: 120s
  timelimiter:
    instances:
      coreTimeout:
        timeoutDuration: 120s  # 仿真计算允许长超时
```

## 5.5 API 密钥认证（NSCA 新增）

> yudao 不提供 API Key 认证。NSCA 新增网关过滤器实现 API Key 验证。

```java
@Component
public class ApiKeyAuthGatewayFilter implements GlobalFilter, Ordered {

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String apiKey = exchange.getRequest().getHeaders().getFirst("X-API-Key");
        if (apiKey == null) return chain.filter(exchange);  // 无 API Key，交由后续过滤器

        // HMAC-SHA256 验证
        ApiKeyRecord record = apiKeyRepository.findByKeyId(extractKeyId(apiKey));
        if (record == null || record.isRevoked()) {
            exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
            return exchange.getResponse().setComplete();
        }

        // 注入认证上下文到 Header
        exchange.getRequest().mutate()
            .header("X-User-Id", record.getUserId().toString())
            .header("X-Tenant-Id", record.getTenantId().toString())
            .header("X-Auth-Method", "api_key");

        return chain.filter(exchange);
    }

    @Override
    public int getOrder() { return -1; }  // 在 JwtAuthFilter 之前
}
```

## 5.6 RP 消费网关过滤器（NSCA 新增）

```java
@Component
public class RPConsumptionFilter implements GlobalFilter, Ordered {

    // 端点 → 每次调用的 RP 成本（配置化，此处示例）
    private static final Map<String, Integer> RP_COST = Map.of(
        "/api/v1/core/causal-discovery", 10,
        "/api/v1/core/batch-analysis", 50,
        "/api/v1/core/advanced-simulation", 100
    );

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String path = exchange.getRequest().getURI().getPath();
        Integer cost = RP_COST.get(path);
        if (cost == null) return chain.filter(exchange);

        AuthContext ctx = exchange.getAttribute("authContext");

        return Mono.fromCallable(() -> {
            rpService.deduct(ctx.userId(), ctx.tenantId(), BigDecimal.valueOf(cost),
                           "API调用: " + path);
            return true;
        }).onErrorMap(InsufficientRPException.class, e -> {
            exchange.getResponse().setStatusCode(HttpStatus.PAYMENT_REQUIRED);
            throw new ResponseStatusException(HttpStatus.PAYMENT_REQUIRED,
                "RP 余额不足，请充值");
        }).then(chain.filter(exchange));
    }

    @Override
    public int getOrder() { return 30; }
}
```

---

## 5.7 核心透传配置接口

> 核心业务通过标准化配置接口向外骨骼暴露页面渲染信息。外骨骼不实现 Fork/MR/仿真预览/排行榜的业务逻辑——它只负责调用核心配置接口获取 Tab 列表、按钮配置、权限映射，然后渲染对应的 UI 组件。

### 5.7.1 透传模式

```
外骨骼前端                          网关                               核心业务
    │                               │                                    │
    │  GET /api/v1/core/page-config │                                    │
    │  ?type=project-public         │                                    │
    │  &project_id={id}             │                                    │
    ├──────────────────────────────►│                                    │
    │                               │  GET /api/v1/core/page-config      │
    │                               │  Headers:                           │
    │                               │    X-User-Id: {uid}                │
    │                               │    X-Tenant-Id: {tid}              │
    │                               │    X-Features: base64(feature_map) │
    │                               ├───────────────────────────────────►│
    │                               │                                    │
    │                               │  ← 200 {                           │
    │                               │      tabs: [...],                  │
    │                               │      actions: [...],               │
    │                               │      permissions: {...}            │
    │                               │    }                               │
    │  ← 200 { tabs, actions }      │ ← ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
    │                               │                                    │
    │  外骨骼根据 type 渲染：        │                                    │
    │  ┌─────────────────────────┐  │                                    │
    │  │ type: "core_data"       │  │  外骨骼调用 endpoint 获取数据，     │
    │  │   → 调用 endpoint       │  │  用自己的组件渲染                  │
    │  │ type: "core_iframe"     │  │  外骨骼嵌入 iframe，               │
    │  │   → 嵌入 src URL        │  │  核心完全控制内容                  │
    │  │ type: "exoskeleton"     │  │  外骨骼自有组件，                  │
    │  │   → 调用外骨骼 API      │  │  不经过核心                        │
    │  └─────────────────────────┘  │                                    │
```

### 5.7.2 核心配置接口清单

| 接口 | 方法 | 用途 | 核心负责 |
|------|------|------|---------|
| `/api/v1/core/page-config` | GET | 返回页面结构化配置（Tab 列表、按钮、权限） | 定义哪些 Tab/按钮可见 |
| `/api/v1/core/permissions` | GET | 返回用户对指定资源的操作权限 | 权限判定逻辑 |
| `/api/v1/core/leaderboard` | GET | 返回排行榜排序数据 | 分数计算与排序 |
| `/api/v1/core/projects/{id}/fork` | POST | Fork 项目 | 完整 Fork 业务逻辑 |
| `/api/v1/core/projects/{id}/merge-requests` | POST | 创建合并请求 | 完整 MR 业务逻辑 |
| `/api/v1/core/projects/{id}/progress` | GET | 获取研究进展数据 | 研究进展计算 |
| `/api/v1/core/projects/{id}/forks` | GET | 获取 Fork 派生树 | Fork 关系查询 |
| `/api/v1/core/projects/{id}/versions` | GET | 获取版本历史 | 版本 diff 计算 |

### 5.7.3 page-config 接口规格

```yaml
# GET /api/v1/core/page-config
# 核心返回页面配置，外骨骼据此渲染社区层页面
request:
  type: string                  # 'project-public' | 'project-workspace' | 'domain-square'
  project_id: UUID?
  domain_id: string?

response_200:
  tabs:                         # Tab 列表（按 display_order 排序）
    - key: string               # Tab 唯一标识
      label: string             # 显示名称（支持 i18n key）
      type: string              # 'core_data' | 'core_iframe' | 'exoskeleton'
      endpoint: string?         # core_data 类型的数据 API 路径
      src: string?              # core_iframe 类型的 iframe URL
      visible: boolean          # 是否显示（核心根据项目状态控制）
      required_features: string[] # 需要哪些功能门控（如 ["monte_carlo"]）
      display_order: int
  actions:                      # 操作按钮配置
    - key: string               # 'fork' | 'merge_request' | 'star' | 'edit' | 'export'
      label: string
      visible: boolean          # 核心控制按钮是否显示
      disabled: boolean         # 灰显但可点击（弹出升级提示）
      disabled_reason: string?  # 灰显原因
      endpoint: string?         # 点击后调用的 API
      method: string?           # HTTP 方法
      required_tier: string?    # 需要的最低会员等级
  permissions:                  # 当前用户对此项目的权限
    can_view: boolean
    can_fork: boolean
    can_edit: boolean
    can_delete: boolean
    can_create_mr: boolean
    can_review_mr: boolean
  metadata:
    project_name: string
    owner_id: UUID
    visibility: string          # 'public' | 'private' | 'team'
```

### 5.7.4 外骨骼前端渲染策略

```tsx
// 社区层项目公共页 — 核心透传渲染
async function ProjectPublicPage({ projectId }) {
  // 1. 获取核心页面配置
  const config = await fetch(
    `/api/v1/core/page-config?type=project-public&project_id=${projectId}`
  ).then(r => r.json());

  // 2. 渲染 Tab（核心决定哪些 Tab 可见）
  const tabs = config.tabs.filter(t => t.visible).map(tab => {
    switch (tab.type) {
      case 'core_data':
        return <CoreDataTab key={tab.key} endpoint={tab.endpoint} />;
      case 'core_iframe':
        return <CoreIframeTab key={tab.key} src={tab.src} />;
      case 'exoskeleton':
        return <ExoskeletonTab key={tab.key} tabKey={tab.key} projectId={projectId} />;
    }
  });

  // 3. 渲染操作按钮（核心决定哪些按钮可见/可用）
  const actions = config.actions.map(action => (
    <ActionButton
      key={action.key}
      label={action.label}
      visible={action.visible}
      disabled={action.disabled}
      disabledReason={action.disabled_reason}
      onClick={() => callCoreApi(action.endpoint, action.method)}
    />
  ));

  return <PageLayout tabs={tabs} actions={actions} />;
}
```

### 5.7.5 核心透传的路由配置

```yaml
spring:
  cloud:
    gateway:
      routes:
        # 核心透传路由 — 外骨骼不处理业务逻辑，仅转发
        - id: nsca-core-service
          uri: lb://nsca-core-service
          predicates: Path=/api/v1/core/**
          filters:
            - name: CircuitBreaker
              args:
                name: coreBreaker
                fallbackUri: forward:/fallback/core
            - name: Retry
              args:
                retries: 2
                statuses: BAD_GATEWAY,SERVICE_UNAVAILABLE
                methods: GET
```

### 5.7.6 page-config 缓存策略

核心 page-config 响应在网关层通过 Caffeine 本地缓存以减少核心服务压力：

```java
@Component
public class CoreConfigCacheFilter implements GlobalFilter, Ordered {

    private final Cache<String, PageConfig> cache = Caffeine.newBuilder()
        .expireAfterWrite(30, TimeUnit.SECONDS)
        .maximumSize(10_000)
        .build();

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String path = exchange.getRequest().getURI().getPath();
        if (!path.equals("/api/v1/core/page-config")) {
            return chain.filter(exchange);
        }

        String cacheKey = exchange.getRequest().getURI().getRawQuery();
        PageConfig cached = cache.getIfPresent(cacheKey);
        if (cached != null) {
            byte[] bytes = objectMapper.writeValueAsBytes(cached);
            exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
            return exchange.getResponse()
                .writeWith(Mono.just(exchange.getResponse().bufferFactory().wrap(bytes)));
        }

        return chain.filter(exchange).then(Mono.fromRunnable(() -> {
            PageConfig config = exchange.getAttribute("corePageConfig");
            if (config != null) cache.put(cacheKey, config);
        }));
    }

    @Override
    public int getOrder() { return 25; }
}
```

### 5.7.7 核心不可用时的降级

```
核心服务不可用
    │
    ▼
断路器打开 (coreBreaker)
    │
    ▼
fallback: /fallback/core
    │
    ├── page-config → 返回静态最小配置:
    │     { tabs: [{ key: "forum", type: "exoskeleton" }],
    │       actions: [],
    │       permissions: { can_view: true, ...全部 false } }
    │
    ├── leaderboard → 返回缓存的最新排行榜（如有）
    │
    └── fork / merge-request → 返回 503:
          { error: "CORE_UNAVAILABLE",
            message: "操作暂时不可用，请稍后重试" }
```

---

## 5.8 yudao 扩展映射

| yudao-gateway 原有 | 方式 | NSCA 扩展 |
|-------------------|------|----------|
| `TokenAuthenticationFilter` | 保留，新增前置过滤器 | `JwtAuthFilter`（离线 RS256 验签） |
| `TenantWebFilter` | 直接复用 | 注入 `X-Tenant-Id`、`X-User-Id` Header |
| Sentinel Gateway Flow Control | 直接复用 | 新增 NSCA 限流规则（核心端点、API Key 端点） |
| Resilience4j CircuitBreaker | 直接复用 | 新增 `coreBreaker` 断路器配置 |
| Spring Cloud Gateway 路由 | 扩展 | 新增核心透传路由（`/api/v1/core/**`）、社区路由 |
| 审计日志过滤 | 直接复用 | 异步记录 API Key 使用、RP 消费审计 |
| — | **新增 Filter** | `ApiKeyAuthFilter`、`FeatureGateFilter`、`RPConsumptionFilter`、`CoreConfigCacheFilter` |

---

## 参考

- [Spring Cloud Gateway 官方文档](https://docs.spring.io/spring-cloud-gateway/)
- [Sentinel 网关限流](https://sentinelguard.io/zh-cn/docs/api-gateway-flow-control.html)
- [yudao 网关文档](https://doc.iocoder.cn/gateway/)
- [Resilience4j 文档](https://resilience4j.readme.io/)
- [11-community.md](11-community.md) — 社区层架构（核心透传的消费方）
