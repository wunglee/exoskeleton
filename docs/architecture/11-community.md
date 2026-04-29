# 11. 社区层架构

> 外骨骼通用社区框架：论坛讨论、评论、关注、动态流。这些是任何会员制平台都需要的通用能力，由外骨骼系统硬编码实现。核心透传功能（Fork/MR/仿真预览/排行榜）不在本文档范围内——外骨骼仅通过核心配置接口获取配置并渲染。

## 11.1 设计原则

**通用框架，非业务专属**：论坛、评论、关注、动态流是通用社区能力。外骨骼提供标准实现，不包含任何 NSCA 特有的仿真/Fork/MR 逻辑。

**核心透传，非外骨骼实现**：Fork 按钮、MR 按钮、仿真预览、研究进展、排行榜由核心通过配置接口驱动。外骨骼只负责"渲染按钮/组件 + 转发请求到核心 API"，不实现业务逻辑。

**事件驱动解耦**：社区行为（发帖、评论、点赞、关注）发布事件，RP 积分系统异步消费事件计算奖励，社区层不直接依赖计费层。

**归属明确**：每个社区功能在数据模型和 API 设计中明确标注归属——外骨骼拥有论坛/评论/关注/动态流；核心拥有 Fork/MR/仿真/排行榜。

## 11.2 模块边界

```
┌─────────────────────────────────────────────────────────────────┐
│                    外骨骼社区层 (exoskeleton-community)            │
│                                                                   │
│  ┌──────────────────────────┐  ┌──────────────────────────────┐ │
│  │  通用社区框架 (外骨骼拥有)  │  │  核心透传集成 (外骨骼渲染)    │ │
│  │                          │  │                              │ │
│  │  - 论坛讨论 (Forum)       │  │  - Fork 按钮 → /core/fork    │ │
│  │  - 评论系统 (Comment)     │  │  - MR 按钮 → /core/mr        │ │
│  │  - 关注/粉丝 (Follow)    │  │  - 仿真预览 → core iframe     │ │
│  │  - 动态流 (ActivityFeed) │  │  - 研究进展 → core data      │ │
│  │  - 点赞系统 (Like)       │  │  - 排行榜 → core leaderboard │ │
│  │  - @用户 (Mention)      │  │  - 版本历史 → core history   │ │
│  └──────────┬───────────────┘  └──────────────┬───────────────┘ │
│             │                                  │                  │
│             │  exoskeleton PostgreSQL           │  HTTP → core     │
│             │  (community_* tables)             │  (passthrough)   │
│             ▼                                  ▼                  │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │              Spring Cloud Gateway (Header 注入)                │ │
│  │   X-User-Id | X-Tenant-Id | X-Request-Id | X-Features        │ │
│  └──────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## 11.3 数据模型

### 11.3.1 论坛讨论 (ForumPost)

```sql
CREATE TABLE community_forum_post (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL,
    author_id       UUID NOT NULL,
    project_id      UUID,                          -- NULL = 全局论坛帖
    title           VARCHAR(200) NOT NULL,
    content         TEXT NOT NULL,                  -- Markdown
    content_html    TEXT NOT NULL,                  -- 服务端渲染的 HTML（XSS 净化后）
    is_pinned       BOOLEAN DEFAULT FALSE,          -- 置顶（项目成员可设置）
    is_locked       BOOLEAN DEFAULT FALSE,          -- 锁定（禁止新回复）
    view_count      INTEGER DEFAULT 0,
    reply_count     INTEGER DEFAULT 0,
    like_count      INTEGER DEFAULT 0,
    tags            VARCHAR(50)[] DEFAULT '{}',    -- PostgreSQL 数组
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ                    -- 软删除

    -- 注意：不创建外键约束到 user 表，User 数据由 Logto OIDC 管理
    -- tenant_id 用于租户隔离，所有查询必须带 tenant_id
);

