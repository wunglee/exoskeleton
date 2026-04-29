# 06. 计费系统架构

> NSCA 外骨骼基于 yudao-module-member 的会员等级和积分体系扩展。`member_level` 表扩展为订阅计划，`member_point_record` 扩展为 RP 交易流水。新增 `rp_account` + `rp_lot` 表族实现 FIFO 批次追踪，新增 `user_subscription` 表管理订阅状态机。

## 6.1 设计原则

**基于 yudao member 扩展**：yudao-module-member 已提供会员等级（`member_level`）、积分流水（`member_point_record`）和用户-等级关联（`member_user.levelId`）。NSCA 在此基础上扩展为订阅计划和 RP 积分体系，不重写 yudao 已有逻辑。

**透明可预测**：用户在执行任何消耗性操作前，系统预估并展示本次消耗；计费明细精确到单个 Tick，杜绝黑盒。

**混合计费模式**：基础功能订阅制（包月/包年），超额资源按量计费，兼顾可预测性与灵活性。

**实时配额守护**：每个仿真启动前校验配额，执行中监控消耗，接近上限时主动告警，杜绝超额透支。

**多币种支持**：企业客户支持合同币种（USD/CNY/EUR），个人用户按地区默认币种，汇率每日更新。

## 6.2 计费维度

| 维度 | 说明 | 计费单位 |
|------|------|----------|
| **仿真 Tick** | 核心消耗资源 | Tick |
| **存储空间** | 项目文件、审计日志 | GB/月 |
| **并发仿真** | 同时运行的仿真数 | 实例 |
| **API 调用** | SDK / 外部集成 | 次/月 |
| **蒙特卡洛** | 蒙特卡洛采样运行 | 次/月 |
| **分支保留** | What-if 分支存储 | 分支数 |
| **协作成员** | 项目协作者数 | 人 |
| **导出报告** | PDF/数据导出 | 次/月 |
| **模型包市场** | 高级模型包访问 | — |
| **科研智能体** | LLM 调用次数 | Token |

## 6.3 计费模型

```
┌──────────────────────────────────────────────────────────────────────┐
│                    计费服务 (yudao-module-member 扩展)                  │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  yudao 原有（复用）               NSCA 扩展（新增）                     │
│  ┌────────────────────┐    ┌────────────────────────────────────┐   │
│  │ 会员等级管理         │    │  订阅管理                           │   │
│  │ member_level CRUD   │    │  - 计划切换 (扩展 levelId)          │   │
│  │ member_user.levelId │    │  - 周期结算 (Stripe/Jeepay)        │   │
│  │ member_point_record │    │  - 优惠券                           │   │
│  └────────────────────┘    └────────────────────────────────────┘   │
│                            ┌────────────────────────────────────┐   │
│  ┌────────────────────┐    │  配额管理器 (QuotaManager)           │   │
│  │ 支付模块             │    │  实时可用 = 订阅配额                │   │
│  │ yudao-module-pay    │    │           + 增量包                  │   │
│  │ - 统一订单          │    │           - 已用                    │   │
│  │ - Jeepay 渠道       │    │           - 预留                    │   │
│  └────────────────────┘    └────────────────────────────────────┘   │
│                                                                      │
│  存储层                                                               │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  MySQL (yudao member_level / member_point_record +            │   │
│  │         NSCA 新增 subscription_* / rp_* 表族)                  │   │
│  │  Redis (配额实时缓存 + 限流计数器)                              │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## 6.4 订阅计划数据模型

### 6.4.1 扩展 yudao `member_level` 表

> **扩展策略**：不新建 `subscription_plan` 表替代 `member_level`，而是在其基础上新增价格、币种和功能配置字段。

```sql
-- NSCA 扩展：member_level 表新增字段（不修改 yudao 原有字段）
ALTER TABLE member_level
    ADD COLUMN price_monthly DECIMAL(10,2) COMMENT '月付价格（NULL 表示不支持月付）',
    ADD COLUMN price_yearly  DECIMAL(10,2) COMMENT '年付价格',
    ADD COLUMN currency      VARCHAR(3) DEFAULT 'CNY' COMMENT '币种 (USD/CNY/EUR)',
    ADD COLUMN features      JSON COMMENT '功能开关与配额 JSON';
