# ADR-0003: GameState 状态机设计

## Status
Accepted

## Date
2026-05-31

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (状态管理) |
| **Knowledge Risk** | LOW — GDScript `enum` + `match` 是 4.0 基础特性，无破坏性变更 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/architecture/architecture.md` Phase 4 |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (状态转换通过 EventBus 广播) |
| **Enables** | 回合管理器、UI 系统、胜负条件 GDD |
| **Blocks** | GameState 管理器 GDD, 回合控制 UI GDD, 胜负条件 GDD |
| **Ordering Note** | 必须在回合管理器和 UI 系统 GDD 之前 Accepted |

## Context

### Problem Statement

游戏需要管理 5 个全局状态（TITLE, PLAYING, PAUSED, VICTORY, DEFEAT），控制哪些系统在何时运行。状态转换必须受规则约束——不能从 TITLE 直接跳到 VICTORY。需要决定：状态机的实现方式。

### Constraints

- 5 个状态，转换规则简单明确
- 回合制游戏，状态切换在秒级粒度，无每帧压力
- 状态转换必须通知所有订阅系统（通过 EventBus）
- 非法转换必须被拒绝并返回 false
- 实现必须可单元测试

### Requirements

- 5 个状态：TITLE, PLAYING, PAUSED, VICTORY, DEFEAT
- 禁止非法转换（如 PLAYING → TITLE，不经过菜单）
- 每次合法转换广播 `EventBus.game_state_changed`
- 提供快捷查询方法 `is_playing()`, `is_game_over()`

## Decision

**使用 GDScript `enum` + `match` 实现状态机。**

`GameState` autoload 持有当前状态枚举，`transition_to()` 验证转换矩阵后执行转换并通过 EventBus 广播。

### Architecture Diagram

```
                    ┌──────────┐
           ┌───────→│  TITLE   │←───────┐
           │        └────┬─────┘        │
           │   start     │              │ restart
           │             ▼              │
           │        ┌──────────┐        │
           │  resume│ PLAYING  │───────→│
           │   ┌────│          │──┐     │
           │   │    └──────────┘  │     │
           │   │                  │     │
           │   ▼ pause       win  │ lose│
           │ ┌──────────┐         │     │
           │ │  PAUSED  │    ┌────▼──┐  │
           │ └──────────┘    │VICTORY│  │
           │                 └───────┘  │
           │                 ┌───────┐  │
           │                 │DEFEAT │──┘
           │                 └───────┘
           └──────────────────────────┘
```

### Key Interfaces

```gdscript
# game_state.gd — autoload: GameState
extends Node

enum State { TITLE, PLAYING, PAUSED, VICTORY, DEFEAT }

var current_state: State = State.TITLE:
    get

func transition_to(new_state: State) -> bool:
    if not _is_valid(current_state, new_state):
        push_warning("Invalid transition: %s → %s" % [current_state, new_state])
        return false
    var old = current_state
    current_state = new_state
    EventBus.game_state_changed.emit(old, new_state)
    return true

func is_playing() -> bool:
    return current_state == State.PLAYING

func is_game_over() -> bool:
    return current_state == State.VICTORY or current_state == State.DEFEAT

func _is_valid(from: State, to: State) -> bool:
    match [from, to]:
        [State.TITLE, State.PLAYING]:
            return true
        [State.PLAYING, State.PAUSED]:
            return true
        [State.PLAYING, State.VICTORY]:
            return true
        [State.PLAYING, State.DEFEAT]:
            return true
        [State.PAUSED, State.PLAYING]:
            return true
        [State.VICTORY, State.TITLE]:
            return true
        [State.DEFEAT, State.TITLE]:
            return true
        _:
            return false
```

### 状态转换矩阵

| 从 \ 到 | TITLE | PLAYING | PAUSED | VICTORY | DEFEAT |
|---------|-------|---------|--------|---------|--------|
| TITLE   | —     | ✅      | ❌     | ❌      | ❌     |
| PLAYING | ❌    | —       | ✅     | ✅      | ✅     |
| PAUSED  | ❌    | ✅      | —      | ❌      | ❌     |
| VICTORY | ✅    | ❌      | ❌     | —       | ❌     |
| DEFEAT  | ✅    | ❌      | ❌     | ❌      | —      |

### 使用示例

```gdscript
# 回合控制 UI — 结束回合按钮
func _on_end_turn_pressed() -> void:
    TurnManager.end_turn()
    # 胜负检查在 TurnManager 内部触发

