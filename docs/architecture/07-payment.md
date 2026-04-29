# 07. 支付集成架构

> NSCA 外骨骼基于 yudao-module-pay 的支付渠道体系扩展。yudao 已提供统一的支付订单模型、渠道抽象和 Jeepay 渠道（支付宝/微信支付）。NSCA 新增 Stripe 国际支付渠道，复用 yudao 的订单模型、退款流程、回调通知和对账机制。

## 7.1 设计原则

**基于 yudao 渠道体系扩展**：yudao-module-pay 提供 `PayOrderDO` 统一订单、`PayChannelEnum` 渠道枚举、`PayOrderService` 订单服务、回调通知框架。NSCA 的 Stripe 渠道作为**新增渠道实现**加入该体系，而非替代。

**多渠道覆盖**：yudao Jeepay 渠道覆盖支付宝/微信支付（中国），NSCA Stripe 覆盖国际信用卡。根据用户地理位置自动推荐最优渠道。

**支付安全**：全渠道 PCI DSS 合规，敏感支付信息永不触碰应用服务器，全部由支付提供商托管（Stripe Elements / 支付宝 JSAPI / 微信 JSAPI）。

**失败韧性**：支付失败自动重试（指数退避），关键失败人工介入，用户始终收到明确反馈。

## 7.2 yudao-module-pay 基座

yudao-module-pay 已提供以下能力，NSCA 直接复用：

| yudao 能力 | 实现 | NSCA 策略 |
|-----------|------|----------|
| **统一支付订单** | `PayOrderDO` (id, merchantOrderId, channelCode, price, status, channelOrderNo) | 复用（Stripe 订单写入同一表） |
| **渠道抽象** | `PayClient` 接口 (doUnifiedOrder/doParseOrderNotify/doGetOrder/doRefund) | 新增 `StripePayClient` 实现 |
| **Jeepay 渠道** | `JeepayPayClient`（支付宝/微信支付） | 直接复用 |
| **退款管理** | `PayRefundDO` + `PayRefundService` | 复用 |
| **回调通知** | `PayNotifyService`（验证签名 + 幂等处理 + 订单更新） | 复用 |
| **支付应用** | `PayAppDO`（多应用隔离） | 复用 |

## 7.3 支付渠道架构（扩展后）

```
┌──────────────────────────────────────────────────────────────────────┐
│                    支付服务 (yudao-module-pay 扩展)                     │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  yudao 渠道抽象层（复用）                                               │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  PayClient 接口 ─┬─ JeepayPayClient (yudao 原有)              │   │
│  │                 │     ├─ 支付宝 (PC/扫码/H5)                  │   │
│  │                 │     └─ 微信支付 (JSAPI/Native/H5)           │   │
│  │                 │                                            │   │
│  │                 ├─ MockPayClient (yudao 原有，测试用)          │   │
│  │                 │                                            │   │
│  │                 └─ StripePayClient  ← ★ NSCA 新增             │   │
│  │                       └─ Stripe (国际信用卡 + 订阅管理)        │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  yudao 统一服务层（复用）                                               │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  PayOrderService  │  PayRefundService  │  PayNotifyService    │   │
│  │  (统一订单 + 幂等)   │  (统一退款)         │  (签名验证 + 回调)    │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  存储层                                                               │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  MySQL (yudao pay_order / pay_refund / pay_channel 表族)       │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## 7.4 Stripe 渠道实现（NSCA 新增）

> 实现 yudao 的 `PayClient` 接口，将 Stripe 作为新增支付渠道接入。

```java
// NSCA 新增 StripePayClient，实现 yudao PayClient 接口
@Component
public class StripePayClient implements PayClient {

