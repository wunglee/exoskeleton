## 06. 计费系统架构

### 06.1 设计原则

**透明可预测**：用户在执行任何消耗性操作前，系统预估并展示本次消耗；计费明细精确到单个 Tick，杜绝黑盒。

**混合计费模式**：基础功能订阅制（包月/包年），超额资源按量计费，兼顾可预测性与灵活性。

**实时配额守护**：每个仿真启动前校验配额，执行中监控消耗，接近上限时主动告警，杜绝超额透支。

**多币种支持**：企业客户支持合同币种（USD/CNY/EUR），个人用户按地区默认币种，汇率每日更新。

### 06.2 计费维度

系统对以下维度进行计量与计费（各计划具体配额详见需求文档 `01-users-concepts.md`）：

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

### 06.3 计费模型

```
┌─────────────────────────────────────────────────────────────────┐
│                        计费服务 (Billing Service)                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ 订阅管理     │  │ 计量采集     │  │ 超额计费                 │ │
│  │ - 计划切换   │  │ - Tick 计数  │  │ - 阶梯单价               │ │
│  │ - 周期结算   │  │ - 存储统计   │  │ - 自动扣款               │ │
│  │ - 优惠券     │  │ - API 计量   │  │ - 欠费保护               │ │
│  └──────┬──────┘  └──────┬──────┘  └────────────┬────────────┘ │
│         └─────────────────┴──────────────────────┘              │
│                              │                                  │
│                    ┌─────────┴─────────┐                        │
│                    │   配额管理器       │                        │
│                    │   (Quota Manager)  │                        │
│                    │                    │                        │
│                    │ 实时可用 = 订阅配额 │                        │
│                    │          + 购买包   │                        │
│                    │          - 已用     │                        │
│                    │          - 预留     │                        │
│                    └─────────┬─────────┘                        │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────┐     │
│  │                           ▼                           │     │
│  │              计费数据库 (PostgreSQL + 分区)             │     │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  │     │
│  │  │订阅记录  │  │计量明细  │  │发票记录  │  │配额快照  │  │     │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘  │     │
│  └───────────────────────────────────────────────────────┘     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 06.4 订阅计划

```python
class SubscriptionPlan:
    plan_id: str                    # free | pro | team | enterprise
    name: str                       # 免费版 / 专业版 / 团队版 / 企业版
    billing_cycle: str              # monthly | yearly
    price_monthly: Decimal          # 月付价格
    price_yearly: Decimal           # 年付价格（约 8.3 折）
    currency: str                   # USD | CNY
    features: Dict[str, Any]        # 功能开关与配额
    is_active: bool

class UserSubscription:
    subscription_id: UUID
    user_id: UUID
    plan_id: str
    status: str                     # active | cancelled | paused | past_due
    current_period_start: datetime
    current_period_end: datetime
    cancel_at_period_end: bool
    payment_method_id: UUID?
    created_at: datetime
```

### 06.5 计量采集机制

**Tick 计量**：
- TickEngine 每完成一个 tick，异步发送计量事件到 Kafka
- 计量服务按用户聚合，写入时序数据库（TimescaleDB）
- 粒度：用户级、项目级、仿真运行级

```python
class TickUsageEvent:
    event_id: UUID
    user_id: UUID
    project_id: UUID
    run_id: UUID
    tick_count: int                 # 本次消耗的 tick 数
    layer_count: int                # 涉及的层数
    node_count: int                 # 扫描的节点数
    timestamp: datetime
    metadata: Dict                  # 仿真配置快照

class UsageAggregation:
    # 每小时聚合一次
    hour_bucket: datetime
    user_id: UUID
    total_ticks: int
    total_simulation_runs: int
    total_monte_carlo_runs: int
    storage_gb: float
    api_calls: int
```

**存储计量**：
- 每日凌晨扫描用户项目存储占用
- 计算：项目文件 + 审计日志 + 分支快照 + 导出报告
- 压缩策略：30 天前的审计日志自动归档至冷存储（费用 1/10）

### 06.6 超额计费与保护

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
  amount: int              # 数量

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

### 06.7 配额实时守护

```python
class QuotaGuard:
    """仿真启动前的配额检查"""

    def can_start_simulation(
        self,
        user_id: UUID,
        estimated_ticks: int,
        is_monte_carlo: bool = False
    ) -> QuotaCheckResult:
        # 1. 查询实时可用配额
        available = self.get_available_quota(user_id)

        # 2. 检查是否满足
        if available.ticks < estimated_ticks:
            return QuotaCheckResult(
                allowed=False,
                reason="Tick配额不足",
                required_tier="pro",
                suggested_topup="100万 Tick包"
            )

        # 3. 预扣配额（避免并发超额）
        self.reserve_quota(user_id, estimated_ticks, ttl=3600)

        return QuotaCheckResult(allowed=True)

    def release_reservation(self, user_id: UUID, reservation_id: UUID):
        """仿真完成或取消时释放预留"""
        pass

    def commit_usage(self, user_id: UUID, actual_ticks: int):
        """仿真结束后确认实际消耗"""
        pass
```

### 06.8 发票与税务

```python
class Invoice:
    invoice_id: UUID
    user_id: UUID
    subscription_id: UUID?
    invoice_type: str           # subscription | topup | overage
    status: str                 # draft | open | paid | void
    currency: str
    subtotal: Decimal           # 小计
    tax: Decimal                # 税费
    total: Decimal              # 总计
    line_items: List[LineItem]
    due_date: datetime
    paid_at: datetime?
    stripe_invoice_id: str?     # 外部系统 ID

