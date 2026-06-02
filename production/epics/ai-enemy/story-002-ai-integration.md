# Story 002: AI 参数化 + 回合集成 + 测试矩阵

> **Epic**: AI 敌人 (ai-enemy)
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/ai-enemy.md`
**Requirement**: `TR-AIE-006`

**ADR Governing Implementation**: ADR-0007: AI 决策架构 (参数化难度); ADR-0004: 回合结算模型 (步骤 1 调用 compute_turn)
**ADR Decision Summary**: AI 三参数可调（aggression/defensiveness/intelligence），默认全 0.5。aggression 降低进攻门槛，defensiveness 提高防守保留比例，intelligence 控制兵种选择智能度。AI compute_turn() 在 TurnManager 步骤 1 被调用，通过 PlanetSystem API 读取星球状态，通过 CombatSystem.resolve() 预估战斗。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯集成代码，对接已有 API。参数可持久化到 .tres（Vertical Slice）。

**Control Manifest Rules (this layer)**:
- Required: AI 三参数可调 — aggression/defensiveness/intelligence，默认全 0.5 — source: ADR-0007
- Required: AI 用 CombatSystem.resolve() 预估战斗 — 与真实结算同一公式 — source: ADR-0007
- Forbidden: 禁止 AI 读取玩家未提交指令 — AI 只读实时星球状态 — source: ADR-0007
- Guardrail: 最坏 10星×3邻×3兵种 = 90 次 resolve() < 2ms — source: ADR-0007

---

## Acceptance Criteria

*From GDD `design/gdd/ai-enemy.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN `intelligence=1.0`，WHEN AI 攻击 INFANTRY 驻兵星，THEN 进攻指令使用 CAVALRY（克步兵）
- [ ] **AC-2**: GIVEN `intelligence=0.0`，WHEN AI 选择兵种，THEN 随机选择（非确定性）
- [ ] **AC-3**: GIVEN `aggression=1.0`，WHEN 防御阶段执行，THEN defense_min 仅保留 1（倾巢而出）
- [ ] **AC-4**: GIVEN `aggression=0.0`，WHEN 防御阶段执行，THEN defense_min 保留 max_garrison × 0.5（龟缩）
- [ ] **AC-5**: GIVEN `defensiveness=1.0`，WHEN 威胁评估，THEN 更多星球判定为 HIGH 威胁，防御指令增多
- [ ] **AC-6**: GIVEN `defensiveness=0.0`，WHEN 威胁评估，THEN threat_ratio 阈值降低，更少触发防御
- [ ] **AC-7**: GIVEN aggression=0.3, defensiveness=0.7, intelligence=0.8，WHEN `compute_turn()`，THEN AI 行为倾向防守+智能选兵
- [ ] **AC-8**: GIVEN TurnManager 进入步骤 1 _collect_commands()，WHEN 执行，THEN AIEnemy.compute_turn() 被调用，指令合并到 all_commands
- [ ] **AC-9**: GIVEN AI 指令生成完成，WHEN 回合结算步骤 2-4 执行，THEN AI 指令与玩家指令使用相同的快照+结算流程
- [ ] **AC-10**: GIVEN 36 种参数组合（aggression[0,0.5,1] × defensiveness[0,0.5,1] × planet_setup[4种]），WHEN 验证矩阵，THEN 无崩溃，所有指令 count >= 1，sum(count) <= garrison

---

## Implementation Notes

*Derived from ADR-0007:*

### AI 参数模型

```gdscript
# ai_params.gd — AI 可调参数 Resource（MVP 代码内默认值，Vertical Slice 迁移到 .tres）
class_name AIParams extends RefCounted
var aggression: float = 0.5      # 0=龟缩, 1=倾巢
var defensiveness: float = 0.5   # 0=不防, 1=过度防守
var intelligence: float = 0.5    # 0=随机兵种, 1=最优克制
```

### 参数影响规则

```gdscript
# AIEnemy 扩展 — 本 Story 在 Story 001 基础上添加

var params: AIParams = AIParams.new()

# --- aggression 影响 ---
func _calc_defense_min(planet: Dictionary) -> int:
    # aggression=0 → ratio = 0.5 (保留更多)
    # aggression=0.5 → ratio = 0.3 (默认)
    # aggression=1.0 → ratio = 0.05 ∼ 1 (仅保留 1)
    var ratio := lerpf(0.5, 0.05, params.aggression)
    return maxi(1, int(planet.max_garrison * ratio))

# --- defensiveness 影响威胁评估阈值 ---
func _get_threat_thresholds() -> Dictionary:
    # defensiveness=0.5 → 默认阈值 (HIGH=1.0, MEDIUM=0.5)
    # defensiveness=1.0 → HIGH=0.6, MEDIUM=0.3 (更容易判定为高威胁)
    # defensiveness=0.0 → HIGH=1.5, MEDIUM=0.8 (更不容易触发防御)
    var d := params.defensiveness
    return {
        "high": lerpf(1.5, 0.6, d),
        "medium": lerpf(0.8, 0.3, d),
    }

# --- intelligence 影响兵种选择 ---
func _select_attack_type(target: Dictionary) -> int:
    if randf() < params.intelligence:
        # 智能：选择克制兵种
        var defender_type := target.get("garrison_type", DataDef.UnitType.INFANTRY)
        return DataDef.get_counter(defender_type)
    else:
        # 随机选择
        var types := [DataDef.UnitType.INFANTRY,
                      DataDef.UnitType.ARCHER,
                      DataDef.UnitType.CAVALRY]
        return types[randi() % types.size()]
```

