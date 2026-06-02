# 星图 UI (Star Map UI)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ♟️ 从容推演 (清晰的战场信息)
> **Architecture**: [ADR-0001](../docs/architecture/adr/adr-0001-event-bus-architecture.md) (EventBus 订阅)

## Overview

星图 UI 是玩家的**主视图**——渲染所有星球节点、连接路线、兵力数字、归属颜色。玩家在星图上完成所有操作（点选星球、查看信息、发起出征）。它是游戏 90% 时间的视觉呈现。

MVP 不做花哨效果——圆形节点 + 颜色区分 + 数字标注。信息高于装饰。

## Player Fantasy

玩家打开游戏看到的第一眼：深色背景上几颗彩色星球，蓝色的是自己的，红色的是敌人的，灰色的是中立的。连接线告诉你"能打哪里"。兵力数字一目了然。玩家不需要看教程就知道这是什么——这是一个棋盘。

## Detailed Rules

### 规则 1: 星球节点渲染

每个星球渲染为一个**圆形图标**：

| 属性 | 规格 |
|------|------|
| 形状 | 圆形，半径 24px |
| 颜色 | PLAYER=蓝色(#4488FF), ENEMY=红色(#FF4444), NEUTRAL=灰色(#888888) |
| 边框 | 选中状态：2px 白色边框闪烁 |
| 文字 | 星球名（8px 上方）+ 兵力数字（14px 居中，白色） |
| 位置 | 按 `planet.position`（Vector2，关卡数据中配置） |

### 规则 2: 连接线渲染

每条 Connection 渲染为一条细线：

| 属性 | 规格 |
|------|------|
| 样式 | 实线，2px 宽 |
| 颜色 | 半透明白色 (#FFFFFF 50% alpha) |
| 端点 | 从星球圆心到圆心 |
| 高亮 | 当选中星球 A 时，A 的所有连接线变为亮色(#FFCC00) |

### 规则 3: 交互

- **点击星球**: 选中该星（高亮边框），显示详情面板（归属、属性、驻兵/上限、相邻星列表）
- **再次点击同星**: 取消选中
- **点击相邻敌星**: 若已选中己方星 → 打开发兵界面（出征 UI）
- **点击非相邻敌星**: 不响应（或提示"不可达"）
- **点击空白区域**: 取消选中

### 规则 4: 事件订阅

星图 UI 监听以下 EventBus 信号并自动刷新：

| 信号 | 响应 |
|------|------|
| `planets_initialized` | 首次渲染全部星球和连接 |
| `planet_owner_changed` | 更新该星球颜色 |
| `planet_garrison_changed` | 更新该星球兵力数字 |
| `turn_ended` | 全部刷新 |
| `game_ended` | 显示胜利/失败 overlay |

### 规则 5: 详情面板

选中星球后，在屏幕一侧显示：

```
星球: 火星
归属: 玩家 (蓝色)
属性: RICH (富饶)
驻兵: 12 / 20
产兵: 1.5 / 回合
连接: 地球, 火卫一
```

### States and Transitions

```
未选中状态:
  所有星球正常渲染，无边框高亮
  → 点击己方星 → 选中己方星状态
  → 点击敌方星 → 选中敌方星状态

选中己方星状态:
  该星高亮蓝框, 相邻敌星高亮黄框(可达提示)
  → 点击相邻敌星 → 触发出征UI
  → 点击其他己方星 → 切换选中
  → 点击空白 → 取消选中

选中敌方星状态:
  该星高亮红框, 相邻己方星高亮蓝框(提示"可以从这打")
  → 点击相邻己方星 → 触发出征UI
  → 点击空白 → 取消选中
```

## Formulas

不适用。

## Edge Cases

- **星球位置重叠**: 关卡设计时避免——两颗星 position 太近导致视觉混乱。MVP 不做自动避让
- **连接线交叉**: 同样——关卡设计时手工调整 position 避免交叉
- **大量星球时性能**: MVP 4 颗星，`_draw()` 每帧 ≈ 10 个 draw call，无压力
- **窗口缩放**: MVP 固定分辨率 (1280×720)，不做响应式

## Dependencies

| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 星球系统 | Hard | `get_all_planets()`, `get_adjacent_planets()` |
| 事件总线 | Hard | 订阅 5 个信号 |
| 出征 UI | Soft | 触发发兵流程 |

## Tuning Knobs

| Knob | 说明 |
|------|------|
| 星球半径 | 24px（当前），可调大以适配高分屏 |
| 势力颜色 | PLAYER蓝/ENEMY红/NEUTRAL灰 |
| 连接线宽度 | 2px |

## Acceptance Criteria

- **GIVEN** `planets_initialized` 信号，**WHEN** 星图 UI 渲染，**THEN** 4 颗星 + 3 条连接线可见
- **GIVEN** `planet_owner_changed(3, ENEMY, PLAYER)`，**WHEN** UI 刷新，**THEN** 3 号星从红色变蓝色
- **GIVEN** 点击己方星，**WHEN** 选中，**THEN** 该星显示白色边框，详情面板展示星球信息
- **GIVEN** 选中己方星，**WHEN** 点击相邻敌星，**THEN** 触发出征 UI
- **GIVEN** 选中己方星，**WHEN** 点击非相邻敌星，**THEN** 无响应
- **GIVEN** `game_ended("victory")` 信号，**WHEN** UI 响应，**THEN** 显示"胜利"overlay