```

**yudao 字段映射**：

| yudao `member_level` 字段 | NSCA 订阅计划语义 | 方式 |
|--------------------------|-----------------|------|
| `id` | 计划唯一标识 | 直接使用 |
| `name` | 计划名 (Free / Pro / Team / Enterprise) | 直接使用 |
| `level` | 计划等级序号 (1=Free, 2=Pro, 3=Team, 4=Enterprise) | 直接使用 |
| `experience` | 升级所需经验（NSCA 改为荣誉级别晋升阈值） | 复用，语义调整 |
| `discountPercent` | 年付折扣百分比（如 17 表示 8.3 折） | 直接使用 |
| `icon` / `backgroundUrl` | 计划展示图标/背景 | 直接使用 |
| `status` | 计划启用/停用 | 直接使用 |
| — | ★ `price_monthly` | **新增** |
| — | ★ `price_yearly` | **新增** |
| — | ★ `currency` | **新增** |
| — | ★ `features` (JSON) | **新增** |

### 6.4.2 订阅计划数据示例

`features` JSON 字段的 Schema：

```json
{
  "features": {
    "tick_monthly": 10000,
    "storage_gb": 5,
    "concurrent_sims": 2,
    "api_calls_monthly": 5000,
    "monte_carlo": false,
    "branches": 3,
    "collaborators": 1,
    "exports_monthly": 10,
    "rp_earn_multiplier": 1.0,
    "rp_daily_cap": 2000,
    "priority_support": false,
    "custom_domain": false,
    "sso": false,
    "audit_log_retention_days": 30
  }
}
```

| 计划 | level | price_monthly (CNY) | price_yearly (CNY) | 核心区别 |
|------|-------|--------------------|--------------------|---------|
| Free | 1 | 0 | 0 | 基础功能，无蒙特卡洛 |
| Pro | 2 | 99 | 990 | 全功能 + 蒙特卡洛 + 10万 Tick |
| Team | 3 | 499 | 4990 | 团队协作 + 100万 Tick + SSO |
| Enterprise | 4 | — | — | 自定义配额 + SLA + 专属支持 |

### 6.4.3 用户订阅表（NSCA 新增）

> yudao `member_user` 只有 `levelId` 字段表示当前等级，没有订阅状态机。NSCA 新增 `user_subscription` 表管理订阅生命周期。

```sql
CREATE TABLE user_subscription (
    id                  BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id             BIGINT NOT NULL COMMENT '关联 member_user.id',
    plan_id             BIGINT NOT NULL COMMENT '关联 member_level.id',
    status              VARCHAR(20) NOT NULL DEFAULT 'active'
                        COMMENT 'active | cancelled | paused | past_due | trialing',
    billing_cycle       VARCHAR(10) COMMENT 'monthly | yearly',
    current_period_start DATETIME NOT NULL,
    current_period_end   DATETIME NOT NULL,
    cancel_at_period_end TINYINT DEFAULT 0,
    trial_end            DATETIME COMMENT '试用截止',
    payment_method_id    BIGINT COMMENT '关联 payment_method 表',
    stripe_subscription_id VARCHAR(100) COMMENT 'Stripe 订阅 ID',
    created_at           DATETIME NOT NULL,
    updated_at           DATETIME,
    FOREIGN KEY (user_id) REFERENCES member_user(id),
    FOREIGN KEY (plan_id) REFERENCES member_level(id),
    INDEX idx_user (user_id),
    INDEX idx_status_period (status, current_period_end)
);
```

**订阅状态机**：

```
trial → active → past_due → active  (续费成功)
                     │
                     ▼
                  cancelled (取消或到期未续)
                     │
                     ▼
                  expired (90天后数据归档)
```

## 6.5 计量采集机制

> yudao 无计量采集组件。NSCA 新增计量服务，通过 RocketMQ（yudao 已集成）异步采集。

**Tick 计量**（Java 风格）：

```java
// NSCA 新增计量事件（通过 RocketMQ 异步发送）
@Data
public class TickUsageEvent {
    private String eventId;       // UUID
    private Long userId;          // 关联 member_user.id
    private Long projectId;
    private String runId;
    private int tickCount;
    private int layerCount;
    private int nodeCount;
    private LocalDateTime timestamp;
    private Map<String, Object> metadata;  // 仿真配置快照
}

