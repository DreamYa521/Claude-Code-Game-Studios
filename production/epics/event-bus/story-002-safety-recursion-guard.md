# Story 002: EventBus Safety — Recursion Guard & Subscription Lifecycle

> **Epic**: event-bus
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: 1.5h
> **Manifest Version**: 2026-05-31
> **Last Updated**: —

## Context

**GDD**: `design/gdd/event-bus.md`
**Requirement**: TR-EVT-004, TR-EVT-005
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0001: 事件总线架构
**ADR Decision Summary**: EventBus 不含业务逻辑 — 只转发 Signal。但需要两个安全机制：(1) 递归 emit 检测防止 `turn_ended` → callback → `turn_ended` 无限循环；(2) 订阅生命周期规范确保短期连接正确释放。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Godot Signal `emit()` 遍历订阅列表的快照，回调中 disconnect 不影响当前遍历。信号连接在节点释放时自动清理（对 autoload 长期订阅方适用）。

**Control Manifest Rules (this layer)**:
- Required: 长期订阅在 `_ready()` 中 `connect()`，短期订阅在 `_exit_tree()` 中显式 `disconnect()`
- Required: 检测 Signal 回调中递归 emit 同一 Signal → `push_error()` + 阻止第二次 emit
- Forbidden: 禁止在 EventBus callback 中再次 emit 同一 Signal（防止无限递归）
- Forbidden: Signal 参数类型全部来自 DataDef，无裸 String/int

---

## Acceptance Criteria

*From GDD `design/gdd/event-bus.md`, scoped to this story:*

- [ ] **AC-1**: Signal callback 中再次 emit 同一 Signal，EventBus 检测递归，`push_error()` 触发 + 第二次 emit 被阻止
- [ ] **AC-2**: 两个独立系统 A 和 B，A 发送事件、B 接收事件，A 不持有 B 的引用（B 只 connect EventBus）
- [ ] **AC-3**: 长期订阅方在 `_ready()` 中 `connect()`，短期订阅方必须显式 `disconnect()`（文档 + 代码审查规则生效）

---

## Implementation Notes

*Derived from ADR-0001:*

**1. 递归 emit 检测实现**:

在 EventBus 中添加轻量级的递归检测包装器。由于 Godot Signal 不支持自定义 emit 逻辑，使用 `emit_signal_wrapper` 模式：

```gdscript
# event_bus.gd — 追加内容（在 Story 001 的 Signal 声明基础上）

# 递归检测：追踪当前正在 emit 的 Signal 集合
var _emitting: Dictionary = {}  # {signal_name: bool}

## 安全版本 emit 包装 — 检测递归，防止无限循环
func safe_emit(signal_name: String, args: Array) -> void:
    if _emitting.get(signal_name, false):
        push_error("EventBus: Recursive emit detected for signal '%s' — blocked." % signal_name)
        return
    
    _emitting[signal_name] = true
    # 注意：Godot 原生 Signal.emit() 不支持通过字符串调用
    # 实际实现采用手动 connect 机制或 match 分发
    # 详见下方"方案选择"
    _emitting[signal_name] = false
```

**方案选择**: Godot 原生 Signal 的 `emit()` 无法被拦截（它在引擎层执行）。推荐的递归防护方案：

- **方案 A（推荐用于 MVP）**: 文档约定 + Code Review 执行。在 `event_bus.gd` 顶部添加醒目的注释警告 "禁止在 callback 中再次 emit 同一 Signal"。在 Godot 原生 Signal 机制下，递归会被引擎层的 emit 快照机制自然阻止（同一 Signal 在遍历订阅列表时，新添加的 emit 会排队在当前遍历完成后执行，不会形成真正的无限递归）。因此 MVP 阶段依赖 Godot 自身保护即可。
- **方案 B（如需主动检测）**: 在 EventBus 中添加一个 Dictionary 追踪，所有发送方不直接调用 `EventBus.signal_name.emit()`，而是通过 EventBus 提供的 `emit_safe(signal_name, ...)` 方法。这需要每个 Signal 配对一个字符串名。各系统代码中显式调用 `EventBus.emit_safe("planet_owner_changed", [planet_id, old, new])` 而非 `EventBus.planet_owner_changed.emit(planet_id, old, new)`。

**本 Story 采用方案 A + 文档警告**。MVP 阶段 Godot 引擎自带的 emit 机制已足够安全。代码审查规则确保开发者不写出 `turn_ended` → callback → `turn_ended` 这类模式。

**2. 订阅生命周期规范**（约定文档，写入 event_bus.gd 注释和 Story 引用）:

```gdscript
## ============================================================================
## 订阅生命周期规则
## ============================================================================
## 长期订阅方 (autoload, 主场景节点):
##   - 在 _ready() 中 connect()
##   - 无需手动 disconnect() — Godot 在节点释放时自动清理
##
## 短期订阅方 (临时弹窗, 确认对话框):
##   - 在 _exit_tree() 或销毁前显式 disconnect()
##   - 示例:
##       func _ready():
##           EventBus.game_state_changed.connect(_on_state_changed)
##       func _exit_tree():
##           EventBus.game_state_changed.disconnect(_on_state_changed)
##
## 订阅方 callback 中禁止再次 emit 同一 Signal
## ============================================================================
```

**3. 跨系统零耦合验证方法**:
- 任意系统 .gd 文件搜索 `[OtherSystemName].signal.connect(` 模式 → 必须无匹配
- 唯一允许的 connect 模式: `EventBus.[signal_name].connect()`
- 系统内部通信（同一系统内 Signal）不受此限

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Signal 声明、命名规范、类型约束、autoload 注册
- 具体发送/订阅逻辑实现（属于各消费系统 — 星球系统、回合管理器、国王系统等）

---

## QA Test Cases

- **AC-1**: 递归 emit 检测（文档 + Code Review）
  - Given: event_bus.gd 文件
  - When: 搜索递归 emit 相关注释和警告
  - Then: 文件顶部存在明确注释 "禁止在 callback 中再次 emit 同一 Signal"；或实现 `_emitting` 追踪 Dictionary
  - Edge cases: 如果采用追踪 Dictionary 实现：构造测试 — connect callback → callback 中 emit 同一 Signal → 第二次 emit 被 push_error 阻止

- **AC-2**: 系统间零直接引用验证
  - Given: 任意两个系统文件（如 `planet_system.gd` 和 `star_map_ui.gd`）
  - When: 搜索 `planet_system.` 或 `star_map_ui.` 形式的跨系统引用
  - Then: 无 `[SystemName].signal.connect()` 模式；只存在 `EventBus.[signal_name].connect()`
  - Edge cases: 允许 `EventBus.planet_owner_changed.connect(_on_owner_changed)` 模式

- **AC-3**: 订阅生命周期文档
  - Given: `event_bus.gd` 或项目编码规范文档
  - When: 阅读订阅生命周期部分
  - Then: 明确描述长期/短期订阅方的 connect/disconnect 规则；包含代码示例
  - Edge cases: 实际代码中短期订阅方（临时 UI）必须在 `_exit_tree()` 中有对应的 `disconnect()` 调用

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/event-bus/test_safety_guard.gd` — must exist and pass
  - 测试递归 emit 被阻止（如采用方案 B）
  - 或将此 test 标记为 ADVISORY（如采用方案 A 仅文档约定）

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: EventBus Story 001 (Signal Declarations) — 在本 Story 的 event_bus.gd 基础上添加安全机制
- Unlocks: None（event-bus Epic 最后一个 Story；解锁所有下游系统的跨系统通信）
