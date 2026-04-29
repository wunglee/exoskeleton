# 08. 会员等级架构

> NSCA 外骨骼基于 yudao-module-member 的会员体系扩展。`member_level` 扩展为订阅计划，`member_user.levelId` 表示当前订阅等级，`member_user.experience` 承载荣誉级别晋升，`member_user.tagIds` 承载专家认证徽章，`member_user.groupId` 支持团队版分组。

## 8.1 设计原则

**基于 yudao member 扩展**：yudao-module-member 已提供会员等级/积分/经验/标签/分组五大体系。NSCA 订阅计划和会员体系在此之上扩展，不重写 yudao 核心逻辑。

**价值梯度清晰**：每个等级的价值增量明确可见，用户升级动机强烈，降级落差可控。

**功能门控透明**：未解锁功能明确展示升级路径，不隐藏功能入口（灰显+提示优于完全隐藏）。

**社交激励**：专家认证、贡献徽章、排行榜等社交资本激励，超越纯功能驱动。

**团队扩展**：个人版到团队版的无缝升级，数据、项目、权限平滑迁移。

## 8.2 yudao member 模块基座

yudao-module-member 已提供以下能力，NSCA 扩展使用：

| yudao 能力 | 数据表/实现 | NSCA 扩展策略 |
|-----------|-----------|-------------|
| **会员等级** | `member_level` (id, name, level, experience, discountPercent) | 扩展字段 → 订阅计划 |
| **用户-等级关联** | `member_user.levelId` | 复用 → 当前订阅等级 |
| **积分体系** | `member_user.point` + `member_point_record` | 保留并行（简单积分 + RP 积分） |
| **经验体系** | `member_user.experience` | 复用 → 荣誉级别晋升阈值 |
| **标签体系** | `member_user.tagIds` + `member_tag` | 扩展 → 专家认证徽章 |
| **分组体系** | `member_user.groupId` + `member_group` | 复用 → 团队版用户分组 |

### 8.2.1 扩展映射概览

```
yudao member 表                  NSCA 会员扩展
─────────────────                ─────────────────
member_level                    订阅计划
  ├── name ─────────────────→ 计划名 (Free/Pro/Team/Enterprise)
  ├── level ─────────────────→ 计划等级序号
  ├── experience ────────────→ 荣誉级别晋升阈值 (探索者→首席科学家)
  ├── discountPercent ───────→ 年付折扣
  ├── ★ price_monthly ─────── 新增: 月付价格
  ├── ★ price_yearly ──────── 新增: 年付价格
  ├── ★ currency ──────────── 新增: 币种
  └── ★ features (JSON) ───── 新增: 功能开关与配额

member_user
  ├── levelId ───────────────→ 当前订阅计划
  ├── point ─────────────────→ yudao 简单积分 (保留)
  ├── ★ rp_account ─────────── 新增: RP 积分 (独立表)
  ├── experience ────────────→ 荣誉级别分
  ├── tagIds ────────────────→ 专家认证徽章
  └── groupId ───────────────→ 团队版用户分组
```

## 8.3 会员等级体系

### 8.3.1 订阅计划（扩展 `member_level`）

订阅计划的详细数据模型和 `features` JSON Schema 见 [06-billing.md §6.4](06-billing.md)。

**四级订阅体系**：

| 计划 | member_level.level | member_level.name | 核心定位 |
|------|--------------------|--------------------|---------|
| Free | 1 | 免费版 | 入门研究者，基础功能 |
| Pro | 2 | 专业版 | 独立研究者，全功能 |
| Team | 3 | 团队版 | 协作团队，共享配额 |
| Enterprise | 4 | 企业版 | 定制配额，专属支持 |

**实际示例（member_level 表数据）**：

```sql
-- Pro 月付计划
INSERT INTO member_level (name, level, experience, discountPercent,
                          price_monthly, price_yearly, currency, features, status)
VALUES ('Pro', 2, 500, 17,
        99.00, 990.00, 'CNY',
        '{"tick_monthly":100000,"storage_gb":10,"concurrent_sims":3,
          "monte_carlo":true,"api_calls_monthly":10000,"rp_daily_cap":5000}',
        1);
```

### 8.3.2 荣誉级别（复用 `member_user.experience`）