// 计量服务：每小时聚合 RocketMQ 事件写入 usage_aggregation 表
@Service
public class UsageAggregationService {

    @RocketMQMessageListener(topic = "nsca-usage-events", consumerGroup = "usage-aggregator")
    public void onUsageEvent(TickUsageEvent event) {
        // 按小时分桶聚合
        String bucketKey = event.getUserId() + ":" +
            event.getTimestamp().format(DateTimeFormatter.ofPattern("yyyyMMddHH"));
        redisTemplate.opsForHash().increment(bucketKey, "totalTicks", event.getTickCount());
        redisTemplate.opsForHash().increment(bucketKey, "totalRuns", 1);
        // 每小时批量写入 MySQL usage_aggregation 表
    }
}
```

**存储计量**：
- 每日凌晨 XXL-JOB（yudao 已集成）定时任务扫描用户项目存储占用
- 计算：项目文件 + 审计日志 + 分支快照 + 导出报告
- 压缩策略：30 天前的审计日志自动归档至冷存储（费用 1/10）

## 6.6 超额计费与保护

**超额策略**：

| 场景 | 行为 |
|------|------|
| Tick 配额耗尽 | 阻止新仿真启动，提示升级或购买增量包 |
| 存储超额 10% | 邮件告警，允许继续 7 天 |
| 存储超额 20% | 阻止新项目创建，只读模式 |
| API 配额耗尽 | 返回 429，提示升级 |
| 订阅到期 | 7 天宽限期，之后降级至免费版 |

**增量包 (Top-up)**：
```yaml
# POST /api/v1/billing/topup
request:
  topup_type: string       # tick_pack | storage_pack | api_pack
  amount: int

available_packs:
  tick_pack:
    - name: "10万 Tick"
      amount: 100000
      price_usd: 5
    - name: "100万 Tick"
      amount: 1000000
      price_usd: 35
  storage_pack:
    - name: "10 GB"
      amount: 10
      price_usd: 2
```

**欠费保护**：
- 自动扣款失败 → 邮件通知 → 24 小时后重试 → 连续 3 次失败进入 past_due
- Past due 7 天内：功能降级，数据保留
- Past due 30 天：账户冻结，只读导出
- Past due 90 天：数据归档（保留 1 年可恢复）

## 6.7 配额实时守护

```java
// NSCA 新增 QuotaGuard（复用 Redisson 分布式锁防并发）
@Service
public class QuotaGuard {

    private final RedissonClient redisson;  // yudao 已集成
    private final RedisTemplate<String, Object> redis;

    public QuotaCheckResult canStartSimulation(
            Long userId, int estimatedTicks, boolean isMonteCarlo) {

        String lockKey = "quota:lock:" + userId;
        RLock lock = redisson.getLock(lockKey);

        try {
            lock.lock(5, TimeUnit.SECONDS);

            // 1. 查询实时可用配额（Redis 缓存）
            QuotaAvailable available = getAvailableQuota(userId);

            // 2. 检查
            if (available.getTicks() < estimatedTicks) {
                return QuotaCheckResult.denied("Tick配额不足", "pro", "100万 Tick包");
            }

            // 3. 预扣（Redis，TTL=3600s，防并发超额）
            redis.opsForValue().decrement("quota:ticks:" + userId, estimatedTicks);
            String reservationId = UUID.randomUUID().toString();
            redis.opsForHash().put("quota:reservation:" + userId, reservationId,
                                   String.valueOf(estimatedTicks));
            redis.expire("quota:reservation:" + userId, 3600, TimeUnit.SECONDS);

            return QuotaCheckResult.allowed(reservationId);

        } finally {
            lock.unlock();
        }
    }

