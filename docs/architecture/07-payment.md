## 07. 支付集成架构

### 07.1 设计原则

**多渠道覆盖**：同时支持国际信用卡（Stripe）和中国本土支付（支付宝、微信支付），根据用户地理位置自动推荐最优渠道。

**支付安全**：全渠道 PCI DSS 合规，敏感支付信息永不触碰应用服务器，全部由支付提供商托管。

**失败韧性**：支付失败自动重试（指数退避），关键失败人工介入，用户始终收到明确反馈。

### 07.2 支付渠道架构

```
┌─────────────────────────────────────────────────────────────────┐
│                      支付服务 (Payment Service)                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐│
│   │  渠道路由    │  │  订单管理    │  │  对账与退款              ││
│   │             │  │             │  │                         ││
│   │ 根据用户地区 │  │ 创建支付订单 │  │ 自动对账每日运行          ││
│   │ 智能选择渠道 │  │ 状态机管理   │  │ 退款 7 个工作日到账       ││
│   │ 失败自动切换 │  │ 幂等性保证   │  │ 争议处理工单系统          ││
│   └──────┬──────┘  └──────┬──────┘  └────────────┬────────────┘│
│          └─────────────────┴──────────────────────┘             │
│                               │                                 │
│          ┌────────────────────┼────────────────────┐            │
│          ▼                    ▼                    ▼            │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐      │
│   │   Stripe    │     │  支付宝      │     │  微信支付    │      │
│   │             │     │             │     │             │      │
│   │ 国际信用卡   │     │ 扫码/网页    │     │ JSAPI/Native│      │
│   │ 订阅管理     │     │ 手机网站     │     │ H5/小程序   │      │
│   │ Webhook     │     │ 异步通知     │     │ 异步通知     │      │
│   └─────────────┘     └─────────────┘     └─────────────┘      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 07.3 支付渠道详情

**Stripe（国际）**：
- 支持：Visa、MasterCard、AmEx、JCB、Diners Club
- 订阅：Stripe Subscription + Customer Portal
- 税务：Stripe Tax 自动计算销售税/VAT
- 发票：Stripe Invoicing 自动生成 PDF
- Webhook 事件：`invoice.paid`、`invoice.payment_failed`、`customer.subscription.updated`

**支付宝（中国）**：
- 支持：PC 网站支付、手机网站支付、扫码支付
- 流程：创建订单 → 返回支付表单/二维码 → 用户支付 → 异步通知 → 更新订单
- 对账：每日凌晨下载支付宝对账单，与系统订单核对

**微信支付（中国）**：
- 支持：JSAPI（微信内）、Native（扫码）、H5（外部浏览器）
- 流程：统一下单 → 返回调起参数 → 用户支付 → 异步通知
- 对账：每日自动下载微信对账单

### 07.4 支付订单状态机

```
┌─────────┐    创建订单    ┌─────────┐    用户支付    ┌─────────┐
│  INIT   │ ─────────────→│ PENDING │ ─────────────→│ SUCCESS │
└─────────┘               └─────────┘               └────┬────┘
                              │                         │
                              │ 超时/取消                │ 退款
                              ▼                         ▼
                         ┌─────────┐               ┌─────────┐
                         │CANCELLED│               │REFUNDED │
                         └─────────┘               └─────────┘
                              │
                              │ 支付失败
                              ▼
                         ┌─────────┐    重试      ┌─────────┐
                         │ FAILED  │ ───────────→ │ PENDING │
                         └─────────┘              └─────────┘
```

### 07.5 渠道路由策略

```python
class PaymentRouter:
    def select_channel(self, user: User, amount: Decimal) -> PaymentChannel:
        # 1. 根据用户地区初筛
        if user.country == "CN":
            candidates = [Alipay, WeChatPay]
        else:
            candidates = [Stripe]

        # 2. 检查渠道可用性
        available = [c for c in candidates if c.is_healthy()]

        # 3. 根据金额选择（大额优先 Stripe 企业支付）
        if amount > 1000 and Stripe in available:
            return Stripe

        # 4. 默认首选
        return available[0]

    def fallback(self, failed_channel: PaymentChannel, user: User) -> PaymentChannel:
        """支付失败时切换到备用渠道"""
        pass
