# Story 002: 去世/继位弹窗 + king_died 事件集成

> **Epic**: 国王 UI (king-ui)
> **Status**: Ready
> **Layer**: Presentation
> **Type**: UI
> **Estimate**: 1h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/king-ui.md`
**Requirement**: `TR-KUI-003`, `TR-KUI-004`

**ADR Governing Implementation**: ADR-0008: 国王去世流程 — emit king_died → GameState→PAUSED → 自动继位 → emit king_succeeded → GameState→PLAYING；ADR-0001: 通过 EventBus 接收 king_died/king_succeeded
**ADR Decision Summary**: 国王去世弹出模态窗口，显示"名字 驾崩，第N代国王，享年N回合"+继承人信息+"继续"按钮。点击继续→GameState 恢复 PLAYING→国王面板刷新为新国王。订阅 king_died/king_succeeded/game_state_changed/action_consumed 四个信号。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Control` + `Label` + `Button`，弹出层用 `show()` + `mouse_filter = MOUSE_FILTER_STOP` 实现模态。非 `Popup` 节点（Popup 在 4.x 中有层级问题）。

**Control Manifest Rules (this layer)**:
- Required: 国王去世流程：emit king_died → GameState→PAUSED → 自动继位 → emit king_succeeded → GameState→PLAYING — source: ADR-0008
- Required: UI 组件全部通过 EventBus 订阅刷新 — 不轮询 — source: ADR-0001

---

## Acceptance Criteria