    public void commitUsage(Long userId, String reservationId, int actualTicks) {
        // 仿真结束后释放预留 + 确认实际消耗
        redis.opsForHash().delete("quota:reservation:" + userId, reservationId);
        // 差额回补
        int reserved = getReservedAmount(userId, reservationId);
        if (actualTicks < reserved) {
            redis.opsForValue().increment("quota:ticks:" + userId, reserved - actualTicks);
        }
    }
}
```

## 6.8 发票与税务

```java
// NSCA 新增 InvoiceDO（复用 yudao BaseDO 基础字段）
@TableName("billing_invoice")
public class InvoiceDO extends BaseDO {
    private Long id;
    private Long userId;
    private Long subscriptionId;
    private String invoiceType;     // subscription | topup | overage
    private String status;          // draft | open | paid | void
    private String currency;
    private BigDecimal subtotal;
    private BigDecimal tax;
    private BigDecimal total;
    private String lineItems;       // JSON
    private LocalDateTime dueDate;
    private LocalDateTime paidAt;
    private String stripeInvoiceId;
}
```

**税务处理**：
- 美国：根据账单地址计算州税（Stripe Tax 自动处理）
- 中国：增值税电子普通发票，6% 税率
- 欧盟：VAT MOSS 处理
- 企业客户：支持 PO（采购订单）流程，账期 30 天

## 6.9 接口契约

```yaml
# GET /api/v1/billing/subscription (复用 yudao member_user.levelId)
response_200:
  plan_id: string
  plan_name: string
  status: string              # 来自 user_subscription.status
  current_period_start: datetime
  current_period_end: datetime
  cancel_at_period_end: boolean
  payment_method:
    type: string
    last4: string
    brand: string

# GET /api/v1/billing/usage
request:
  start_date: date?
  end_date: date?

response_200:
  period: string
  tick_used: int
  tick_limit: int
  tick_percentage: float
  storage_used_gb: float
  storage_limit_gb: float
  api_calls: int
  api_limit: int
  monte_carlo_used: int
  monte_carlo_limit: int
  daily_breakdown:
    - date: date
      ticks: int
      api_calls: int

# GET /api/v1/billing/invoices
response_200:
  invoices:
    - invoice_id: string
      amount: string
      currency: string
      status: string
      created_at: datetime
      pdf_url: string?

# POST /api/v1/billing/change-plan
request:
  plan_id: string           # 对应 member_level.id
  billing_cycle: string     # monthly | yearly

# 升级：立即生效，按比例计费。降级：当前周期结束后生效。

# POST /api/v1/billing/cancel
request:
  cancel_at_period_end: boolean
```

## 6.10 计费事件流

> 复用 yudao 已集成的 RocketMQ。事件 Topic: `nsca-billing-events`。

```yaml
billing.subscription.created:
  user_id: Long
  plan_id: Long
  amount: Decimal

billing.subscription.cycled:
  user_id: Long
  plan_id: Long
  period_start: datetime
  period_end: datetime
  amount: Decimal

billing.usage.threshold.reached:
  user_id: Long
  metric: string             # ticks | storage | api
  percentage: float          # 0.8 | 0.9 | 1.0

billing.overage.charged:
  user_id: Long
  metric: string
  quantity: int
  unit_price: Decimal
  amount: Decimal

billing.payment.failed:
  user_id: Long
  invoice_id: Long
  failure_code: string
  retry_count: int

billing.points.redeemed:
  user_id: Long
  points_redeemed: int
  redeemed_for: string       # subscription | token_topup
  equivalent_value: Decimal
  currency: string
```

---

## 6.11 RP 积分系统（Research Points）

> yudao `member_point_record` 表使用 Integer 单余额模型（字段: `userId`, `point`, `totalPoint`, `bizType`, `bizId`），适合简单的积分场景。RP 积分的 FIFO 批次追踪、12 个月有效期、每日 0.1% 衰减、BigDecimal 精度要求与 yudao 单余额模型根本不同，需新增独立表族。

### 6.11.1 RP 数据模型

```sql
-- NSCA 新增：RP 账户表
CREATE TABLE rp_account (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id         BIGINT NOT NULL COMMENT '关联 member_user.id',
    balance         DECIMAL(16,4) NOT NULL DEFAULT 0 COMMENT '当前可用余额',
    total_earned    DECIMAL(16,4) NOT NULL DEFAULT 0 COMMENT '历史累计获得',
    total_redeemed  DECIMAL(16,4) NOT NULL DEFAULT 0 COMMENT '历史累计兑换',
    daily_earned    DECIMAL(16,4) NOT NULL DEFAULT 0 COMMENT '今日已获 RP',
    daily_date      DATE COMMENT '每日获得日期（用于重置 daily_earned）',
    frozen_balance  DECIMAL(16,4) NOT NULL DEFAULT 0 COMMENT '冻结余额（风控）',
    last_activity_at DATETIME,
    created_at      DATETIME NOT NULL,
    updated_at      DATETIME,
    FOREIGN KEY (user_id) REFERENCES member_user(id),
    UNIQUE KEY uk_user (user_id)
);