class LineItem:
    description: str
    quantity: int
    unit_price: Decimal
    amount: Decimal
    period_start: datetime?
    period_end: datetime?
```

**税务处理**：
- 美国：根据账单地址计算州税（Stripe Tax 自动处理）
- 中国：增值税电子普通发票，6% 税率
- 欧盟：VAT MOSS 处理
- 企业客户：支持 PO（采购订单）流程，账期 30 天

### 06.9 接口契约

```yaml
# GET /api/v1/billing/subscription
response_200:
  plan_id: string
  plan_name: string
  status: string
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
  plan_id: string           # pro | team | enterprise
  billing_cycle: string     # monthly | yearly

# 升级：立即生效，按比例计费
# 降级：当前周期结束后生效

# POST /api/v1/billing/cancel
request:
  cancel_at_period_end: boolean  # true: 周期结束取消；false: 立即取消并退款
```

### 06.10 计费事件流

```yaml
# 发送至 Kafka topic: billing.events
billing.subscription.created:
  user_id: UUID
  plan_id: string
  amount: Decimal

billing.subscription.cycled:
  user_id: UUID
  plan_id: string
  period_start: datetime
  period_end: datetime
  amount: Decimal

billing.usage.threshold.reached:
  user_id: UUID
  metric: string             # ticks | storage | api
  percentage: float          # 0.8 | 0.9 | 1.0

billing.overage.charged:
  user_id: UUID
  metric: string
  quantity: int
  unit_price: Decimal
  amount: Decimal

billing.payment.failed:
  user_id: UUID
  invoice_id: UUID
  failure_code: string
  retry_count: int

billing.points.redeemed:
  user_id: UUID
  points_redeemed: int
  redeemed_for: string      # subscription | token_topup
  equivalent_value: Decimal
  currency: string
```

---

### 06.11 研究积分系统（Research Points）

> 积分业务规则（来源明细、兑换比例、价值锚定）详见需求文档 `01-users-concepts.md`。

**积分生成算法**（每日批次计算）：

```
RP_day = Σ(ProjectScore) + MergeBonus + ReputationDecay

ProjectScore = (stars × 10 + quality_comments × 30 + views × 0.01 + forks × 50)
               × project_age_factor
               × quality_multiplier

project_age_factor = max(0.5, 1 - (days_since_publish / 180))
quality_multiplier = 1.0 + (health_score / 100)
MergeBonus = Σ(merged_prs × 500 × impact_weight)
impact_weight: minor=0.5 | moderate=1.0 | major=2.0
ReputationDecay = -balance × 0.001
```

**防刷检测规则**（技术实现层）：
- 同一 IP/设备星标去重（Redis Set，TTL=24h）
- 短时间内批量 Fork 频率限制（滑动窗口，10次/小时）
- 评论 NLP 质量评分（BERT 分类器，阈值 0.6）
- 每日总获得上限硬限制：2000 RP

**积分账户模型**：
```python
class ResearchPointsAccount:
    account_id: UUID
    user_id: UUID
    balance: int                    # 当前可用余额
    total_earned: int               # 历史累计获得
    total_redeemed: int             # 历史累计兑换
    pending: int                    # 待结算（如举报审核中的贡献）
    last_activity_at: datetime

class PointsTransaction:
    transaction_id: UUID
    account_id: UUID
    type: str                       # earn | redeem | expire | adjust
    amount: int                     # 正数 = 获得，负数 = 消费
    balance_after: int
    source: str                     # 来源行为标识
    source_id: UUID?                # 关联对象（项目ID、合并请求ID等）
    description: str
    created_at: datetime
```

**积分有效期**：
- 获得之日起 12 个月有效
- 过期前 30 天邮件提醒
- 优先消耗最早获得的积分（FIFO）

**积分兑换接口**：
```yaml
# GET /api/v1/billing/points
response_200:
  balance: int
  total_earned: int
  total_redeemed: int
  upcoming_expiry:
    - expire_date: date
      amount: int
  recent_transactions:
    - type: string
      amount: int
      description: string
      created_at: datetime

# POST /api/v1/billing/points/redeem
request:
  redemption_type: string    # subscription | tick_topup | token_topup | storage_topup
  amount_points: int         # 要兑换的积分数
  target_resource_id: string?   # 如订阅ID（续费时）

response_200:
  redeemed_points: int
  equivalent_value: string
  currency: string
  result:
    type: string             # subscription_discounted | tick_added | token_added
    detail: object

# POST /api/v1/billing/checkout
# 升级会员时，支持积分+现金混合支付
request:
  plan_id: string
  billing_cycle: string
  points_to_redeem: int      # 0 = 全现金支付
  payment_method_id: string  # Stripe/支付宝/微信

response_200:
  order_id: string
  cash_amount: string         # 扣除积分抵扣后的现金金额
  points_redeemed: int
  checkout_url: string?       # 第三方支付跳转URL
```

**积分防刷机制**：
- 同一项目反复 Fork 仅首次给积分
- 星标积分：同一用户多次取消/重打不计重复
- 每日总获得上限：5000 RP
- 异常模式检测（如短时间内大量自 Fork）→ 冻结积分账户，人工审核