    @Override
    public PayOrderUnifiedRespDTO doUnifiedOrder(PayOrderUnifiedReqDTO reqDTO) {
        // 创建 Stripe PaymentIntent
        PaymentIntentCreateParams params = PaymentIntentCreateParams.builder()
            .setAmount(reqDTO.getPrice().multiply(new BigDecimal("100")).longValue()) // 分为单位
            .setCurrency(reqDTO.getCurrency().toLowerCase())
            .setDescription(reqDTO.getBody())
            .putMetadata("merchantOrderId", reqDTO.getMerchantOrderId())
            .build();
        PaymentIntent intent = PaymentIntent.create(params);

        return PayOrderUnifiedRespDTO.builder()
            .clientSecret(intent.getClientSecret())
            .displayMode("stripe_elements")  // 前端用 Stripe Elements 渲染
            .build();
    }

    @Override
    public PayOrderRespDTO doParseOrderNotify(PayOrderDO order, String body) {
        // 从 Stripe Webhook 解析支付状态
        // 签名验证已在 PayNotifyService 中完成
        Event event = Event.fromJson(body);
        PaymentIntent intent = (PaymentIntent) event.getDataObjectDeserializer()
            .getObject().orElseThrow();

        return PayOrderRespDTO.builder()
            .channelOrderNo(intent.getId())
            .status(intent.getStatus().equals("succeeded") ? PayStatusEnum.SUCCESS : null)
            .successTime(LocalDateTime.now())
            .build();
    }

    @Override
    public PayOrderRespDTO doRefund(PayOrderDO order, PayRefundDO refund) {
        RefundCreateParams params = RefundCreateParams.builder()
            .setPaymentIntent(order.getChannelOrderNo())
            .setAmount(order.getPrice().multiply(new BigDecimal("100")).longValue())
            .build();
        Refund stripeRefund = Refund.create(params);

        return PayOrderRespDTO.builder()
            .channelOrderNo(stripeRefund.getId())
            .status(stripeRefund.getStatus().equals("succeeded")
                    ? PayStatusEnum.REFUND_SUCCESS : null)
            .build();
    }
}
```

## 7.5 支付订单状态机（复用 yudao PayOrderDO）

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

> 状态机由 yudao `PayOrderDO.status` 驱动，NSCA 不修改状态流转逻辑。

## 7.6 渠道路由策略

```java
// NSCA 新增 PaymentRouter（yudao 无渠道路由，需要按地区智能选择）
@Service
public class PaymentRouter {

    public PayChannelEnum selectChannel(MemberUserDO user, BigDecimal amount) {
        // 1. 中国用户 → Jeepay（支付宝/微信）
        if (isChineseUser(user)) {
            return PayChannelEnum.WX_PUB;  // yudao 已有枚举
        }

        // 2. 国际用户 → Stripe
        return PayChannelEnum.STRIPE;  // NSCA 新增枚举值
    }
}
```

## 7.7 订阅生命周期（Stripe Billing）

```
用户选择计划
    ↓
创建 Stripe Subscription (通过 StripePayClient)
    ↓
首次扣款成功 → 订阅激活 → user_subscription 表更新
    ↓
每月/每年自动续费 (Stripe 侧)
    ├── invoice.paid → Stripe Webhook → 更新 user_subscription 周期
    ├── invoice.payment_failed → 重试 D+1, D+3, D+5
    │       └── 3 次失败 → 进入 past_due → 邮件通知
    └── 用户主动取消 → cancel_at_period_end = true
                ↓
        周期结束 → 降级至免费版 (member_level.id = 1)
```

## 7.8 Webhook 处理

### Stripe Webhook（复用 yudao PayNotifyService）

```java
@RestController
public class StripeWebhookController {