-- NSCA 新增：RP 批次表（FIFO 过期追踪）
CREATE TABLE rp_lot (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    account_id      BIGINT NOT NULL COMMENT '关联 rp_account.id',
    amount          DECIMAL(16,4) NOT NULL COMMENT '原始获得数量',
    remaining       DECIMAL(16,4) NOT NULL COMMENT '剩余未消费数量',
    source          VARCHAR(50) NOT NULL COMMENT '来源: project_score | merge_bonus | sign_in 等',
    source_id       BIGINT COMMENT '来源对象ID',
    acquired_at     DATETIME NOT NULL COMMENT '获得时间',
    expires_at      DATETIME NOT NULL COMMENT '过期时间 (acquired_at + 12个月)',
    created_at      DATETIME NOT NULL,
    FOREIGN KEY (account_id) REFERENCES rp_account(id),
    INDEX idx_account_remaining (account_id, remaining),
    INDEX idx_expires (expires_at)
);

-- NSCA 新增：RP 交易记录表（替代 yudao member_point_record 承载 RP 交易）
CREATE TABLE rp_transaction (
    id              BIGINT PRIMARY KEY AUTO_INCREMENT,
    account_id      BIGINT NOT NULL COMMENT '关联 rp_account.id',
    type            VARCHAR(20) NOT NULL COMMENT 'earn | consume | expire | decay | adjust',
    amount          DECIMAL(16,4) NOT NULL COMMENT '正数=获得，负数=消费',
    balance_after   DECIMAL(16,4) NOT NULL COMMENT '交易后余额',
    source          VARCHAR(50) NOT NULL COMMENT '来源/去向标识',
    source_id       BIGINT COMMENT '关联对象ID',
    lot_id          BIGINT COMMENT '关联 rp_lot.id（消费时记录批次）',
    description     VARCHAR(500),
    created_at      DATETIME NOT NULL,
    FOREIGN KEY (account_id) REFERENCES rp_account(id),
    FOREIGN KEY (lot_id) REFERENCES rp_lot(id),
    INDEX idx_account_created (account_id, created_at),
    INDEX idx_type (type, created_at)
);
```

**与 yudao `member_point_record` 的对比**：

| 维度 | yudao `member_point_record` | NSCA `rp_transaction` + `rp_lot` |
|------|---------------------------|----------------------------------|
| 余额模型 | Integer 单余额 (`point`, `totalPoint`) | BigDecimal 多批次 FIFO (`rp_account.balance` + `rp_lot.remaining`) |
| 精度 | 整数 | DECIMAL(16,4)（支持极小量衰减） |
| 有效期 | 无 | 12 个月 FIFO，`rp_lot.expires_at` |
| 衰减 | 无 | 每日 0.1%，逐 lot 扣减 |
| 业务枚举 | 6 种 (`bizType`: SIGN/ADMIN/ORDER_* 等) | 扩展为 12+ 种（见下表） |
| 并发控制 | 乐观锁（version） | Redis 分布式锁（Redisson，yudao 已集成） |

### 6.11.2 RP 业务枚举（扩展 yudao MemberPointBizTypeEnum）

```java
// NSCA 新增 RP 业务类型（在 yudao MemberPointBizTypeEnum 基础上扩展）
public enum RpBizType {
    // 获得
    PROJECT_SCORE("project_score", "项目评分奖励"),
    MERGE_BONUS("merge_bonus", "合并奖励"),
    DAILY_SIGN_IN("daily_sign_in", "每日签到"),
    STARS_RECEIVED("stars_received", "被星标奖励"),
    FORK_REWARD("fork_reward", "被 Fork 奖励"),
    REVIEW_APPROVED("review_approved", "审核通过"),
    // 消费
    SIMULATION_CONSUME("simulation_consume", "仿真消耗"),
    MONTE_CARLO_CONSUME("monte_carlo_consume", "蒙特卡洛消耗"),
    TOKEN_PURCHASE("token_purchase", "LLM Token 购买"),
    STORAGE_PURCHASE("storage_purchase", "存储扩容"),
    // 系统
    DAILY_DECAY("daily_decay", "每日衰减"),
    EXPIRY("expiry", "过期清算"),
    ADMIN_ADJUST("admin_adjust", "管理员调整");
}
```

### 6.11.3 FIFO 消费核心逻辑

```java
@Service
public class RpConsumptionService {