# 暂停菜单 — 继续按钮
func _on_resume_pressed() -> void:
    GameState.transition_to(GameState.State.PLAYING)

# 任意系统 — 查询状态
func _process(_delta: float) -> void:
    if not GameState.is_playing():
        return  # 只在 PLAYING 状态运行逻辑
```

## Alternatives Considered

### Alternative 1: Node 状态机

- **Description**: 每个状态是一个 `Node` 子节点，通过 `add_child`/`remove_child` 切换，每个状态节点有 `_enter()` / `_exit()` 回调
- **Pros**: 状态自身可以有子节点树，适合状态对应不同场景布局的情况
- **Cons**: 5 个简单状态各自创建一个 Node，代码量大；状态间无子场景差异，Node 优势不发挥；remove/add child 比 enum 赋值重
- **Rejection Reason**: 本项目所有状态共享同一星图场景。UI 变化通过 Control 节点显隐处理，不需要切换场景树。

### Alternative 2: State 类模式

- **Description**: `BaseState` 类（`enter()`, `exit()`），5 个状态各自继承。`current_state.exit()` → `current = new` → `current.enter()`
- **Pros**: 每个状态可携带复杂逻辑；符合 OOP 设计模式
- **Cons**: 6 个文件表达 5 个简单状态；状态逻辑极简，类层次杀鸡用牛刀；新人需读 6 个文件理解简单状态流
- **Rejection Reason**: 本项目的状态只有"允许/禁止某些系统运行"一个职责，且回合制下无 `update()` 需求。复杂度收益比为负。

## Consequences

### Positive

- **极简**: 约 30 行代码表达完整状态机和转换规则
- **可测试**: 纯逻辑，`transition_to()` 返回值可直接 assert，不依赖场景树
- **类型安全**: `State` 枚举编译期检查，`match` 穷举模式 Godot 可警告遗漏分支
- **广播自动**: 每次合法转换自动 emit `EventBus.game_state_changed`，订阅方无需关心转换细节

### Negative

- **添加状态需改 match**: 如果未来新增状态（如 LOADING），需修改 `_is_valid()` 的 match 表。缓解：5 个 MVP 状态已覆盖完整循环
- **无 enter/exit 钩子**: 没有"进入 PAUSED 时自动暂停所有 Timer"这种自动机制。缓解：订阅系统各自监听 `game_state_changed` 自行处理——事件解耦的设计意图

### Risks

- **非法转换静默失败**: `return false` 可能被调用方忽略。缓解：`push_warning()` 开发阶段可见
- **直接赋值绕过**: 理论上代码可以访问 setter 绕过 `transition_to()`。缓解：`current_state` 只暴露 getter；code review 执行

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| GameState 管理器 | 5 状态全局管理 | `enum State` + `transition_to()` 集中控制 |
| 回合管理器 | PLAYING 状态下接受部署指令 | `is_playing()` 查询，`transition_to()` gate |
| 胜负条件 | 触发 VICTORY/DEFEAT 转换 | `transition_to(VICTORY/DEFEAT)` 唯一路径 |
| 回合控制 UI | 结束回合按钮在 PLAYING 外禁用 | `is_playing()` 驱动按钮 enabled 状态 |
| 国王 UI | TITLE/PAUSED 状态隐藏 | 监听 `game_state_changed` 控制显隐 |

## Performance Implications

- **CPU**: 枚举比较 + match 是 O(1)，无测量意义
- **Memory**: 一个 `enum` 变量 + 一个 `match` 函数 ≈ 0 开销
- **Load Time**: 无
- **Network**: 不适用

## Migration Plan

不适用 — 新项目。

## Validation Criteria

- `transition_to()` 合法转换返回 true，`current_state` 更新正确
- `transition_to()` 非法转换返回 false，`current_state` 不变
- 每次合法转换触发 `EventBus.game_state_changed.emit(old, new)`
- `is_playing()` 和 `is_game_over()` 返回正确值
- 单元测试覆盖全部 7 条合法转换 + 至少 3 条非法转换

## Related Decisions

- ADR-0001: 事件总线架构 — 状态转换通过 `EventBus.game_state_changed` 广播
- ADR-0004: 回合结算模型 — 结算在 PLAYING 状态下执行
- `docs/architecture/architecture.md` — Phase 3 数据流场景 1 (初始化: TITLE→PLAYING), Phase 4 状态转换矩阵