    // Stripe Webhook 端点，复用 yudao PayNotifyService 的幂等性框架
    @PostMapping("/api/v1/pay/webhook/stripe")
    public String handleStripeWebhook(@RequestBody String payload,
                                       @RequestHeader("Stripe-Signature") String sigHeader) {
        // 1. 验证签名
        Event event = Webhook.constructEvent(payload, sigHeader, stripeEndpointSecret);

        // 2. 幂等性检查（复用 yudao PayNotifyService）
        if (payNotifyService.isProcessed(event.getId())) return "ok";

        // 3. 分发处理
        switch (event.getType()) {
            case "invoice.paid"          -> handleInvoicePaid(event);
            case "invoice.payment_failed"-> handlePaymentFailed(event);
            case "customer.subscription.updated" -> handleSubscriptionUpdated(event);
            case "customer.subscription.deleted" -> handleSubscriptionDeleted(event);
            case "charge.refunded"       -> handleRefund(event);
            case "charge.dispute.created"-> handleDispute(event);
        }

        // 4. 标记已处理
        payNotifyService.markProcessed(event.getId());
        return "ok";
    }
}
```

### 支付宝/微信异步通知（复用 yudao Jeepay 回调）

yudao Jeepay 已实现支付宝和微信支付的异步通知处理，NSCA 无需额外代码。

## 7.9 接口契约

```yaml
# POST /api/v1/pay/create-intent (挂载在 yudao-module-pay Controller)
request:
  amount: string            # 金额
  currency: string          # USD | CNY
  description: string       # 订阅专业版 - 月付
  channel: string           # stripe | alipay | wechat (对应 yudao PayChannelEnum)
  metadata:
    user_id: string
    plan_id: string

response_200:
  client_secret: string     # Stripe 返回 client_secret
  payment_form: object      # Jeepay 返回支付表单参数
  channel: string
  order_id: string          # yudao pay_order.id

# POST /api/v1/pay/webhook/stripe (NSCA 新增)
# POST /api/v1/pay/webhook/alipay (复用 yudao Jeepay)
# POST /api/v1/pay/webhook/wechat (复用 yudao Jeepay)

# POST /api/v1/pay/refund (复用 yudao PayRefundService)
request:
  payment_id: string
  amount: string?
  reason: string

response_200:
  refund_id: string
  status: string            # pending | succeeded | failed

# GET /api/v1/pay/methods (复用 yudao)
response_200:
  methods:
    - id: string
      type: string
      brand: string?
      last4: string?
      is_default: boolean
```

## 7.10 对账机制（扩展 yudao 对账）

> yudao 已提供 `PayReconciliationService` 框架。NSCA 新增 Stripe 对账单下载和比对逻辑。

```
每日凌晨 03:00 (XXL-JOB 调度)
    ↓
┌─ Stripe: 下载 Stripe Report → 与 pay_order 比对
├─ Jeepay: 复用 yudao 已有对账逻辑
└─ 生成差异报告
    ├── 一致 → 归档
    ├── 系统有，渠道无 → 标记异常
    ├── 渠道有，系统无 → 补录订单
    └── 金额不一致 → 标记争议
```

**监控告警**：
- 对账差异 > 0.1% → 立即告警
- 单日退款率 > 5% → 运营介入
- 争议率 > 1% → 风控审查

## 7.11 yudao 扩展映射

| yudao 原有 | 方式 | NSCA 扩展 |
|-----------|------|----------|
| `PayClient` 接口 | 新增实现类 | `StripePayClient` |
| `PayChannelEnum` | 新增枚举 | `STRIPE` |
| `PayOrderDO` 表 | 直接复用 | Stripe 订单写入同一表 |
| `PayRefundDO` 表 | 直接复用 | Stripe 退款写入同一表 |
| `PayNotifyService` | 复用幂等框架 | Stripe Webhook 验证 + 分发 |
| `PayReconciliationService` | 扩展 | 新增 Stripe 对账单下载/比对 |
| `JeepayPayClient` | 直接复用 | 支付宝/微信支付不变 |
| — | **新增** | Stripe Customer Portal 集成、Stripe Tax 自动计税 |
| — | **新增依赖** | `stripe-java` 25.x (JDK 8 兼容) |

---

## 参考

- [yudao 支付文档](https://doc.iocoder.cn/pay/build/)
- [Stripe Java SDK](https://github.com/stripe/stripe-java)
- [Stripe Billing API](https://docs.stripe.com/billing)
- [Jeepay 文档](https://www.jeequan.com/)