> yudao 的经验系统（`member_user.experience` + `member_level.experience` 升级阈值）被重新定义为荣誉级别晋升，与订阅计划解耦。经验通过项目贡献、社区活动获得。

| 荣誉级别 | 所需经验 | 称号 |
|---------|---------|------|
| Lv.1 | 0 | 探索者 |
| Lv.2 | 200 | 实践者 |
| Lv.3 | 500 | 研究者 |
| Lv.4 | 1000 | 高级研究者 |
| Lv.5 | 2000 | 专家 |
| Lv.6 | 5000 | 首席科学家 |

荣誉级别**不绑定订阅计划**：免费用户可以靠社区贡献达到高级研究者；Pro 订阅但无贡献的用户保持在探索者。

### 8.3.3 专家认证徽章（复用 `member_user.tagIds`）

> yudao 的标签系统（`member_tag` 表）被扩展为专家认证体系。徽章通过 `member_user.tagIds` 关联。

```sql
-- yudao member_tag 表示例（NSCA 新增标签记录）
INSERT INTO member_tag (name, description)
VALUES
  ('NC.Verified.Expert', '通过 NSCA 官方专家认证'),
  ('NC.MonteCarlo.Master', '蒙特卡洛仿真大师'),
  ('NC.TopReviewer.Gold', '黄金审核者（审核通过100+ PR）'),
  ('NC.ModelPack.Publisher', '模型包发布者（通过审核5+模型包）');
```

## 8.4 功能门控实现

> 功能门控由 `member_level.features` JSON 字段驱动。前端通过 `/api/v1/membership/current` 获取功能列表，后端通过网关 `FeatureGateFilter` 拦截。

**前端门控（UX 层）**：
```tsx
// 组件级门控 — 读取 membership.current 的 features map
<FeatureGate feature="monte_carlo" fallback={<UpgradePrompt tier="pro" />}>
  <MonteCarloPanel />
</FeatureGate>

// 按钮级门控 — 配额感知
<GatedButton
  feature="export_report"
  consumed={5}
  limit={5}
  onClick={handleExport}
>
  导出报告
</GatedButton>
// 当 consumed >= limit → 按钮灰显，点击弹出升级提示
```

**后端门控（网关层 + Spring Security）**：

```java
// 网关层 FeatureGateFilter（NSCA 新增）
@Component
public class FeatureGateFilter implements GlobalFilter, Ordered {

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        AuthContext ctx = exchange.getAttribute("authContext");
        String path = exchange.getRequest().getURI().getPath();

        // 从 features 检查所需功能
        if (path.contains("/monte-carlo") && !ctx.hasFeature("monte_carlo")) {
            exchange.getResponse().setStatusCode(HttpStatus.FORBIDDEN);
            return writeError(exchange, "FEATURE_LOCKED", "升级至 Pro 以使用蒙特卡洛");
        }
        return chain.filter(exchange);
    }

    @Override
    public int getOrder() { return 20; }
}

// Service 层方法级门控（复用 yudao @PreAuthorize）
@PreAuthorize("@ss.hasPermission('simulation:monte_carlo')")
public MonteCarloResult runMonteCarlo(MonteCarloRequest request) { ... }
```

## 8.5 升级/降级流程

**升级状态流转**：
```
用户发起升级 (POST /api/v1/billing/change-plan)
    ↓
Stripe/Jeepay 支付成功
    ↓
member_user.levelId 更新为新计划
user_subscription 表更新 status=active, 重置周期
features 立即生效，新配额即刻可用
    ↓
RocketMQ 发送 membership.tier.changed 事件
```

**降级状态流转**：
```
用户取消或订阅到期
    ↓
当前周期结束后 member_user.levelId 降为 Free (id=1)
    ↓
配额检查：
    - 超出配额的项目 → 只读模式
    - 超出存储 → 阻止新项目创建
    - 团队版 → 个人版：团队项目转交管理员
    ↓
RocketMQ 发送 membership.tier.changed 事件
```

## 8.6 排行榜接口

> 排行榜数据由核心业务提供（见 [05-gateway-integration.md §5.7](05-gateway-integration.md)），外骨骼通过核心透传接口获取排序数据，使用 `member_user` 表渲染用户信息。