### 回合集成

```gdscript
# TurnManager._collect_commands() — 修改
func _collect_commands() -> Array[DeploymentCommand]:
    var all_commands: Array[DeploymentCommand] = []
    
    # 1. 获取 AI 指令
    var planets := PlanetSystem.get_all_planets()
    var ai_commands := AIEnemy.compute_turn_with_planets(planets)
    all_commands.append_array(ai_commands)
    
    # 2. 获取玩家指令
    var player_commands := DeploymentSystem.get_pending()
    all_commands.append_array(player_commands)
    
    return all_commands
```

### 关键实现要点

- `AIParams` 用 `RefCounted` — 轻量，不需要 Resource 序列化（MVP）
- `aggression` 线性映射 `defense_reserve_ratio`：0→0.5, 0.5→0.3, 1→0.05
- `defensiveness` 线性映射威胁阈值：0→(1.5,0.8), 0.5→(1.0,0.5), 1→(0.6,0.3)
- `intelligence=1.0` 时 `randf() < 1.0` 始终为 true → 总是选克制兵种 → 确定性输出
- `intelligence=0.0` 时 `randf() < 0.0` 始终为 false → 总是随机 → 非确定性
- `compute_turn_with_planets()` 是 `compute_turn()` 的包装：从 PlanetSystem 拉数据 + 注入 `CombatSystem.resolve` Callable
- AI 指令使用与玩家相同的 `DeploymentCommand` 结构（`player_owned=false`）
- 本 Story 不修改 PlanetSystem/CombatSystem — 只通过已有公开 API 调用

### 回合管线（AI 视角）

```
TurnManager.end_turn():
  → transition_to(EXECUTION)
  → 步骤 1: _collect_commands()
      → AIEnemy.compute_turn_with_planets()
        → 从 PlanetSystem 读取实时星球状态（玩家刚部署完的状态）
        → 三阶段决策
        → 返回 Array[DeploymentCommand] (player_owned=false)
      → 合并玩家指令
  → 步骤 2: snapshot = PlanetSystem.take_snapshot()
  → 步骤 3: 基于快照计算全部战斗（AI+玩家统一处理）
  → 步骤 4: 统一 apply 战斗结果
  → ... (后续步骤)
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: 三阶段规则引擎核心（_defense_phase / _offense_phase / _resolve_overdraft）
- CombatSystem: `resolve()` 实现（已由 combat-resolution stories 完成）
- PlanetSystem: `get_all_planets()` / `are_connected()`（已由 planet-system stories 完成）
- TurnManager: `_collect_commands()` / `end_turn()`（已由 Foundation turn-manager 完成；本 Story 可能追加 AI 调用行）
- AI 关卡难度配置: 逐关调高参数（level-data story）

---

## QA Test Cases

### 参数行为测试

- **AC-1**: intelligence=1.0 选克制兵种
  - Given: intelligence=1.0, target 驻兵类型 INFANTRY
  - When: _select_attack_type(target)
  - Then: 返回 CAVALRY（克制步兵）

- **AC-3**: aggression=1.0 倾巢
  - Given: aggression=1.0, max_garrison=20
  - When: _calc_defense_min(planet)
  - Then: 返回 1（仅保留 1 兵）

- **AC-4**: aggression=0.0 龟缩
  - Given: aggression=0.0, max_garrison=20
  - When: _calc_defense_min(planet)
  - Then: 返回 10（20 × 0.5）

- **AC-7**: 组合参数
  - Given: aggression=0.3, defensiveness=0.7, intelligence=0.8
  - When: compute_turn()
  - Then: 防御倾向明显（高 defensiveness）、防守保留较多（低 aggression）、兵种偏智能

### 集成测试

- **AC-8**: TurnManager 步骤 1 调用 AI
  - Given: 初始化完整系统链 (GameState+TurnManager+PlanetSystem+AIEnemy)
  - When: TurnManager.end_turn() → _collect_commands()
  - Then: AI 指令已包含在 all_commands 中

- **AC-9**: AI 指令与玩家指令统一结算
  - Given: 1 条玩家指令 + N 条 AI 指令指向同一天球
  - When: 快照→计算→apply
  - Then: 所有指令基于同一快照结算，结果确定

### 测试矩阵（36 组合）

- **AC-10**: 参数 × 地图组合
  - aggression ∈ {0, 0.5, 1}
  - defensiveness ∈ {0, 0.5, 1}
  - planet_setup ∈ {平等2v2, AI优势3v1, 玩家优势1v3, 全部隔离}
  - Expect: 36 种组合全部无崩溃，每条指令 count >= 1，sum(count) <= garrison

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/ai-enemy/ai_turn_integration_test.gd` — must exist and pass
- Logic: `tests/unit/ai-enemy/ai_params_test.gd` — 参数行为单元测试
- Logic: `tests/unit/ai-enemy/ai_combat_integration_test.gd` — 36 组合矩阵测试

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (ai-engine-core) — must be DONE
- Depends on: Core combat-resolution (TR-CBT-001~004, resolve 纯函数) — must be DONE
- Depends on: Core planet-system (TR-PLT-001~006, get_all_planets + are_connected) — must be DONE
- Depends on: Core deployment-system (TR-DPL-002, DeploymentCommand 结构) — must be DONE
- Depends on: Foundation turn-manager (TR-TRN-001~004, _collect_commands) — must be DONE
- Unlocks: 关卡难度配置 (level-data), AI 行为调优 (balance-check)
