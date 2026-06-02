# Interaction Pattern Library — 星辰之轭 Part 2

**Version**: 1.0 — MVP (2026-06-02)
**Scope**: Demo（拖线发兵+占点产兵+全歼制胜）

---

## Pattern 1: Click-to-Select

**Where**: 星图上的星球

**Behavior**:
- 点击星球 → 选中（白色 2px 边框）
- 再次点击同星球 → 取消选中
- 点击空白 → 取消选中
- 选中己方星 → 自动高亮相邻敌星（金色 2px 边框）
- 选中敌方/中立星 → 仅选中，不高亮

**Keyboard**: Esc = 取消选中

**Visual**: 即时边框变化，无动画

---

## Pattern 2: Select-then-Act（两步操作）

**Where**: 发兵流程

**Behavior**:
- Step 1: 点击己方星（选中源）
- Step 2: 点击相邻敌星（目标） → 弹出出征面板
- Step 3: 调整兵力滑块 → 确认/取消

**Rationale**: 两步操作消除误触 — 发兵是重要决策，不应该一键触发。MVP 用点击两步，不做拖拽（降低实现复杂度）。

---

## Pattern 3: Slider with Immediate Feedback

**Where**: 出征面板

**Behavior**:
- 拖动滑块 → 数字即时更新
- 联动更新"出发星剩余兵力"
- 范围 1～garrison，默认拉到最大值
- 确认前不产生任何效果

**Keyboard**: ←/→ 微调（MVP 暂不做）

---

## Pattern 4: Modal Overlay

**Where**: 出征面板、国王去世弹窗、胜利/失败 overlay

**Behavior**:
- 弹出时覆盖半透明暗色背景（`#000000` 50%）
- 背景点击不关闭（意图明确）
- Esc = 取消（出征面板）/ 无操作（胜利 overlay 不接受取消）
- 其他 UI 交互被阻止

---

## Pattern 5: State-Dependent Button

**Where**: 回合控制按钮

**Behavior**:

| 状态 | 按钮 | 说明 |
|------|------|------|
| 可用 | 蓝色、可点击 | 仅在 DEPLOYMENT |
| 禁用 | 灰色、不可点击 | EXECUTION/CLEANUP |
| 隐藏 | 完全消失 | 非 PLAYING |

**双击保护**: 点击时第一时间 `disabled=true`，防止双击触发两次。

---

## Pattern 6: Event-Driven Refresh

**Where**: 所有 UI 组件

**Behavior**:
- 不轮询状态（不用 `_process()` 每帧检查）
- 订阅 EventBus 信号，仅在信号触发时 `queue_redraw()`
- 国王面板、星图、回合控制全部遵循此模式

---

## Pattern 7: Keyboard Accessibility

**Where**: 全局

**Shortcuts**:

| 操作 | 快捷键 | 说明 |
|------|--------|------|
| 结束回合 | Space / E | 仅 DEPLOYMENT |
| 取消 | Esc | 取消选中/关闭面板 |
| 确认 | Enter | 出征面板内 |

**Design Rule**: 所有核心操作必须有键盘路径，不允许纯鼠标操作。

---

## Anti-Patterns (Forbidden)

| ❌ | 原因 |
|----|------|
| 拖拽发兵（MVP） | 实现复杂度高 — 点击两步操作足够清晰 |
| 悬停预览 | 不做悬停交互 — 无法用键盘触发 |
| 右键菜单 | 增加认知负担 — 所有操作显式可见 |
| 双击操作 | 单机目标受众不习惯双击 |
| 长按操作 | 回合制无时间压力 |
| Toast/通知弹窗 | 分散注意力 — 用持久状态指示代替 |
