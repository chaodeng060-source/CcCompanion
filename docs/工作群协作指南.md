# 工作群使用指南 & AI Agent 协作模式

> CcCompanion 的工作群 (Group Chat) 是一个**多 agent 协作面板** — 用户在一个聊天界面里把多个 AI agent 拉到一起, 用 @mention 派活、看进度、做交叉审稿. 这份文档讲两件事:
>
> 1. 怎么用工作群 (普通用户)
> 2. 怎么让多 agent 协作不打架 (进阶 / agent 设计者)

---

## 一 工作群是什么

工作群不是普通群聊. 它是一个**让多个 AI 在同一屏幕协作干活的容器**.

### 跟普通群聊的区别

| 维度 | 普通 IM 群聊 | CcCompanion 工作群 |
|------|------------|-------------------|
| 成员 | 真人 | 用户 + 多个 AI agent (每个 agent 是 Mac 上一个 tmux session 跑 Claude / Codex / 等 CLI) |
| 路由 | 全员收到 | `@mention` 精准路由, 无 @ 时 broadcast 到全 agent (后者由 agent 自判是否响应) |
| 派活 | 口头说 | 用户 @某 agent 写 spec, agent 执行后 @用户 回报 |
| 跨 agent | 不能跨 IM | 同一 backend 路由, agent A 完工自动派 agent B review |

### 典型场景

- 你跟主 agent (例如 `assistant`) 聊产品方向, 让它写 spec
- spec 写完, 主 agent `@coder` 派去执行
- coder 跑完, `@reviewer` 派去交叉审稿
- reviewer 抓出 bug, 主 agent 给你看人话版总结, 你拍下一步
- 整个流程在你 iPhone 的工作群一屏看完

---

## 二 怎么开始用 (普通用户)

### 1 配置 agent

CcCompanion 默认带 2 个 agent (`user` + `assistant`). 你可以加自己的:

#### 方法 a — 改 `agents_config.json` (推荐, 持久化)

```bash
cd /path/to/CcCompanion/apns-server
cp agents_config.example.json agents_config.json
```

编辑 `agents_config.json`:

```json
{
  "agents": [
    {
      "id": "user",
      "display_name": "你的名字",
      "kind": "human",
      "avatar": "U",
      "color": "neutral"
    },
    {
      "id": "assistant",
      "display_name": "主助手",
      "kind": "agent",
      "avatar": "A",
      "color": "orange",
      "model": "Claude Opus 4.7",
      "tmux": "assistant",
      "canReply": true
    },
    {
      "id": "agent-b",
      "display_name": "执行助手",
      "kind": "agent",
      "avatar": "B",
      "color": "blue",
      "model": "Claude Sonnet 4.6",
      "tmux": "agent-b",
      "canReply": true
    },
    {
      "id": "agent-c",
      "display_name": "审稿助手",
      "kind": "agent",
      "avatar": "C",
      "color": "green",
      "model": "Codex GPT-5",
      "tmux": "agent-c",
      "canReply": true
    }
  ],
  "mention_aliases": {
    "user": "user",
    "ai": "assistant",
    "exec": "agent-b",
    "review": "agent-c"
  }
}
```

字段说明:

- `id` — 内部路由 ID (不展示给用户)
- `display_name` — 工作群里显示的名字
- `kind` — `human` 或 `agent`
- `avatar` — 头像首字 (单字母或汉字; 也可以用图片走 iOS 设置改)
- `color` — 头像底色 (`orange` / `blue` / `green` / `purple` / `slate` / `neutral`)
- `model` — 该 agent 跑的模型 (展示用)
- `tmux` — 对应的 tmux session 名 (派活脚本用)
- `canReply` — 是否能接收 @mention

`mention_aliases` 是别名映射 — 用户在 iPhone 输入 `@exec` 实际路由到 `agent-b`, 方便记.

#### 方法 b — 在 iOS Settings 里添加 (从 build 217 起)

设置 → 群聊 → 成员列表底部 `+` 按钮 → 弹窗填: 名称 / 头像 / 模型 / tmux session / 是否可回复 → 保存. 直接同步到 `agents_config.json`.

### 2 启动 agent 进程

每个 agent 在自己的 tmux session 里跑对应的 CLI:

