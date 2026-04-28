# 05. API 网关与集成协议

> Spring Cloud Gateway 是外骨骼系统的唯一入口，也是外骨骼与核心业务服务之间的唯一集成面。业务服务不需要知道 JWT 格式、租户隔离策略、收费规则——只需信任网关注入的 HTTP Header。

## 5.1 网关架构

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

## 5.2 路由配置

```yaml
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

## 5.3 网关集成协议（外骨骼 → 业务服务）

这是整个架构中最核心的约定：外骨骼与业务服务之间的接口**只由 HTTP Header 定义**。没有共享代码、没有 SDK 依赖、没有数据库共享。

### 5.3.1 外骨骼向业务服务注入的 Header

网关在完成所有校验（JWT/API Key、租户、功能门控、RP 扣除）后，向业务服务请求注入以下 Header：

```
X-User-Id:     logto_user_uuid
X-Tenant-Id:   tenant_uuid
X-Request-Id:  uuid-v4
X-Job-Id:      uuid-v4 (仅计算端点)
X-Features:    base64(json)  ← 当前套餐的功能集
X-Auth-Method: jwt | api_key
```

### 5.3.2 业务服务的责任（最小化）

```python
# services/nsca-compute/main.py
# 业务服务不需要导入任何外骨骼的代码，不需要知道 JWT 格式
# 它只需信任网关注入的 Header

from fastapi import FastAPI, Request, Header

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

### 5.3.3 业务服务的硬性约定

| 规则 | 说明 |
|------|------|
| **不自行认证** | 信任 X-User-Id 和 X-Tenant-Id。不要在业务服务中写 JWT 校验 |
| **不暴露公网端口** | 业务服务端口只在 Docker 内网可达，外部只能通过网关访问 |
| **不处理计费** | RP 扣除已完成，不要在业务服务中调用支付 API |
| **不存储用户数据** | 用户/套餐/订阅数据都在外骨骼 PostgreSQL 中，业务服务不建用户表 |
| **记录 tenant_id** | 日志/审计必须包含 X-Tenant-Id，确保事后可追溯 |

## 5.4 Sentinel 限流与熔断

### 5.4.1 限流规则

```
┌──────────────────┬─────────┬──────────┬───────┐
│ 资源              │ 阈值     │ 限流模式  │ 效果   │
├──────────────────┼─────────┼──────────┼───────┤
│ gateway-common   │ 1000    │ 每租户    │ 快速失败│
│ compute-causal   │ 10      │ 每用户/min│ 排队等待│
│ compute-batch    │ 5       │ 每用户/min│ 快速失败│
│ admin-read       │ 100     │ 全局      │ 快速失败│
└──────────────────┴─────────┴──────────┴───────┘
```

### 5.4.2 断路器（Resilience4j — 业务服务保护）

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

## 5.5 API 密钥认证（与 JWT 互补）

API 密钥用于 CLI/SDK 等程序化访问：

```java
@Component
public class ApiKeyAuthGatewayFilter implements GlobalFilter, Ordered {

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

        // 注入认证上下文到 Header
        exchange.getRequest().mutate()
            .header("X-User-Id", record.getUserId())
            .header("X-Tenant-Id", record.getTenantId())
            .header("X-Auth-Method", "api_key");

        return chain.filter(exchange);
    }

    @Override
    public int getOrder() { return -1; }
}
```

## 5.6 RP 消费网关过滤器

```java
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

        AuthContext ctx = exchange.getAttribute("authContext");

        return Mono.fromCallable(() -> {
            rpService.deduct(ctx.userId(), ctx.tenantId(), BigDecimal.valueOf(cost),
                           "API调用: " + path);
            return true;
        }).onErrorMap(InsufficientRPException.class, e -> {
            exchange.getResponse().setStatusCode(HttpStatus.PAYMENT_REQUIRED);
            throw new ResponseStatusException(HttpStatus.PAYMENT_REQUIRED, ...);
        }).then(chain.filter(exchange));
    }

    @Override
    public int getOrder() { return 30; }
}
```

---

## 参考

- [Spring Cloud Gateway 官方文档](https://docs.spring.io/spring-cloud-gateway/)
- [Sentinel 网关限流](https://sentinelguard.io/zh-cn/docs/api-gateway-flow-control.html)
- [Resilience4j 文档](https://resilience4j.readme.io/)
