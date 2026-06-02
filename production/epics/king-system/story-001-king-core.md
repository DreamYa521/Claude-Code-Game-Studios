# Story 001: KingData 结构 + consume_turn() + 去世/继位核心

> **Epic**: 国王系统 (king-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/king-system.md`
**Requirement**: `TR-KNG-001`, `TR-KNG-002`, `TR-KNG-003`, `TR-KNG-004`, `TR-KNG-005`, `TR-KNG-006`, `TR-KNG-008`

**ADR Governing Implementation**: ADR-0008: 国王寿命模型 (行动次数寿命、自动继位、MVP 天赋标签)
**ADR Decision Summary**: 基于行动次数的寿命模型 — `consume_turn()` 消耗 1，`actions_remaining == 0` 时去世。去世流程：暂停→广播 king_died→自动继位→广播 king_succeeded→恢复。MVP 天赋仅为标签（talent_bonus 留空 {}），Vertical Slice 填充效果。初始 lifespan=30（可配置）。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯 GDScript 数据模型 + 字符串操作，无引擎 API 依赖。名字池用 const Array[String]。

**Control Manifest Rules (this layer)**:
- Required: KingData 结构 — name/talent/lifespan/actions_used/age/generation/talent_bonus — source: ADR-0008
- Required: 每回合消耗 1 寿命 — `consume_turn()` 在 CLEANUP 步骤 5 调用 — source: ADR-0008
- Required: 国王去世流程 — emit king_died → GameState→PAUSED → 自动继位 → emit king_succeeded → GameState→PLAYING — source: ADR-0008
- Required: MVP 天赋仅为标签 — talent_bonus Dictionary 留空 `{}` — source: ADR-0008

---

## Acceptance Criteria

*From GDD `design/gdd/king-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 游戏启动，WHEN `init_king()` 完成，THEN `current_king != null`, `generation == 1`, `actions_remaining() == 30`, `is_alive() == true`
- [ ] **AC-2**: GIVEN `consume_turn()` 调用 1 次，WHEN 完成，THEN `actions_remaining()` 减少 1（29 → 28...）
- [ ] **AC-3**: GIVEN `consume_turn()` 调用 29 次（初始 30），WHEN 第 29 次完成，THEN `is_alive() == true`, `actions_remaining() == 1`
- [ ] **AC-4**: GIVEN `consume_turn()` 调用 30 次（初始 30），WHEN 第 30 次完成，THEN `is_alive() == false`
- [ ] **AC-5**: GIVEN 国王去世，WHEN `_generate_heir()` 完成，THEN `generation == 2`, `actions_remaining() == 30`, `actions_used == 0`, 新国王名字 ≠ 旧国王名字
- [ ] **AC-6**: GIVEN 连续 2 代国王各活 30 回合，WHEN 第 2 代国王去世后继位，THEN `generation == 3`
- [ ] **AC-7**: GIVEN 初始国王，WHEN 检查 talent_bonus，THEN talent_bonus 为空 Dictionary `{}`
- [ ] **AC-8**: GIVEN 初始国王，WHEN 检查 talent，THEN talent 是有效 TalentType 枚举值之一
- [ ] **AC-9**: GIVEN 初始国王，WHEN 检查 name，THEN name 来自名字池（非空字符串）

---

## Implementation Notes

*Derived from ADR-0008 and GDD king-system.md:*

### KingData 结构

```gdscript
# king_data.gd
class_name KingData extends RefCounted
var name: String = ""
var talent: int = 0              # DataDef.TalentType
var lifespan: int = 30           # KING_DEFAULT_LIFESPAN
var actions_used: int = 0
var generation: int = 1
var talent_bonus: Dictionary = {}  # MVP 空，Vertical Slice 填入效果

func actions_remaining() -> int:
    return lifespan - actions_used

func is_alive() -> bool:
    return actions_remaining() > 0

## 代际内年龄（= actions_used，从 0 起计）
func age() -> int:
    return actions_used
```

### 核心函数

```gdscript
# king_system.gd (本 Story 为独立类，不依赖 autoload)
class_name KingSystem

const KING_DEFAULT_LIFESPAN := 30
const MALE_NAMES := ["阿尔萨斯", "伊耿", "洛萨", "泰瑞纳斯", "瓦里安",
                      "凯尔萨斯", "乌瑟尔", "安东尼达斯", "图拉扬", "达纳斯"]
const FEMALE_NAMES := ["伊莎贝尔", "吉安娜", "希尔瓦娜斯", "艾蕾莉亚",
                        "维伦妮", "奥蕾莉亚", "莉亚德琳", "泰兰德", "玛维", "阿莱克斯塔萨"]

var current_king: KingData = null
var generation_count: int = 0

## 游戏启动时创建初始国王
func init_king() -> KingData:
    var king := KingData.new()
    king.name = _random_name()
    king.talent = _random_talent()
    king.lifespan = KING_DEFAULT_LIFESPAN
    king.actions_used = 0
    king.generation = 1
    king.talent_bonus = {}
    current_king = king
    generation_count = 1
    return king

## 每回合在 CLEANUP 步骤 5 调用
## 返回: KingDied | KingAlive | KingSucceeded
func consume_turn() -> int:
    if current_king == null:
        return KingResult.NO_KING
    
    current_king.actions_used += 1
    
    if not current_king.is_alive():
        return KingResult.DIED
    
    return KingResult.ALIVE

## 去世后生成继承人
func generate_heir() -> KingData:
    var old := current_king
    var heir := KingData.new()
    heir.name = _random_name()
    heir.talent = _random_talent()
    heir.lifespan = KING_DEFAULT_LIFESPAN
    heir.actions_used = 0
    heir.generation = old.generation + 1
    heir.talent_bonus = {}
    current_king = heir
    generation_count = heir.generation
    return heir

func is_alive() -> bool:
    return current_king != null and current_king.is_alive()

func actions_remaining() -> int:
    if current_king == null:
        return 0
    return current_king.actions_remaining()

## --- 内部 ---

func _random_name() -> String:
    var pool := MALE_NAMES + FEMALE_NAMES
    return pool[randi() % pool.size()]

func _random_talent() -> int:
    var talents := [
        DataDef.TalentType.CONQUEROR,
        DataDef.TalentType.RESEARCHER,
        DataDef.TalentType.HOARDER,
        DataDef.TalentType.DIPLOMAT,
    ]
    return talents[randi() % talents.size()]
```

### 关键实现要点

- `KingData` 用 `RefCounted` 而不是 `Resource` — 避免深拷贝语义问题
- `KingResult` 枚举：`NO_KING / ALIVE / DIED` — 由本 Story 定义（或添加到 DataDef）
- `consume_turn()` 不直接触发继位 — 仅返回 DIED 状态，继位由回合管线（Story 002）调用 `generate_heir()` 完成
- 名字池硬编码在 KingSystem 中 — MVP 不做外部配置（Vertical Slice 可迁移到 .tres）
- `randi()` 用于名字和天赋随机 — MVP 可接受（后续通过种子控制再现性）
- `talent_bonus` 初始化为 `{}`，预留接口但不实现任何效果
- 本 Story 不依赖 EventBus、GameState、TurnManager — 纯数据模型 + 逻辑，可独立测试

### 测试数据构造

```gdscript
func test_king_lifecycle():
    var ks := KingSystem.new()
    
    # 初始国王
    var king = ks.init_king()
    assert(king.generation == 1)
    assert(ks.actions_remaining() == 30)
    assert(ks.is_alive())
    
    # 消耗 30 回合
    for i in range(30):
        ks.consume_turn()
    
    assert(not ks.is_alive())
    
    # 继位
    var heir = ks.generate_heir()
    assert(heir.generation == 2)
    assert(ks.actions_remaining() == 30)
    assert(ks.is_alive())
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: TurnManager CLEANUP 步骤 5 集成、EventBus (king_died / king_succeeded / action_consumed) 广播、GameState (PAUSED/PLAYING) 过渡、去世警告阈值 (actions_remaining ≤ 3)、边界处理
- 国王 UI: 名字/天赋/寿命条/警告显示（presentation layer）
- DataDef: TalentType 枚举、KING_DEFAULT_LIFESPAN 常量（已在 Foundation 中定义；本 Story 可内联常量做隔离测试）

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: 初始国王
  - Given: KingSystem 刚创建
  - When: `init_king()`
  - Then: current_king != null; generation == 1; actions_remaining() == 30; is_alive() == true

- **AC-2**: 单次消耗
  - Given: 初始 30 寿命
  - When: consume_turn()
  - Then: actions_remaining() == 29

- **AC-3**: 29 次后仍存活
  - Given: 初始 30 寿命
  - When: consume_turn() × 29
  - Then: is_alive() == true; actions_remaining() == 1

- **AC-4**: 30 次后去世
  - Given: 初始 30 寿命
  - When: consume_turn() × 30
  - Then: is_alive() == false

- **AC-5**: 继位后代际递增
  - Given: 国王已去世
  - When: generate_heir()
  - Then: generation == 2; actions_remaining() == 30; actions_used == 0; name != old_name

- **AC-6**: 连续 3 代
  - Given: init → consume×30 → heir (gen2) → consume×30 → heir (gen3)
  - When: 检查 generation
  - Then: generation == 3

- **AC-7**: MVP 天赋为空效果
  - Given: 初始国王
  - When: 检查 talent_bonus
  - Then: talent_bonus == {} (empty Dictionary)

- **AC-8**: 天赋为有效枚举
  - Given: init_king()
  - When: 检查 talent
  - Then: talent in [CONQUEROR, RESEARCHER, HOARDER, DIPLOMAT]

- **AC-9**: 名字非空
  - Given: init_king()
  - When: 检查 name
  - Then: name is non-empty String

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/king-system/king_core_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Foundation data-definitions (TR-DEF-008 TalentType 枚举, KING_DEFAULT_LIFESPAN 常量) — must be DONE
- Unlocks: Story 002 (king-integration)