```bash
# 主助手 (Claude Code)
tmux new-session -d -s assistant
tmux send-keys -t assistant "claude --model claude-opus-4-7 --dangerously-skip-permissions" Enter

# 执行助手
tmux new-session -d -s agent-b
tmux send-keys -t agent-b "claude --model claude-sonnet-4-6 --dangerously-skip-permissions" Enter

# 审稿助手 (Codex)
tmux new-session -d -s agent-c
tmux send-keys -t agent-c "codex --model gpt-5" Enter
```

### 3 派活脚本

仓库 `scripts/` 下有派活脚本模板. 用 `dispatch_to_agent.sh`:

```bash
~/scripts/dispatch_to_agent.sh agent-b ~/work/inbox/your-spec.md --priority high
```

脚本做三件事:
1. 把 spec 文件复制到 agent 的 inbox
2. `tmux send-keys` 通知该 agent 执行
3. `curl POST /group/send` 在工作群通报派活动作 (附 spec 摘要)

### 4 iOS 端使用

打开 CcCompanion iOS app → 群聊 tab → 你能看到:

- **顶部**: 群名 + 群头像 + 搜索 + 收藏入口
- **成员行**: 横向滚动展示所有 agent 跟状态 (在线 / 离线 / 正在输入)
- **消息流**: 按时间排列, agent 名 + model 名 + 内容
- **输入框**: `加号 (拍照 / 文件) → @ → 输入 → 图片 → 发送`

#### 发消息

- **直接发** (无 @) → 默认 broadcast 给全 agent, 每个 agent 自己判断要不要回. 跟微信群一句"今晚加班" 不是每个人都接的逻辑一致.
- **@某 agent** → 精准路由, 该 agent 必须响应
- **@all 或 @艾特所有人** → 强制全员都收
- **加号 → 拍照 / 文件** → 上传图片 / 文件 / 视频, agent 能读
- **长按消息** → 复制 / 引用 / 收藏 / 多选 / 删除 / 分享

---

## 三 多 Agent 协作模式 (进阶)

CcCompanion 里推荐的协作模式是 **"主助手 + 执行助手 + 审稿助手" 三层架构**:

```
     ┌─────────────┐
     │    User     │
     └──────┬──────┘
            │
            ▼
     ┌─────────────┐
     │ 主助手 (A)   │  ← 决策、写 spec、对用户翻译
     └──┬────────┬─┘
        │        │
   派 spec    派 spec
        │        │
        ▼        ▼
  ┌──────┐  ┌──────┐
  │ 执行  │  │ 审稿  │  ← 自动 review 执行结果
  │ 助手  │←─┤ 助手  │
  │ (B)  │  │ (C)  │
  └──┬───┘  └───┬──┘
     │          │
     └────┬─────┘
          ▼
       主助手收两边结果 → 报告用户
```

### 三个角色

#### 主助手 (Assistant / Agent A) — 决策层

**职责**:
- 直接对用户聊天, 理解需求
- 把需求拆成可执行 spec
- 派给执行助手 (B)
- 接 review 反馈, 翻译成人话报告给用户

**模型选择**: 推荐用最强 reasoning 模型 (Claude Opus / GPT-5 Pro 等) — 它做的是判断, 不是劳力.

#### 执行助手 (Agent B) — 实现层

**职责**:
- 接主助手的 spec
- 在仓库 / 服务器上执行 (改代码 / 跑命令 / 部署)
- 完工后写 result 报告
- 自动派审稿助手 review

**模型选择**: 性价比高的模型 (Sonnet / Codex / Aider 等). 它做的是机械执行, 不需要太多 reasoning.

#### 审稿助手 (Agent C) — 验证层

**职责**:
- 接执行结果, 跟原 spec 对比
- 跑 build / test / lint
- 抓出执行助手漏的边界 case
- 写 review 报告 (PASS / PASS_WITH_NOTES / NEEDS_REVISION)

**模型选择**: 跨基座最好 — 用跟执行助手不同的模型 (例如执行用 Claude, 审稿用 Codex), 拿"独立视角"抓 confirmation bias.

### 协作硬规则

为了不让多 agent 互相吵 (或互相 echo 刷屏), 给每个 agent 的 SOP 里加这些规则:

#### 规则 1 — 不寒暄

执行 / 审稿助手收 spec 直接干, 不"收到 我读一下" 不"好的开始". 完工才发一条报告.

#### 规则 2 — 不发空 ack

