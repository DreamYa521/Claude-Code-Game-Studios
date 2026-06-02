# 战斗动画 (Battle Animation)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ♟️ 从容推演 (结算可视化)
> **Architecture**: [ADR-0004](../docs/architecture/adr/adr-0004-turn-resolution-model.md) (EXECUTION 阶段动画)

## Overview

战斗动画系统在回合结算的 EXECUTION 阶段提供视觉反馈——兵力短线沿连接路线流动、星球占领时闪烁。MVP 不做复杂特效，只做"让玩家看到发生了什么的"极简动画。所有动画在 Godot 的 `Tween` 或 `_draw()` 中实现。

动画不是装饰——它是让回合结算从"数字突然变了"变成"我看到我的兵在移动"的信息传达。

## Player Fantasy

玩家点击"结束回合"→ 看到几条短线从己方星出发，沿连接线流向目标星。目标星闪一下——颜色变了——占领成功。整个过程大约 2-3 秒。简洁、清晰、不拖沓。

## Detailed Rules

### 规则 1: 兵力移动动画

每条执行中的 DeploymentCommand 渲染一条**移动短线**：

| 属性 | 规格 |
|------|------|
| 形状 | 小三角形或短线，沿连接线移动 |
| 颜色 | 与出发星归属方颜色一致（蓝=玩家，红=AI） |
| 大小 | 8-12px |
| 速度 | 300-500px/s（沿路径匀速） |
| 数量 | 1 条短线/指令（不按兵力数缩放） |
| 时机 | EXECUTION 阶段步骤 3-4 期间播放 |

### 规则 2: 动画序列

回合结算期间动画分阶段播放：

```
阶段 1 (收集): 无动画 — 等待 AI 计算（< 100ms）

阶段 2 (快照): 无动画 — 内部操作（< 1ms）

阶段 3 (计算): 无动画 — 内部操作（< 10ms）
    动画信号: execution_phase_started

阶段 4 (应用): 分批播放动画
    所有指令的移动动画同时开始（并行）
    → 每条短线 0.5-1s 到达目标
    → 到达时：若占领 → 目标星闪烁（颜色切换）
                → 兵力数字更新
    → 全部到达 → 动画结束

阶段 5 (收尾): 无动画 — 内部操作
```

### 规则 3: 占领闪烁

当星球归属变更时（`planet_owner_changed`）：

| 属性 | 规格 |
|------|------|
| 效果 | 星球闪烁 3 次（旧颜色→新颜色交替） |
| 持续时间 | 每次闪烁 150ms |
| 总时长 | ~900ms |
| 实现 | `Tween` 或 `_draw()` 颜色插值 |

### 规则 4: 动画速度

`ANIMATION_SPEED = 400px/s`（默认）。连接线长度通常 100-300px → 每条动画 0.25-0.75s。4 条指令并行播放。

### 规则 5: 动画期间玩家不可操作

- EXECUTION 阶段按钮禁用（回合控制 UI 已处理）
- 动画播放期间星图不接受点击
- 全部动画完成后 `turn_ended` 信号发出 → 玩家可操作

### 规则 6: MVP 跳过选项

提供"跳过动画"选项：
- 点击屏幕任意位置 → 全部动画瞬移到终点
- 设置中可勾选"跳过战斗动画"
- 跳过不影响结算结果——纯视觉效果

### States and Transitions

```
回合结算开始:
  按钮禁用

步骤 3 结束 → execution_phase_started:
  → 启动动画协程：
      for each cmd:
        play_move_animation(from_pos, to_pos, faction_color)
        await arrival
        if occupation:
          play_occupation_flash(planet)
  
  全部动画完成:
    → 步骤 5 (收尾)
    → turn_ended 信号
    → 按钮恢复
```

## Formulas

不适用。

## Edge Cases

- **0 条指令**: 无动画 → execution_phase_started → 立即 turn_ended（跳过动画协程）
- **多条指令到同一颗星**: 多条短线先后到达同一点 → 每条到达时可能触发占领闪烁。实际应用中：第一条到达可能已占领（星变蓝），后续到达的进攻方看到已是己方星 → 不触发占领。这反映了正确的游戏逻辑（第一支到达的部队占领了）
- **动画时长 > 5秒**: MVP 最多 20 条指令并行，每条 ≤ 0.75s，不会超 1 秒。若关卡设计导致路径过长（> 2000px）→ 加速动画（上限 1s）
- **动画中断 (跳过)**: 跳过时所有短线瞬移到目标 → 占领闪烁改为单次闪 → 立即进入步骤 5

## Dependencies

| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 出征系统 | Hard | `DeploymentCommand[]`（from_planet, to_planet） |
| 星球系统 | Hard | 星球 position 用于动画起终点 |
| 事件总线 | Hard | 订阅 `execution_phase_started`, `planet_owner_changed` |

## Tuning Knobs

| Knob | 默认值 | 说明 |
|------|--------|------|
| `ANIMATION_SPEED` | 400px/s | 移动速度 |
| 占领闪烁次数 | 3 | 闪烁次数 |
| 占领闪烁间隔 | 150ms | 每次闪烁时长 |
| 默认跳过 | false | 是否默认跳过动画 |

## Acceptance Criteria

- **GIVEN** `execution_phase_started` 信号 + 有 2 条指令，**WHEN** 动画播放，**THEN** 看到 2 条短线沿连接线移动
- **GIVEN** 移动短线到达目标星且 attacker_wins=true，**WHEN** 完成，**THEN** 目标星闪烁（颜色切换）
- **GIVEN** 动画播放中点击屏幕，**WHEN** 响应，**THEN** 全部动画瞬移到终点
- **GIVEN** 0 条指令，**WHEN** `execution_phase_started`，**THEN** 无动画，直接 `turn_ended`
- **GIVEN** 动画全部完成，**WHEN** 检查按钮状态，**THEN** "结束回合"按钮恢复可用
