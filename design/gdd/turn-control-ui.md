# 回合控制 UI (Turn Control UI)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ♟️ 从容推演 (回合节奏的物理按钮)
> **Architecture**: [ADR-0003](../docs/architecture/adr/adr-0003-gamestate-state-machine.md), [ADR-0004](../docs/architecture/adr/adr-0004-turn-resolution-model.md)

## Overview

回合控制 UI 提供"结束回合"按钮、当前回合数显示、游戏状态标签。它是玩家主动推进游戏节奏的唯一入口——"我的部署做完了，让回合结算吧"。

MVP 极简：一个按钮 + 一个数字。

## Player Fantasy

玩家部署完毕，看一眼右上角——"第 5 回合"。点"结束回合"→ 按钮短暂禁用（EXECUTION 阶段）→ 动画闪过 → 按钮恢复，"第 6 回合"。干净利落，没有多余的步骤。

## Detailed Rules

### 规则 1: 界面元素

```
┌──────────────────────┐
│  第 5 回合            │  ← 回合数标签
│  [ 结束回合 ]         │  ← 主按钮
│  部署阶段             │  ← 阶段指示
└──────────────────────┘
```

### 规则 2: 结束回合按钮

- **DEPLOYMENT 阶段**: 按钮可用，蓝色，文字"结束回合"
- **EXECUTION 阶段**: 按钮禁用，灰色，文字"结算中..."
- **CLEANUP 阶段**: 按钮禁用，文字"收尾中..."
- **非 PLAYING 状态**: 按钮隐藏

点击 → 调用 `TurnManager.end_turn()`：
1. 禁用按钮（防止双击）
2. 回合管理器执行 5 步骤
3. `turn_ended` 信号 → 按钮恢复可用

### 规则 3: 回合数显示

- 监听 `EventBus.turn_ended(turn_number)`
- 显示"第 N 回合"
- 初始为"第 1 回合"（游戏开始时）

### 规则 4: 阶段指示

- 监听 `EventBus.deployment_phase_started` → 显示"部署阶段"
- 监听 `EventBus.execution_phase_started` → 显示"结算中..."
- 纯信息展示，无交互

### 规则 5: 快捷键

- `Space` → 结束回合（仅在 PLAYING + DEPLOYMENT 阶段有效）
- `E` → 同上，备选快捷键

### States and Transitions

```
游戏开始 (PLAYING, DEPLOYMENT):
  显示: "第1回合" + [结束回合] 可用 + "部署阶段"
  
玩家点击结束回合:
  按钮禁用 → "结算中..." → 5步骤执行
  → turn_ended → 回合数+1 → 按钮恢复 → "部署阶段"
  
游戏暂停 (PAUSED):
  按钮隐藏，显示"已暂停"
  
游戏结束 (VICTORY/DEFEAT):
  按钮隐藏，显示"胜利"/"失败"
```

## Formulas

不适用。

## Edge Cases

- **玩家双击结束回合**: 按钮在第一次点击后立即禁用 → 第二次点击无效
- **结束回合时无任何指令**: 允许——空回合正常结算（生产照常，AI 照常），玩家可以"跳过一回合"
- **快捷键在非 DEPLOYMENT 阶段按下**: 忽略

## Dependencies

| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 回合管理器 | Hard | `end_turn()` |
| GameState | Hard | `is_playing()` gate |
| 事件总线 | Hard | 订阅 `turn_ended`, `deployment_phase_started`, `execution_phase_started` |

## Tuning Knobs

| Knob | 说明 |
|------|------|
| 按钮位置 | 屏幕右上角 |

## Acceptance Criteria

- **GIVEN** 游戏在 PLAYING + DEPLOYMENT，**WHEN** 渲染 UI，**THEN** "结束回合"按钮可用
- **GIVEN** 点击"结束回合"，**WHEN** 结算中，**THEN** 按钮禁用
- **GIVEN** `turn_ended` 信号，**WHEN** UI 刷新，**THEN** 回合数 +1，按钮恢复
- **GIVEN** PAUSED 状态，**WHEN** 渲染 UI，**THEN** 按钮隐藏
- **GIVEN** 在 DEPLOYMENT 阶段按 Space，**WHEN** UI 响应，**THEN** 等效点击"结束回合"