    public RpConsumeResult consume(Long accountId, BigDecimal amount,
                                    String source, Long sourceId) {

        // 1. 获取分布式锁（Redisson，yudao 已集成）
        RLock lock = redisson.getLock("rp:consume:" + accountId);
        try {
            lock.lock(3, TimeUnit.SECONDS);

            RpAccountDO account = rpAccountMapper.selectById(accountId);
            if (account.getBalance().compareTo(amount) < 0) {
                throw new InsufficientRpException(account.getBalance(), amount);
            }

            // 2. 查询未过期的可用 lot，按 acquired_at ASC（FIFO）
            List<RpLotDO> availableLots = rpLotMapper.selectAvailableLots(
                accountId, LocalDateTime.now());

            // 3. 逐 lot 扣减，直到满足消费金额
            BigDecimal remaining = amount;
            List<LotConsumption> consumptions = new ArrayList<>();

            for (RpLotDO lot : availableLots) {
                BigDecimal deduct = remaining.min(lot.getRemaining());
                lot.setRemaining(lot.getRemaining().subtract(deduct));
                rpLotMapper.updateRemaining(lot.getId(), lot.getRemaining());

                consumptions.add(new LotConsumption(lot.getId(), deduct));
                remaining = remaining.subtract(deduct);
                if (remaining.compareTo(BigDecimal.ZERO) <= 0) break;
            }

            // 4. 更新账户余额
            account.setBalance(account.getBalance().subtract(amount));
            account.setLastActivityAt(LocalDateTime.now());
            rpAccountMapper.updateBalance(account.getId(), account.getBalance());

            // 5. 创建交易记录
            RpTransactionDO tx = new RpTransactionDO();
            tx.setAccountId(accountId);
            tx.setType("consume");
            tx.setAmount(amount.negate());
            tx.setBalanceAfter(account.getBalance());
            tx.setSource(source);
            tx.setSourceId(sourceId);
            tx.setCreatedAt(LocalDateTime.now());
            rpTransactionMapper.insert(tx);

            return new RpConsumeResult(consumptions, amount, account.getBalance());

        } finally {
            lock.unlock();
        }
    }
}
```

### 6.11.4 每日衰减计算（XXL-JOB 定时任务）

> yudao 已集成 XXL-JOB。NSCA 注册定时任务，每日凌晨 3:00 执行。

```
RP_day = Σ(ProjectScore) + MergeBonus - ReputationDecay

ProjectScore = (stars × 10 + quality_comments × 30 + views × 0.01 + forks × 50)
               × project_age_factor
               × quality_multiplier

project_age_factor = max(0.5, 1 - (days_since_publish / 180))
quality_multiplier = 1.0 + (health_score / 100)
MergeBonus = Σ(merged_prs × 500 × impact_weight)
ReputationDecay = -balance × 0.001  (每日 0.1%)
```

```java
@Component
public class RpDailyDecayJob {

    private static final BigDecimal DECAY_RATE = new BigDecimal("0.001");  // 0.1%