*From GDD `design/gdd/king-ui.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN `king_died` 信号（国王阿尔萨斯，第1代，lifespan=30），WHEN UI 响应，THEN 弹窗显示："阿尔萨斯 驾崩 / 第1代国王，享年30回合 / 继承人：伊莎贝尔（囤积者）/ 第2代，剩余30回合 / [继续]"
- [ ] **AC-2**: GIVEN 弹窗显示中，WHEN 点击"继续"，THEN 弹窗关闭 → GameState 恢复 PLAYING → 国王面板刷新为新国王（第2代，伊莎贝尔，30/30）
- [ ] **AC-3**: GIVEN 弹窗显示中，WHEN 检查 GameState，THEN current_state == PAUSED（弹窗期间暂停游戏）
- [ ] **AC-4**: GIVEN 无继承人（极端情况），WHEN king_died 信号发射，THEN 显示"末代国王"特殊文本，按钮文字为"结束游戏"
- [ ] **AC-5**: GIVEN PAUSED 状态（国王去世弹窗中），WHEN `end_turn()` 被调用，THEN 返回 false

---

## Implementation Notes

*Derived from ADR-0008 and GDD king-ui.md:*

### 弹窗场景结构

```
KingDeathPopup (Control, 全屏覆盖 + 半透明黑底)
├── ShadePanel (ColorRect, 全屏 #000000 50% alpha, mouse_filter=STOP)
│   └── ModalPanel (Panel, 居中 400×250)
│       ├── DeathTitle ("阿尔萨斯 驾崩")
│       ├── Subtitle ("第 1 代国王，享年 30 回合")
│       ├── Separator (HSeparator)
│       ├── HeirLabel ("继承人：伊莎贝尔（囤积者）")
│       ├── HeirInfo ("第 2 代，剩余 30 回合")
│       └── ContinueButton ([继续])
```

### 核心代码

```gdscript
# king_death_popup.gd
class_name KingDeathPopup extends Control

@onready var _death_title: Label = $ShadePanel/ModalPanel/DeathTitle
@onready var _subtitle: Label = $ShadePanel/ModalPanel/Subtitle
@onready var _heir_label: Label = $ShadePanel/ModalPanel/HeirLabel
@onready var _heir_info: Label = $ShadePanel/ModalPanel/HeirInfo
@onready var _continue_btn: Button = $ShadePanel/ModalPanel/ContinueButton

var _king_system  # KingSystem autoload

func _ready() -> void:
    hide()
    EventBus.king_died.connect(_on_king_died)
    _continue_btn.pressed.connect(_on_continue)

func _on_king_died(king: KingData) -> void:
    # 1. 显示去世信息
    _death_title.text = "%s 驾崩" % king.name
    _subtitle.text = "第 %d 代国王，享年 %d 回合" % [king.generation, king.lifespan]
    
    # 2. 检查继承人
    var heir = _king_system.current_king()  # 继位已完成（king_died emit 前继位）
    
    if heir != null and heir.id != king.id:
        # 正常继位
        var talent_text = _talent_name(heir.talent)
        _heir_label.text = "继承人：%s（%s）" % [heir.name, talent_text]
        _heir_info.text = "第 %d 代，剩余 %d 回合" % [heir.generation, heir.lifespan - heir.actions_used]
        _continue_btn.text = "继续"
    else:
        # 无继承人（极端情况）
        _heir_label.text = "王朝终结，末代国王"
        _heir_info.text = "游戏结束"
        _continue_btn.text = "结束游戏"
    
    show()

func _on_continue() -> void:
    hide()
    # GameState 恢复 PLAYING — 由 KingSystem 在继位流程中处理
    # 若 king_died 已自动触发 PAUSED → 继位 → PLAYING，这里只需关弹窗
    EventBus.king_succession_complete.emit()

func _talent_name(talent: int) -> String:
    match talent:
        DataDef.TalentType.CONQUEROR: return "征服者"
        DataDef.TalentType.RESEARCHER: return "科研者"
        DataDef.TalentType.HOARDER: return "囤积者"
        DataDef.TalentType.DIPLOMAT: return "外交者"
        _: return "未知"
```

### KingSystem 集成流程（参考，不属于本 Story 实现范围）

```
king_died 信号 → EventBus
  ├── KingDeathPopup: 弹出弹窗
  ├── GameState: transition_to(PAUSED)  ← KingSystem 内部处理
  └── KingPanel: hide()（通过 game_state_changed 监听）

玩家点"继续" → KingDeathPopup._on_continue()
  → GameState.transition_to(PLAYING)
  → KingPanel 通过 king_succeeded 刷新为新国王
```

### 关键实现要点

- 弹窗用全屏 `ColorRect` 做半透明遮罩 — `mouse_filter = MOUSE_FILTER_STOP` 阻止点击穿透
- `king_died` 信号的 king 参数包含去世国王信息 — 已由 KingSystem 填充
- 继承人信息从 `KingSystem.current_king()` 读取 — 继位已在 emit 前完成
- MVP 无"末代国王"情况（ADR-0008: AI 无国王，玩家总有继承人） — AC-4 为防御性覆盖
- 弹窗关闭后国王面板通过 `king_succeeded` 信号自动刷新（story-001 已实现）
- GameState PAUSED 状态下回合控制按钮自动隐藏（turn-control-ui 已处理）

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: 国王常驻面板（寿命条、代际、名字）
- KingSystem.consume_turn() / 去世触发 / 继位逻辑 — king-system epic 已实现
- 天赋机制效果（MVP 不做）

---

## QA Test Cases

*Derived from GDD acceptance criteria.*

- **AC-1**: 死亡弹窗显示
  - Given: king_died({name:"阿尔萨斯", generation:1, lifespan:30}) emitted
  - When: KingDeathPopup responds
  - Then: "阿尔萨斯 驾崩", "第1代国王，享年30回合", heir info visible, "继续" button

- **AC-2**: 点击继续
  - Given: popup visible, heir = {name:"伊莎贝尔", talent:HOARDER, generation:2, remaining:30}
  - When: click "继续"
  - Then: popup hidden, GameState→PLAYING, KingPanel shows "第 2 代：囤积者 伊莎贝尔, 30/30"

- **AC-3**: PAUSED 期间 gate
  - Given: popup visible
  - When: check GameState.current_state
  - Then: == PAUSED

- **AC-4**: 无继承人场景
  - Given: king_died emitted but current_king() returns same king (no heir)
  - When: popup renders
  - Then: "王朝终结，末代国王" + "结束游戏" button

- **AC-5**: PAUSED 拒绝 end_turn
  - Given: GameState == PAUSED
  - When: call end_turn()
  - Then: returns false

---

## Test Evidence

**Story Type**: UI
**Required evidence**:
- Manual walkthrough doc: `production/qa/evidence/king-ui-death-popup-walkthrough.md` — must exist
- Screenshots: death popup, after continue showing new king

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (国王常驻面板) — must be DONE
- Depends on: Core king-system (king_died/king_succeeded signals, current_king(), KingData) — must be DONE
- Depends on: Foundation event-bus (king_died, king_succeeded, game_state_changed) — must be DONE
- Depends on: Foundation gamestate-manager (PAUSED/PLAYING state, transition_to()) — must be DONE