```

### 07.6 订阅生命周期

```
用户选择计划
    ↓
创建 Stripe Subscription / 支付宝周期扣款签约
    ↓
首次扣款成功 → 订阅激活
    ↓
每月/每年自动续费
    ├── 扣款成功 → 发送发票 → 更新订阅周期
    ├── 扣款失败 → 重试 D+1, D+3, D+5
    │       └── 3 次失败 → 进入 past_due → 邮件通知
    └── 用户主动取消 → cancel_at_period_end = true
                ↓
        周期结束 → 降级至免费版
```

### 07.7 退款策略

> 退款业务规则（场景、比例、时效）详见需求文档 `01-users-concepts.md`。

退款接口统一返回 `Refund` 对象，状态机：`pending → succeeded / failed`。

### 07.8 Webhook 处理

**Stripe Webhooks**：
```python
STRIPE_WEBHOOK_EVENTS = [
    "invoice.paid",                    # 发票支付成功
    "invoice.payment_failed",          # 发票支付失败
    "customer.subscription.created",   # 订阅创建
    "customer.subscription.updated",   # 订阅更新（计划切换、取消）
    "customer.subscription.deleted",   # 订阅删除
    "charge.refunded",                 # 退款完成
    "charge.dispute.created",          # 争议发起
]

class StripeWebhookHandler:
    def handle(self, payload: dict, signature: str):
        # 1. 验证签名
        event = stripe.Webhook.construct_event(payload, signature, endpoint_secret)

        # 2. 幂等性检查
        if self.is_processed(event.id):
            return "ok"

        # 3. 分发处理
        handler = self.get_handler(event.type)
        handler(event.data.object)

        # 4. 标记已处理
        self.mark_processed(event.id)
```

**支付宝/微信异步通知**：
- 验签 → 查询订单状态 → 更新本地订单 → 返回 success
- 通知失败时支付渠道会重试，需保证幂等性

### 07.9 接口契约

```yaml
# POST /api/v1/payments/create-intent
request:
  amount: string            # 金额，如 "29.00"
  currency: string          # USD | CNY
  description: string       # 订阅专业版 - 月付
  metadata:
    user_id: string
    plan_id: string
    billing_cycle: string

response_200:
  client_secret: string     # Stripe client_secret
  payment_form: object      # 支付宝/微信表单参数
  channel: string           # stripe | alipay | wechat
  order_id: string

# POST /api/v1/payments/webhook/stripe
# Stripe Webhook 端点，验证签名后处理

# POST /api/v1/payments/webhook/alipay
# 支付宝异步通知端点

# POST /api/v1/payments/webhook/wechat
# 微信支付异步通知端点

# POST /api/v1/payments/refund
request:
  payment_id: string
  amount: string?           # 部分退款时指定
  reason: string

response_200:
  refund_id: string
  status: string            # pending | succeeded | failed

# GET /api/v1/payments/methods
response_200:
  methods:
    - id: string
      type: string           # card | alipay | wechat
      brand: string?         # visa | mastercard
      last4: string?
      expiry_month: int?
      expiry_year: int?
      is_default: boolean
```

### 07.10 对账机制

**日对账流程**：
```
每日凌晨 03:00
    ↓
下载渠道对账单（Stripe / 支付宝 / 微信）
    ↓
与系统订单表比对
    ↓
生成差异报告
    ├── 一致 → 归档
    ├── 系统有，渠道无 → 标记异常，人工核查
    ├── 渠道有，系统无 → 补录订单
    └── 金额不一致 → 标记争议，人工核查
```

**监控告警**：
- 对账差异 > 0.1% → 立即告警
- 单日退款率 > 5% → 运营介入
- 争议率 > 1% → 风控审查