    @XxlJob("rpDailyDecay")  // XXL-JOB 调度
    public void execute() {
        // 批量处理所有活跃账户，按 lot 逐 lot 衰减
        List<RpAccountDO> activeAccounts = rpAccountMapper.selectActiveAccounts();

        for (RpAccountDO account : activeAccounts) {
            List<RpLotDO> lots = rpLotMapper.selectAvailableLots(
                account.getId(), LocalDateTime.now());

            BigDecimal totalDecay = BigDecimal.ZERO;
            for (RpLotDO lot : lots) {
                BigDecimal decay = lot.getRemaining().multiply(DECAY_RATE)
                    .setScale(4, RoundingMode.HALF_UP);
                if (decay.compareTo(new BigDecimal("0.0001")) <= 0) continue;

                lot.setRemaining(lot.getRemaining().subtract(decay));
                rpLotMapper.updateRemaining(lot.getId(), lot.getRemaining());
                totalDecay = totalDecay.add(decay);

                rpTransactionMapper.insert(RpTransactionDO.builder()
                    .accountId(account.getId()).type("decay")
                    .amount(decay.negate()).lotId(lot.getId())
                    .description("每日衰减").createdAt(LocalDateTime.now())
                    .build());
            }

            account.setBalance(account.getBalance().subtract(totalDecay));
            rpAccountMapper.updateBalance(account.getId(), account.getBalance());
        }
    }
}
```

### 6.11.5 防刷机制

- **同一 IP/IP 段星标去重**：Redis Set (`rp:star:{projectId}:ips`)，TTL=24h
- **短时间内批量 Fork 频率限制**：滑动窗口 (Redisson `RScoredSortedSet`)，10次/小时
- **评论 NLP 质量评分**：BERT 分类器，阈值 0.6
- **每日总获得上限**：`rp_account.daily_earned` ≤ 2000 RP
- **异常模式检测**（如短时间内大量自 Fork）→ 冻结 `rp_account.frozen_balance`，人工审核

### 6.11.6 RP 兑换

```yaml
# GET /api/v1/billing/points (查询 RP 余额)
response_200:
  balance: string           # BigDecimal
  total_earned: string
  total_redeemed: string
  upcoming_expiry:
    - expire_date: date
      amount: string
  recent_transactions:
    - type: string
      amount: string
      description: string
      created_at: datetime

# POST /api/v1/billing/points/redeem
request:
  redemption_type: string   # subscription | tick_topup | token_topup | storage_topup
  amount_points: int        # 要兑换的积分数
  target_resource_id: string?

response_200:
  redeemed_points: int
  equivalent_value: string
  currency: string

# POST /api/v1/billing/checkout
# 升级会员时，支持积分+现金混合支付
request:
  plan_id: string            # member_level.id
  billing_cycle: string
  points_to_redeem: int
  payment_method_id: string  # Stripe/Jeepay

response_200:
  order_id: string
  cash_amount: string        # 扣除积分抵扣后的现金金额
  points_redeemed: int
  checkout_url: string?      # 第三方支付跳转URL
```

**兑换比例**（来自需求文档）：

| 货币 | 1 个单位 = RP |
|------|--------------|
| 1 CNY | 10 RP |
| 1 USD | 70 RP |

## 6.12 yudao 扩展总览

| yudao 原有 | 方式 | NSCA 扩展 |
|-----------|------|----------|
| `member_level` 表 | 新增字段 | `price_monthly`, `price_yearly`, `currency`, `features(JSON)` |
| `member_user.levelId` | 直接复用 | 表示用户当前订阅计划 |
| `member_user.point` | 保留并行 | yudao 简单积分 + NSCA `rp_account` RP 积分 |
| `member_point_record` 表 | 扩展 bizType + 新增表 | 保留 yudao 流水 + 新增 `rp_transaction` |
| — | **新增表** | `user_subscription`, `rp_account`, `rp_lot`, `rp_transaction`, `billing_invoice` |
| — | **新增 Service** | `SubscriptionService`, `RpAccountService`, `RpConsumptionService`, `QuotaGuard` |
| `MemberPointRecordService` | 扩展 | 新增 RP 相关 `bizType` 枚举值 |
| XXL-JOB (yudao 已有) | 新增任务 | `rpDailyDecay`（每日衰减）, `rpExpiryCheck`（过期清算） |
| RocketMQ (yudao 已有) | 新增 Topic | `nsca-billing-events`, `nsca-usage-events` |
| Redisson (yudao 已有) | 直接复用 | RP 消费分布式锁、配额预扣锁 |

---

## 参考

- [yudao 会员等级文档](https://doc.iocoder.cn/member/level/)
- [Stripe Billing API](https://docs.stripe.com/billing)
- [RocketMQ Spring 文档](https://github.com/apache/rocketmq-spring)
