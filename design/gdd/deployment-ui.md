# 出征 UI (Deployment UI)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ⚖️ 抉择之重 (发兵是不可逆的承诺)
> **Architecture**: [ADR-0001](../docs/architecture/adr/adr-0001-event-bus-architecture.md), [ADR-0004](../docs/architecture/adr/adr-0004-turn-resolution-model.md) (submit_command)

## Overview

出征 UI 是玩家发兵的交互面板——在星图上选中己方星后点击相邻敌星时弹出。包含兵力滑块、目标信息、确认/取消按钮。MVP 不做兵种选择（默认步兵），极简设计。

## Player Fantasy

选了己方星 A（12 兵），点了敌星 B（5 兵）。一个简洁的面板弹出："从 地球 发兵 → 火星。兵力：[===O====] 8。预测：损失约 2，剩余 6。" 玩家满意地拖到 8，点确认——承诺已做出，等回合结束看结果。

（MVP 不做预测显示——预测功能延后到 Vertical Slice。但数据结构已保证可行。）

## Detailed Rules

### 规则 1: 面板元素

```
┌─────────────────────────────┐
│  出征：地球 → 火星           │  ← 标题（出发星→目标星）
│                             │
│  目标星球：火星 (RICH)       │  ← 目标信息
│  敌方驻兵：5                 │
│                             │
│  出兵数量：[====O======] 8  │  ← 滑块 + 数字
│  出发星剩余：4               │  ← 动态更新
│                             │
│  [取消]          [确认发兵]   │  ← 按钮
└─────────────────────────────┘
```

### 规则 2: 兵力滑块

- **范围**: 1 ~ `from_planet.garrison`
- **默认值**: `from_planet.garrison`（全部）
- **拖动时实时显示**: 数字 + "出发星剩余"
- **快速操作**: 点击数字可直接输入

### 规则 3: 确认发兵

点击"确认发兵":
1. 调用 `DeploymentSystem.deploy(from, to, count, INFANTRY)`
2. 若返回 true → 面板关闭，星图刷新（出发星驻兵减少）
3. 若返回 false → 显示红色提示（如"兵力不足"）

### 规则 4: 取消

点击"取消"或面板外区域 → 关闭面板，不产生指令。

### 规则 5: 快捷键

- `ESC` → 取消，关闭面板
- `Enter` → 确认发兵

### States and Transitions

```
星图选中己方星 + 点击相邻敌星:
  → 弹出面板，滑块默认值 = 全部驻兵
  → 玩家调整滑块
  → 确认: deploy() → 成功关闭 / 失败提示 + 面板保持
  → 取消: 面板关闭
```

## Formulas

不适用。

## Edge Cases

- **出发星 garrison = 1**: 滑块范围 1~1，滑动无意义——可直接确认
- **玩家确认时 garrison 已变**: 例如另一个并发操作扣了驻兵（MVP 不存在，但防御性：deploy() 实时 validate）
- **目标星在面板打开期间被 AI 抢先攻击**: 面板不关闭——玩家仍可发兵，到达时可能与 AI 指令同一目标（ADR-0004 独立战斗处理）

## Dependencies

| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 出征系统 | Hard | `deploy()` |
| 星球系统 | Soft | 读取目标星信息显示 |
| 星图 UI | Hard | 触发入口（选中后点击相邻敌星） |

## Tuning Knobs

| Knob | 说明 |
|------|------|
| 面板宽度 | 300px |

## Acceptance Criteria

- **GIVEN** 选中己方星 (garrison=10) + 点击相邻敌星，**WHEN** UI 弹出，**THEN** 滑块范围 1-10，默认值 10
- **GIVEN** 滑块拖到 5 + 确认，**WHEN** `deploy()` 返回 true，**THEN** 面板关闭，星图刷新（出发星 garrison=5）
- **GIVEN** 滑块拖到 15（> garrison），**WHEN** 确认，**THEN** `deploy()` 返回 false，面板保持，显示红色提示
- **GIVEN** 面板打开，**WHEN** 按 ESC，**THEN** 面板关闭，零指令生成
- **GIVEN** 面板打开，**WHEN** 按 Enter，**THEN** 确认发兵（等效点击确认按钮）