CREATE INDEX idx_forum_post_project ON community_forum_post(tenant_id, project_id, created_at DESC);
CREATE INDEX idx_forum_post_author ON community_forum_post(author_id, created_at DESC);
CREATE INDEX idx_forum_post_tags ON community_forum_post USING gin(tags);
```

### 11.3.2 论坛回复 (ForumReply)

```sql
CREATE TABLE community_forum_reply (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id         UUID NOT NULL,
    parent_reply_id UUID,                          -- NULL = 顶层回复，非 NULL = 嵌套回复
    author_id       UUID NOT NULL,
    tenant_id       UUID NOT NULL,
    content         TEXT NOT NULL,                  -- Markdown
    content_html    TEXT NOT NULL,
    like_count      INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ

    -- 嵌套深度限制：最多 2 层（parent_reply_id 的 parent_reply_id 必须为 NULL）
    -- 在应用层校验，不在数据库层约束
);

CREATE INDEX idx_forum_reply_post ON community_forum_reply(post_id, created_at ASC);
```

### 11.3.3 评论 (Comment) — 通用评论系统

```sql
CREATE TABLE community_comment (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL,
    author_id       UUID NOT NULL,
    target_type     VARCHAR(30) NOT NULL,           -- 'project' | 'model_pack' | 'paper' | 'hypothesis'
    target_id       UUID NOT NULL,
    parent_id       UUID,                           -- 嵌套回复
    content         TEXT NOT NULL,                   -- Markdown
    content_html    TEXT NOT NULL,
    like_count      INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_comment_target ON community_comment(target_type, target_id, created_at ASC);
CREATE INDEX idx_comment_author ON community_comment(author_id, created_at DESC);
```

### 11.3.4 用户关注 (Follow)

```sql
CREATE TABLE community_follow (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id     UUID NOT NULL,                  -- 关注者
    followee_id     UUID NOT NULL,                  -- 被关注者
    tenant_id       UUID NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(follower_id, followee_id),
    CHECK(follower_id <> followee_id)              -- 不能关注自己
);

CREATE INDEX idx_follow_follower ON community_follow(follower_id);
CREATE INDEX idx_follow_followee ON community_follow(followee_id);
```

### 11.3.5 动态流 (ActivityEvent)

```sql
CREATE TABLE community_activity_event (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL,
    actor_id        UUID NOT NULL,                  -- 触发行为的用户
    event_type      VARCHAR(40) NOT NULL,           -- 见事件类型枚举
    target_type     VARCHAR(30),                    -- 'project' | 'forum_post' | 'comment' | null
    target_id       UUID,
    payload         JSONB DEFAULT '{}',             -- 事件附加数据
    visibility      VARCHAR(10) DEFAULT 'public',   -- 'public' | 'followers_only' | 'private'
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_activity_actor ON community_activity_event(actor_id, created_at DESC);
CREATE INDEX idx_activity_feed ON community_activity_event(tenant_id, visibility, created_at DESC);
CREATE INDEX idx_activity_target ON community_activity_event(target_type, target_id);
```

事件类型枚举：

| event_type | 说明 | payload |
|-----------|------|---------|
| `forum.post_created` | 发布论坛帖 | `{post_id, title, project_id?}` |
| `forum.reply_created` | 回复论坛帖 | `{post_id, reply_id, parent_reply_id?}` |
| `comment.created` | 发表评论 | `{target_type, target_id, comment_id}` |
| `project.starred` | 星标项目 | `{project_id, project_name}` |
| `project.forked` | Fork 项目（透传核心事件） | `{project_id, fork_id}` |
| `user.followed` | 关注用户 | `{followee_id}` |
| `hypothesis.verified` | 假设验证通过 | `{project_id, hypothesis_id}` |
| `badge.awarded` | 获得徽章 | `{badge_id, badge_name}` |

### 11.3.6 点赞 (Like)

```sql
CREATE TABLE community_like (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL,
    tenant_id       UUID NOT NULL,
    target_type     VARCHAR(30) NOT NULL,           -- 'forum_post' | 'forum_reply' | 'comment' | 'project'
    target_id       UUID NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(user_id, target_type, target_id)
);

CREATE INDEX idx_like_target ON community_like(target_type, target_id);
```

## 11.4 API 契约

### 11.4.1 论坛讨论

```yaml
# POST /api/v1/community/forum/posts
# 创建论坛帖
request:
  project_id: UUID?            # null = 全局论坛
  title: string                # 1-200 字符
  content: string              # Markdown，最大 50KB
  tags: string[]?              # 最多 5 个标签
response_201:
  post:
    id: UUID
    author: UserSummary
    title: string
    content_html: string
    tags: string[]
    created_at: datetime

# GET /api/v1/community/forum/posts
# 论坛帖列表（支持全局帖 + 项目帖过滤）
request:
  project_id: UUID?            # null = 仅全局帖；指定 = 该项目帖
  sort: string                 # 'latest' | 'hot' | 'most_replied'
  page: int                    # 默认 1
  limit: int                   # 默认 20，最大 50
response_200:
  posts:
    - id: UUID
      title: string
      author: UserSummary
      reply_count: int
      like_count: int
      view_count: int
      tags: string[]
      is_pinned: boolean
      created_at: datetime
  total: int
  page: int

# GET /api/v1/community/forum/posts/{id}
# 论坛帖详情（含回复列表）
response_200:
  post:
    id: UUID
    project_id: UUID?
    title: string
    content_html: string
    author: UserSummary
    tags: string[]
    like_count: int
    view_count: int
    is_pinned: boolean
    is_locked: boolean
    created_at: datetime
  replies:                     # 前 20 条顶层回复
    - id: UUID
      author: UserSummary
      content_html: string
      like_count: int
      children: []Reply        # 嵌套回复（最多展示 3 条，更多点"展开"）
      created_at: datetime
  reply_total: int

# POST /api/v1/community/forum/posts/{id}/replies
# 回复论坛帖
request:
  parent_reply_id: UUID?       # null = 顶层回复
  content: string              # Markdown，最大 20KB
response_201:
  reply: ForumReply

# DELETE /api/v1/community/forum/posts/{id}
# 删除论坛帖（仅作者或管理员）
# → 发布 community.forum.post.deleted 事件
```

### 11.4.2 评论

```yaml
# POST /api/v1/community/comments
# 创建评论
request:
  target_type: string          # 'project' | 'model_pack' | 'paper' | 'hypothesis'
  target_id: UUID
  parent_id: UUID?
  content: string              # Markdown，最大 20KB
response_201:
  comment:
    id: UUID
    author: UserSummary
    content_html: string
    like_count: int
    created_at: datetime

# GET /api/v1/community/comments
# 评论列表
request:
  target_type: string
  target_id: UUID
  sort: string                 # 'latest' | 'oldest' | 'most_liked'
  page: int
  limit: int                   # 默认 20
response_200:
  comments:
    - id: UUID
      author: UserSummary
      content_html: string
      like_count: int
      children: []Comment
      created_at: datetime
  total: int
```

### 11.4.3 关注

```yaml
# POST /api/v1/community/follows
# 关注/取消关注用户（toggle）
request:
  followee_id: UUID
response_200:
  following: boolean           # true = 已关注，false = 已取消
  follower_count: int

# GET /api/v1/community/users/{id}/followers
# 粉丝列表
request:
  page: int
  limit: int                   # 默认 20
response_200:
  followers: []UserSummary
  total: int

# GET /api/v1/community/users/{id}/following
# 关注列表
request:
  page: int
  limit: int
response_200:
  following: []UserSummary
  total: int
```

### 11.4.4 动态流

```yaml
# GET /api/v1/community/feed
# 用户动态流（关注者的活动 + 全局热门）
request:
  scope: string                # 'following' | 'global'
  page: int
  limit: int                   # 默认 20
response_200:
  events:
    - id: UUID
      actor: UserSummary
      event_type: string
      target_type: string?
      target_id: UUID?
      payload: object
      created_at: datetime
  total: int

# GET /api/v1/community/users/{id}/activity
# 指定用户的活动时间线
request:
  page: int
  limit: int
response_200:
  events: []ActivityEvent
  total: int
```

### 11.4.5 点赞

```yaml
# POST /api/v1/community/likes
# 点赞/取消点赞（toggle）
request:
  target_type: string          # 'forum_post' | 'forum_reply' | 'comment' | 'project'
  target_id: UUID
response_200:
  liked: boolean
  like_count: int
```

## 11.5 核心透传集成

外骨骼不实现 Fork/MR/仿真预览/排行榜/版本历史的业务逻辑。这些功能通过核心配置接口驱动：

```
外骨骼前端                          外骨骼后端（Gateway）                   核心业务服务
    │                                     │                                  │
    │ GET /api/v1/core/page-config        │                                  │
    │ ?type=project-public                │                                  │
    │ &project_id={id}                    │                                  │
    ├────────────────────────────────────►│                                  │
    │                                     │ GET /api/v1/core/page-config     │
    │                                     │ (注入 X-User-Id, X-Tenant-Id)    │
    │                                     ├─────────────────────────────────►│
    │                                     │                                  │
    │                                     │  ← { tabs: [                     │
    │                                     │      { key: "progress",          │
    │                                     │        label: "研究进展",         │
    │                                     │        type: "core_data",        │
    │                                     │        endpoint: "/api/v1/core/  │
    │                                     │          projects/{id}/progress" │
    │                                     │      },                          │
    │                                     │      { key: "simulation",        │
    │                                     │        label: "仿真预览",         │
    │                                     │        type: "core_iframe",      │
    │                                     │        src: "/core/simulation/   │
    │                                     │          preview?id={id}"        │
    │                                     │      },                          │
    │                                     │      { key: "forum",             │
    │                                     │        label: "论坛讨论",         │
    │                                     │        type: "exoskeleton",      │
    │                                     │        endpoint: "/api/v1/       │
    │                                     │          community/forum/posts   │
    │                                     │          ?project_id={id}"       │
    │                                     │      },                          │
    │                                     │      ...                         │
    │                                     │    ]}                            │
    │  ← { tabs, actions, permissions }   │ ← ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
    │                                     │                                  │
    │ 外骨骼根据 type 决定渲染方式：       │                                  │
    │ - core_data → 调用 endpoint 取数据   │                                  │
    │ - core_iframe → 嵌入 iframe         │                                  │
    │ - exoskeleton → 外骨骼自有组件       │                                  │
```

### 核心配置接口

| 接口 | 用途 | 归属 |
|------|------|------|
| `GET /api/v1/core/page-config?type={type}&project_id={id}` | 返回页面 Tab 列表和每个 Tab 的渲染配置 | 核心 |
| `GET /api/v1/core/leaderboard?domain={d}&period={p}&category={c}` | 返回排行榜排序数据 | 核心 |
| `GET /api/v1/core/permissions?project_id={id}&user_id={uid}` | 返回用户对项目的操作权限 | 核心 |
| `POST /api/v1/core/projects/{id}/fork` | Fork 项目 | 核心 |
| `POST /api/v1/core/projects/{id}/merge-requests` | 创建合并请求 | 核心 |
| `GET /api/v1/core/projects/{id}/progress` | 获取研究进展数据 | 核心 |
| `GET /api/v1/core/projects/{id}/forks` | 获取 Fork 派生树 | 核心 |
| `GET /api/v1/core/projects/{id}/versions` | 获取版本历史 | 核心 |

> 这些接口的完整规格不属于外骨骼架构文档。外骨骼的责任是：信任核心返回的配置数据，按配置渲染 UI 组件，将用户操作转发到核心 API。

## 11.6 社区事件与 RP 积分联动

社区行为通过事件驱动方式触发 RP 奖励，社区层不直接调用 RP 服务：

```
社区行为                      事件                            RP 消费者
─────────                    ────                           ──────────
发布论坛帖     →  community.forum.post_created    →  +2 RP（每日最多 10 RP）
回复论坛帖     →  community.forum.reply_created   →  +1 RP（每日最多 5 RP）
发表评论       →  community.comment.created       →  +1 RP（每日最多 5 RP）
被点赞         →  community.like.received         →  +0.5 RP（每日最多 10 RP）
获得关注       →  community.follow.received       →  不奖励（防刷）
星标项目       →  community.project.starred       →  +1 RP（对星标者）
项目被星标     →  community.project.star_received →  +3 RP（对项目所有者）
```

防刷规则在 RP 消费者中实现（不在社区层）：
- 同一 IP 对同一目标的重复操作去重
- 每日 RP 获取上限
- NLP 质量评分（内容长度 < 50 字符不计入 RP 奖励）

## 11.7 网关路由

```yaml
spring:
  cloud:
    gateway:
      routes:
        # 社区服务路由
        - id: community-service
          uri: lb://exoskeleton-community
          predicates: Path=/api/v1/community/**

        # 核心透传路由（外骨骼仅转发，不处理业务逻辑）
        - id: core-passthrough
          uri: lb://nsca-core-service
          predicates: Path=/api/v1/core/**
          filters:
            - name: CircuitBreaker
              args:
                name: coreBreaker
                fallbackUri: forward:/fallback/core
```

## 11.8 内容安全

### XSS 防护

所有用户提交的 Markdown 内容在服务端渲染为 HTML 后进行净化：

```java
@Service
public class MarkdownSanitizer {
    private final PolicyFactory sanitizePolicy = Sanitizers.FORMATTING
        .and(Sanitizers.BLOCKS)
        .and(Sanitizers.LINKS)
        .and(Sanitizers.IMAGES)
        .and(Sanitizers.TABLES);

    public String renderAndSanitize(String markdown) {
        String html = pegdownProcessor.markdownToHtml(markdown);
        return sanitizePolicy.sanitize(html);
    }
}
```

净化规则：
- 允许：`h1-h6`, `p`, `ul`, `ol`, `li`, `strong`, `em`, `a[href]`, `img[src|alt]`, `code`, `pre`, `blockquote`, `table`, `thead`, `tbody`, `tr`, `th`, `td`
- 移除：`script`, `style`, `iframe`, `object`, `embed`, `on*` 事件属性
- `a[href]` 仅允许 `https://` 和 `mailto:` 协议

### 速率限制

```yaml
sentinel:
  rules:
    - resource: community-forum-post
      grade: QPS
      count: 3                    # 每用户每分钟最多 3 篇帖
    - resource: community-comment
      grade: QPS
      count: 10                   # 每用户每分钟最多 10 条评论
    - resource: community-like
      grade: QPS
      count: 30                   # 每用户每分钟最多 30 次点赞
```

### 内容审核

```sql
CREATE TABLE community_moderation_queue (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_type    VARCHAR(30) NOT NULL,
    content_id      UUID NOT NULL,
    status          VARCHAR(20) DEFAULT 'pending',  -- 'pending' | 'approved' | 'rejected'
    reason          TEXT,
    reviewed_by     UUID,
    reviewed_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## 11.9 与需求文档的对应

| 需求章节 | 归属 | 架构覆盖 |
|---------|------|---------|
| 7.17 首页门户 | 混合（布局外骨骼，数据核心） | 11.4.4 动态流 + 11.5 核心透传 |
| 7.18 领域广场 | 混合（外骨骼渲染列表，核心提供数据） | 11.5 核心透传 |
| 7.19 项目公共页 Tab 1-3 | 核心透传 | 11.5 核心透传 |
| 7.19 项目公共页 Tab 4 (论坛) | 外骨骼 | 11.3.1 + 11.4.1 |
| 7.19 项目公共页 Tab 5-6 | 核心透传 | 11.5 核心透传 |
| 7.20 个人空间 | 核心透传 | 11.5 核心透传 |
| 7.21 专家认证与排行榜 | 混合（徽章外骨骼，数据核心） | 11.5 核心透传 |
| 评论系统（通用） | 外骨骼 | 11.3.3 + 11.4.2 |
| 关注/粉丝 | 外骨骼 | 11.3.4 + 11.4.3 |
| 动态流 | 外骨骼 | 11.3.5 + 11.4.4 |
| 点赞 | 外骨骼 | 11.3.6 + 11.4.5 |

---

## 参考

- [03-community.md](../requirements/03-community.md) — 社区层需求文档
- [05-gateway-integration.md](05-gateway-integration.md) — 网关集成协议（Header 注入、路由）
- [06-billing.md](06-billing.md) — RP 积分消费者（社区事件 → RP 奖励）
- [03-auth.md](03-auth.md) — 认证（X-User-Id 来源）
