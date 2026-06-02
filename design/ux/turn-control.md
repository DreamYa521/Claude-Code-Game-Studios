# UX Spec: Turn Control（回合控制）

**Screen ID**: `turn_control`
**Type**: Persistent HUD Element（固定在屏幕右上角）
**Input**: Mouse click + Keyboard (Space/E)

---

## Purpose

回合制最核心的交互入口。显示当前回合数、阶段、并执行"结束回合"操作。

---

## Layout

```
┌──────────────┐
│ 第 3 回合     │  ← 回合数（只读）
│ [结束回合]    │  ← 核心按钮（可变文字/状态）
│ Space         │  ← 快捷键提示
│ 部署阶段      │  ← 阶段指示（只读）
└──────────────┘
```

锚定：右上角（anchor_right=1.0, margin=16px）

---

## Button States

| 状态 | 按钮文字 | 颜色 | 可点击 | 条件 |
|------|----------|------|--------|------|
| **就绪** | 结束回合 | 蓝色 `#4488FF` | ✅ | PLAYING + DEPLOYMENT |
| **结算中** | 结算中... | 灰色 `#555555` | ❌ | PLAYING + EXECUTION |
| **收尾** | 收尾中... | 灰色 `#555555` | ❌ | PLAYING + CLEANUP |
| **暂停** | (隐藏) | — | — | PAUSED |
| **胜利** | (隐藏) | — | — | VICTORY |
| **失败** | (隐藏) | — | — | DEFEAT |

---

## Keyboard Shortcuts

| 快捷键 | 操作 | 条件 |
|--------|------|------|
| Space | 结束回合 | 仅在 DEPLOYMENT 阶段有效 |
| E | 结束回合 | 仅在 DEPLOYMENT 阶段有效 |

---

## EventBus Subscriptions

| 信号 | 响应 |
|------|------|
| `deployment_phase_started` | 按钮恢复：文字"结束回合"，蓝色可用 |
| `execution_phase_started` | 按钮禁用：文字"结算中..."，灰色 |
| `turn_ended(turn_number)` | 回合数 +1 |
| `game_state_changed(old, new)` | 根据新状态显示/隐藏/禁用 |

---

## Phase Indicator

| 阶段 | 显示文字 | 说明 |
|------|----------|------|
| DEPLOYMENT | 部署阶段 | 玩家正在发兵 |
| EXECUTION | 结算中... | 战斗动画面播放中 |
| CLEANUP | 收尾中... | 生产/占领导入中（MVP 几乎不可见） |

---

## Edge Cases

- **双击结束回合**：第一次点击后按钮立即 `disabled=true` → 第二次点击被忽略
- **在非 PLAYING 状态按 Space**：`_input()` gate 检查 `is_playing()` → 无响应
- **MVP CLEANUP 极快**：CLEANUP 在 MVP 中 <1ms，玩家基本看不到"收尾中..."