```yaml
# GET /api/v1/membership/leaderboard
# 外骨骼调用核心透传 → 核心返回排序 → 外骨骼渲染用户信息
request:
  domain: string?             # 领域过滤
  period: string              # weekly | monthly | all_time
  category: string            # stars | forks | ticks | contributions
  limit: int                  # 默认 20

response_200:
  leaderboard:
    - rank: int
      user: UserSummary       # 从 member_user 表渲染
      score: int              # 核心计算
      change: int             # 核心计算排名变化
      badges: string[]        # 从 member_user.tagIds 关联
```

## 8.7 接口契约

```yaml
# GET /api/v1/membership/plans (查询 member_level 表)
response_200:
  plans:
    - plan_id: string         # member_level.id
      name: string            # member_level.name
      description: string
      price_monthly: string
      price_yearly: string
      currency: string
      features:
        - key: string
          name: string
          value: any
          included: boolean
      is_popular: boolean

# GET /api/v1/membership/current (查询 member_user + member_level)
response_200:
  tier: string                # member_level.name → free | pro | team | enterprise
  level: int                  # member_level.level
  plan_name: string
  honor_level:                # member_user.experience → 荣誉级别
    level: int
    title: string             # 探索者 / 实践者 / ...
    experience: int
    next_level_exp: int
  features:                   # member_level.features JSON
    monte_carlo: boolean
    max_projects: int
    max_ticks: int
    max_storage_gb: int
    max_collaborators: int
  badges:                     # member_user.tagIds → member_tag
    - id: string
      name: string
      awarded_at: datetime
  usage:                      # 计量服务 + 订阅配额
    ticks_used: int
    ticks_limit: int
    storage_used_gb: float
    storage_limit_gb: int
  next_billing_date: datetime?
  rp_balance: string          # rp_account.balance

# GET /api/v1/membership/leaderboard (核心透传 + member_user 渲染)
# 见 §8.6
```

## 8.8 会员事件流

> 事件通过 yudao 已集成的 RocketMQ 发送。Topic: `nsca-membership-events`。

```yaml
membership.tier.changed:
  user_id: Long
  old_level_id: Long
  new_level_id: Long
  reason: string              # upgrade | downgrade | expiry

membership.feature.unlocked:
  user_id: Long
  feature: string
  required_level: string

membership.quota.warning:
  user_id: Long
  metric: string              # ticks | storage | api
  percentage: float
  level_name: string

membership.badge.awarded:
  user_id: Long
  tag_id: Long                # member_tag.id
  tag_name: string

membership.honor_level.up:
  user_id: Long
  old_level: int
  new_level: int
  new_title: string            # 研究者 → 高级研究者

membership.leaderboard.rank_changed:
  user_id: Long
  old_rank: int
  new_rank: int
  category: string
```

## 8.9 yudao 扩展映射

| yudao 原有 | 方式 | NSCA 扩展 |
|-----------|------|----------|
| `member_level` 表 | 新增字段 | `price_monthly`, `price_yearly`, `currency`, `features(JSON)` |
| `member_level.experience` | 语义调整 | 从订阅升级阈值 → 荣誉级别晋升阈值 |
| `member_user.levelId` | 直接复用 | 当前订阅计划 ID |
| `member_user.experience` | 直接复用 | 荣誉级别经验值 |
| `member_user.point` | 保留并行 | yudao 简单积分（签到、admin 调整等） |
| `member_user.tagIds` | 扩展 | 专家认证徽章（通过 `member_tag` 新增标签） |
| `member_user.groupId` | 直接复用 | 团队版用户分组 |
| `member_point_record` | 扩展 bizType | 新增 RP 相关业务类型 + 新增 `rp_transaction` 表 |
| `member_tag` 表 | 新增记录 | 专家认证徽章标签 |
| — | **新增表** | `user_subscription`, `rp_account`, `rp_lot`（详见 06-billing.md） |
| — | **新增 Service** | `FeatureGateFilter`, `HonorLevelService`, `BadgeService` |
| RocketMQ (yudao 已有) | 新增 Topic | `nsca-membership-events` |

---

## 参考

- [yudao 会员中心文档](https://doc.iocoder.cn/member/)
- [06-billing.md](06-billing.md) — 订阅计划 + RP 积分数据模型
- [05-gateway-integration.md §5.7](05-gateway-integration.md) — 核心透传排行榜接口
- [../requirements/02-subscription-plans.md](../requirements/02-subscription-plans.md) — 订阅计划需求
