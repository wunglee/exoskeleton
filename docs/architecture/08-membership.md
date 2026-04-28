## 08. 会员等级架构

### 08.1 设计原则

**价值梯度清晰**：每个等级的价值增量明确可见，用户升级动机强烈， downgrade 落差可控。

**功能门控透明**：未解锁功能明确展示升级路径，不隐藏功能入口（灰显+提示优于完全隐藏）。

**社交激励**：专家认证、贡献徽章、排行榜等社交资本激励，超越纯功能驱动。

**团队扩展**：个人版到团队版的无缝升级，数据、项目、权限平滑迁移。

### 08.2 会员等级体系

> 会员等级功能矩阵、订阅定价、专家认证条件、荣誉级别规则详见需求文档 `01-users-concepts.md`。

系统支持四级订阅体系：Free / Pro / Team / Enterprise。每级对应一组功能开关与资源配额，由 `SubscriptionPlan.features` 字典驱动前后端门控。

```python
class SubscriptionPlan:
    plan_id: str                    # free | pro | team | enterprise
    name: str
    billing_cycle: str              # monthly | yearly
    price_monthly: Decimal
    price_yearly: Decimal
    currency: str                   # USD | CNY
    features: Dict[str, Any]        # 功能开关与配额
    is_active: bool
```

### 08.5 功能门控实现

**前端门控（UX 层）**：
```tsx
// 组件级门控
<FeatureGate feature="monte_carlo" fallback={<UpgradePrompt tier="pro" />}>
  <MonteCarloPanel />
</FeatureGate>

// 按钮级门控
<GatedButton
  feature="export_report"
  consumed={5}
  limit={5}
  onClick={handleExport}
>
  导出报告
</GatedButton>
// 当 consumed >= limit 时，按钮灰显，点击弹出升级提示
```

**后端门控（API 层）**：
```python
@app.post("/api/v1/simulations/monte-carlo")
@require_feature("monte_carlo")
@require_quota("monte_carlo_runs", 1)
async def run_monte_carlo(request: MonteCarloRequest, user: User):
    # 门控装饰器自动处理：
    # 1. 检查用户会员等级是否包含 monte_carlo
    # 2. 检查当月剩余蒙特卡洛次数
    # 3. 任一不满足则返回 403 + 升级指引
    pass
```

### 08.6 升级/降级流程

**升级状态流转**：
```
用户发起升级
    ↓
支付成功 → 立即生效，新配额即刻可用
    ↓
旧计划按比例退款（如有）
    ↓
发布 membership.tier.changed 事件
```

**降级状态流转**：
```
用户取消或订阅到期
    ↓
当前周期结束后生效（已付费权益不收回）
    ↓
周期结束触发配额检查：
    - 超出配额的项目 → 只读模式
    - 超出存储 → 阻止新项目创建
    - 团队版 → 个人版：团队项目转交管理员
    ↓
发布 membership.tier.changed 事件
```

### 08.7 排行榜接口

> 排行榜业务规则（分类、奖励、更新周期）详见需求文档 `01-users-concepts.md`。

### 08.8 接口契约

```yaml
# GET /api/v1/membership/plans
response_200:
  plans:
    - plan_id: string
      name: string
      description: string
      price_monthly: string
      price_yearly: string
      currency: string
      features:
        - key: string
          name: string
          value: any
          included: boolean
      is_popular: boolean       # 标记推荐计划

# GET /api/v1/membership/current
response_200:
  tier: string                # free | pro | team | enterprise
  plan_name: string
  features:
    monte_carlo: boolean
    max_projects: int
    max_ticks: int
    max_storage_gb: int
    max_collaborators: int
  usage:
    ticks_used: int
    ticks_limit: int
    storage_used_gb: float
    storage_limit_gb: int
  next_billing_date: datetime?

# GET /api/v1/membership/leaderboard
request:
  domain: string?             # 领域过滤
  period: string              # weekly | monthly | all_time
  category: string            # stars | forks | ticks | contributions
  limit: int                  # 默认 20

response_200:
  leaderboard:
    - rank: int
      user: UserSummary
      score: int
      change: int              # 排名变化
      badges: string[]
```

### 08.9 会员事件流

```yaml
membership.tier.changed:
  user_id: UUID
  old_tier: string
  new_tier: string
  reason: string              # upgrade | downgrade | expiry

membership.feature.unlocked:
  user_id: UUID
  feature: string
  tier: string

membership.quota.warning:
  user_id: UUID
  metric: string
  percentage: float
  tier: string

membership.badge.awarded:
  user_id: UUID
  badge_id: string
  badge_name: string

membership.leaderboard.rank_changed:
  user_id: UUID
  old_rank: int
  new_rank: int
  category: string
