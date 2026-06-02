# Story 003: Presentation 层信号补充

> **Epic**: 事件总线 (event-bus)
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: 0.25h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/event-bus.md`
**Requirement**: 无独立 TR-ID（属于 event-bus 基础设施扩展）

**ADR Governing Implementation**: ADR-0001: 新增 Signal 只追加到文件末尾，不删除不重命名
**ADR Decision Summary**: story-001 声明了 12 个 Foundation+Core 层所需的 Signal。Presentation 层的 star-map-ui / battle-animation / king-ui 在交互流程中需要 3 个额外信号，全部追加到 EventBus 末尾。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Godot 原生 Signal 声明，`signal deployment_requested(from, to)` 等。无引擎 API 依赖。

**Control Manifest Rules (this layer)**:
- Required: Signal 命名：snake_case 过去时 — source: ADR-0001
- Required: 新增 Signal 只追加到文件末尾 — source: ADR-0001
- Forbidden: 禁止修改已有 Signal 名或参数类型 — source: ADR-0001

---

## Acceptance Criteria

- [ ] **AC-1**: GIVEN EventBus autoload，WHEN 查看末尾，THEN `signal deployment_requested(from: int, to: int)` 已声明
- [ ] **AC-2**: GIVEN EventBus autoload，WHEN 查看末尾，THEN `signal animations_complete()` 已声明
- [ ] **AC-3**: GIVEN EventBus autoload，WHEN 查看末尾，THEN `signal king_succession_complete()` 已声明
- [ ] **AC-4**: GIVEN EventBus autoload，WHEN 检查已有 12 个信号，THEN 名称和参数签名未变

---

## Implementation Notes

*Derived from ADR-0001:*

### 追加 3 个信号

在 `event_bus.gd` 末尾追加：

```gdscript
# =========================================================================
# Presentation 层信号 — 追加于 2026-05-31 (event-bus story-003)
# =========================================================================

## 星图触发出兵面板
## from: 出发星球ID  to: 目标星球ID
signal deployment_requested(from: int, to: int)

## 战斗动画全部完成（移动+占领闪烁）
## 无参数 — TurnManager.await 此信号后进入步骤5
signal animations_complete()

## 国王去世弹窗"继续"按钮被点击
## 无参数 — KingUI 关弹窗后 emit，GameState 恢复 PLAYING
signal king_succession_complete()
```

### 调用关系

```
star-map-ui story-002:
  点击相邻敌星 → EventBus.deployment_requested.emit(from, to)
  deployment-ui story-001 监听 → DeploymentPanel.open(from, to)

battle-animation story-001/002:
  全部动画完成 → EventBus.animations_complete.emit()
  TurnManager 监听 → await animations_complete → 进入步骤5

king-ui story-002:
  弹窗"继续" → EventBus.king_succession_complete.emit()
  GameState/KingSystem 监听 → transition_to(PLAYING)
```

### 关键实现要点

- 追加到 `event_bus.gd` 最末尾 — 保证已有信号序号不变
- 参数类型使用 Typed Signal（Godot 4.x 语法：`signal foo(from: int, to: int)`）
- `animations_complete()` 和 `king_succession_complete()` 无参数 — 纯通知信号
- `deployment_requested(from, to)` 两个 int 参数 — 明确传星球 ID
- 不修改 story-001 中已有 12 个信号

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Foundation+Core 层 12 个 Signal 声明
- Story 002: 递归保护 + disconnect 管理
- 具体信号消费者实现（属于各 Presentation story 范围）

---

## QA Test Cases

- **AC-1**: deployment_requested 存在
  - Given: event_bus.gd
  - When: check signal declarations
  - Then: `signal deployment_requested(from: int, to: int)` present at file end

- **AC-2**: animations_complete 存在
  - Given: event_bus.gd
  - When: check signal declarations
  - Then: `signal animations_complete()` present at file end

- **AC-3**: king_succession_complete 存在
  - Given: event_bus.gd
  - When: check signal declarations
  - Then: `signal king_succession_complete()` present at file end

- **AC-4**: 已有信号不变
  - Given: event_bus.gd before and after
  - When: diff
  - Then: only 3 new signals added, zero existing signals modified

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/event-bus/signal_declarations_test.gd` — must pass (追加 3 信号后行数增加)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Foundation event-bus story-001 (12 Signal declarations) — must be DONE
- Depends on: ADR-0001 (EventBus architecture) — must be Accepted
- Required by: star-map-ui story-002, battle-animation story-001/002, king-ui story-002