被主助手 verify 之后不要回 "standby" / "收到 ✓" / "等下一件". 主助手看到完工通知自动知道下一步, 不需要 echo.

#### 规则 3 — 完工报告人话 + 工程细节同条

执行助手写报告时要包含: 一句话总结 + 改动文件清单 + 关键决策 (3-5 条) + 已知 stub + commit hash. **不分"工程版""人话版"两段** — 用户读不动两份, 主助手翻译时一份就够.

#### 规则 4 — 审稿不放水

审稿助手如果觉得交付有问题, **必须**写 NEEDS_REVISION, 不要为了"和气"打 PASS_WITH_NOTES. 主助手能根据审稿严格度判断要不要重派.

#### 规则 5 — 无 @ broadcast 时 agent 自判要不要响应

用户在群里发消息没 @ 任何人, agent 收到 metadata `broadcast: true`. 自判规则:

- 相关 + 我能加价值 → 回 (例如用户说"那个 build 怎么样", 执行助手最了解直接回)
- 不相关 / 别 agent 更适合 → 不回 (例如用户问审稿结果, 执行助手不抢, 让审稿助手回)
- 纯情绪 / 寒暄 / 私密符号 → 主助手处理, 其它 agent 不掺和
- 真不确定要不要回 → 不回 (沉默优于刷屏)

#### 规则 6 — 公开 repo 上传前 grep 私名

每个 agent 在 commit 公开 repo 之前必须跑:

```bash
git diff --cached | grep -iE "<你的私名清单 regex>"
```

返回 zero hit 才能 commit. 不要把团队内部代号 / 真名 / 域名留进公开源码.

---

## 四 进阶: 写自己 agent 的 SOP

每个 agent 都有自己的 `CLAUDE.md` (或 `AGENTS.md`) 定义行为. 推荐结构:

```markdown
# Agent X SOP

## 你是谁
名字 / 模型 / 跑的 tmux session.

## 你跟主助手的关系
主助手派活你执行, 完工 push 报告.

## 工作风格
- 不寒暄
- 完工说"X 任务做完 路径 Y 关键决策 ABC"
- 报告 markdown + bullet + 表格

## 工作流
1. 冷启动读项目记忆索引 (~/work/memory/INDEX.md)
2. 接 spec → 先 grep 长期记忆找历史经验
3. 不清退回主助手问 不要自己拍
4. 完工四件: 写 result / 更新 project memory / 抽 decisions / 抽 learnings

## 不要做
- 不要写主助手风格的撒娇 / emoji / 括号动作
- 不要碰主助手的私人记忆目录
- 不要发空 ack 进工作群
- 不要主动 ping 用户 (走主助手转)
```

完整模板在仓库 `examples/agent-sop-template.md`.

---

## 五 常见问题

### Q1 我可以加几个 agent?

技术上不限. 实际推荐 3-5 个 (主 + 1-2 执行 + 1 审稿). 超过 5 个用户在工作群里很难追.

### Q2 agent 离线了怎么办?

工作群成员状态是从 tmux session 跑情况判断的 (是否有 active claude/codex 进程). 离线的 agent 在头像旁会显示灰点. 派给离线 agent 的消息会进 inbox 等它上线再处理.

### Q3 多用户共享一个 workgroup 可以吗?

当前架构是**单用户单 Mac**. 多用户要么各跑各的, 要么改 backend 让一个 Mac 跑多 user namespace (没现成模板).

### Q4 agent 之间能私聊吗?

可以 — `@agent-b` 的消息只路由到 agent-b, 主助手默认收一份当 audit. agent-b 回的消息也是同样规则.

### Q5 用户在群里发消息不 @ 谁 全部 agent 都会抢着回 怎么办?

按 broadcast 自判规则 (上面规则 5). 如果你的 agent SOP 写得好, 不会抢. 如果发现某 agent 老抢话, 改它的 SOP 加 "不相关时沉默" 强约束.

---

## 六 引用

- 后端 API 文档: `cccompanion-docs/workgroup-backend.md`
- agent SOP 模板: `examples/agent-sop-template.md`
- 派活脚本: `scripts/dispatch_to_agent.sh`
- 配置示例: `apns-server/agents_config.example.json`

---

## 七 反馈

发现协作模式的问题 / 想加新功能 / 有自己的 agent 设计想分享, 邮件 `opia@starryfield.space` 或加微信 `CyberSealNull`.
