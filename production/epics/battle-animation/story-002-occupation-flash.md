# Story 002: 占领闪烁 + 动画序列集成

> **Epic**: 战斗动画 (battle-animation)
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Visual/Feel
> **Estimate**: 1h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/battle-animation.md`
**Requirement**: `TR-BAN-002`, `TR-BAN-003`

**ADR Governing Implementation**: ADR-0004: 动画序列 execution_phase_started→parallel move→occupation flash→all done→turn_ended
**ADR Decision Summary**: 移动动画到达目标星时，若占领成功 → 星球闪烁3次（旧颜色↔新颜色交替），每次150ms，总~900ms。所有指令的移动+占领全部完成后 emit turn_ended。并行播放：所有指令的移动同时开始，各指令到达时各自的占领闪烁立即开始（不互相等待）。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `_process(delta)` 控制闪烁计数器。闪烁效果通过切换 `_draw()` 中的星球颜色实现（叠加一个闪烁颜色层）。

**Control Manifest Rules (this layer)**:
- Required: 占领闪烁：3次(旧色↔新色交替)，每次150ms，总~900ms — source: ADR-0004
- Required: 并行播放+先后到达：各指令到达时各自的占领闪烁立即开始 — source: ADR-0004

---

## Acceptance Criteria

*From GDD `design/gdd/battle-animation.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 玩家兵到达火星(原ENEMY红) + attacker_wins=true，WHEN 占领，THEN 火星闪烁 3 次（红色↔蓝色交替），每次 150ms
- [ ] **AC-2**: GIVEN 玩家兵到达月球(原NEUTRAL灰) + attacker_wins=true，WHEN 占领，THEN 月球闪烁 3 次（灰色↔蓝色交替）
- [ ] **AC-3**: GIVEN 2 条指令分别攻击火星和月球，先到达的一条立即开始闪烁，后到达的不等待先前的闪烁完成
- [ ] **AC-4**: GIVEN 所有动画（所有移动+所有占领闪烁）完成，WHEN 检查，THEN `animations_complete` 信号已 emit
- [ ] **AC-5**: GIVEN 士兵到达但 attacker_wins=false（防守方胜），WHEN 处理，THEN 该星球不闪烁

---

## Implementation Notes

*Derived from ADR-0004 and GDD battle-animation.md:*

### 扩展 BattleAnimator（在 story-001 基础上）

```gdscript
# battle_animator.gd — 在 story-001 基础上添加

const FLASH_COUNT := 3
const FLASH_DURATION := 0.15  # 150ms per flash

var _flashes: Array = []  # [{planet_id, old_color, new_color, flash_index, timer}]

func _setup_animations(commands: Array, battle_results: Dictionary) -> void:
    _animations.clear()
    _flashes.clear()
    
    for cmd in commands:
        var from_planet = _planet_system.get_planet(cmd.from_planet)
        var to_planet = _planet_system.get_planet(cmd.to_planet)
        
        var color = COLOR_PLAYER if cmd.player_owned else COLOR_ENEMY
        
        # 检查是否有战斗结果（occupy 信息）
        var result = battle_results.get(cmd.id, null)
        var will_occupy = result != null and result.attacker_wins
        
        _animations.append({
            "from_pos": from_planet.position,
            "to_pos": to_planet.position,
            "color": color,
            "t": 0.0,
            "duration": _calc_duration(from_planet.position, to_planet.position),
            "completed": false,
            "planet_id": to_planet.id,
            "will_occupy": will_occupy,
            "old_owner": to_planet.owner,  # 旧归属（快照时的颜色）
            "flash_started": false,
        })

func _process(delta: float) -> void:
    if not _is_playing:
        return
    
    # 移动动画更新
    var all_move_done = true
    for anim in _animations:
        if anim.completed:
            continue
        anim.t += delta / anim.duration
        if anim.t >= 1.0:
            anim.t = 1.0
            anim.completed = true
            # 到达时：若需占领，启动闪烁
            if anim.will_occupy and not anim.flash_started:
                anim.flash_started = true
                _start_flash(anim.planet_id, anim.old_owner,
                    _planet_system.get_planet(anim.planet_id).owner)
        else:
            all_move_done = false
    
    # 闪烁动画更新
    for flash in _flashes:
        flash.timer += delta
        if flash.timer >= FLASH_DURATION:
            flash.timer -= FLASH_DURATION
            flash.flash_index += 1
    
    # 清理已完成的闪烁
    _flashes = _flashes.filter(func(f): return f.flash_index < FLASH_COUNT * 2)
    
    queue_redraw()
    
    if all_move_done and _flashes.is_empty():
        _on_all_completed()

func _start_flash(planet_id: int, old_owner: int, new_owner: int) -> void:
    _flashes.append({
        "planet_id": planet_id,
        "old_color": _owner_to_color(old_owner),
        "new_color": _owner_to_color(new_owner),
        "flash_index": 0,
        "timer": 0.0,
    })

func _owner_to_color(owner: int) -> Color:
    match owner:
        DataDef.Faction.PLAYER: return COLOR_PLAYER
        DataDef.Faction.ENEMY: return COLOR_ENEMY
        _: return COLOR_NEUTRAL

func _draw() -> void:
    if not _is_playing:
        return
    
    # 画移动短线（story-001）
    for anim in _animations:
        _draw_moving_line(anim)
    
    # 画占领闪烁覆盖层
    for flash in _flashes:
        _draw_flash(flash)

func _draw_flash(flash: Dictionary) -> void:
    var planet = _planet_system.get_planet(flash.planet_id)
    var pos = planet.position
    
    # 闪烁: 偶数帧旧色，奇数帧新色
    var color = flash.old_color if (flash.flash_index % 2 == 0) else flash.new_color
    
    # 半透明覆盖圈（比星球略大）
    draw_circle(pos, PLANET_RADIUS + 3, Color(color, 0.6))

func _on_all_completed() -> void:
    _is_playing = false
    _animations.clear()
    _flashes.clear()
    queue_redraw()
    EventBus.animations_complete.emit()
```

### 动画时间线示意

```
Time →
  指令1: |████████⚡⚡⚡|           ← 移动0.5s + 闪烁0.9s = 1.4s
  指令2: |██████████████⚡⚡⚡|     ← 移动0.75s + 闪烁0.9s = 1.65s
  指令3: |███⚡⚡⚡|               ← 移动0.25s + 闪烁0.9s = 1.15s

  animations_complete → 最长的链完成 (1.65s)
```

### 关键实现要点

- `battle_results` 由 TurnManager 步骤 4 传入 — 在 `_apply_results()` 后再设置动画
- 闪烁用 `_draw()` 覆盖层实现 — 不修改底层星球数据
- 每条动画各自独立计时 — 到达即开始闪烁，不互相等待（符合 GDD 并行定义）
- `FLASH_COUNT = 3` → `flash_index` 递增到 `3*2 = 6`（每个完整闪烁 = 2 次切换: 旧→新→旧→新→旧→新）
- 闪烁完成条件：`flash.flash_index >= FLASH_COUNT * 2`，即 6 次颜色切换完成
- `attacker_wins=false` 时不触发闪烁 — GDD 明确不闪烁
- 动画完成后清理 `_animations` 和 `_flashes` 数组 — 防止内存累积

### 与 TurnManager 集成点

```gdscript
# TurnManager._execute_turn() 中：
_apply_results(results)  # 步骤 4：先应用（星球归属已变）
# 然后启动动画（使用 results 中的占领信息）
BattleAnimator.start(results)
await EventBus.animations_complete
# 然后步骤 5...
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: 移动动画核心（短线绘制、进度、跳过）
- TurnManager 中的 `await` 集成（回合管理器 epic 中实现）
- 多指令同目标星的特殊处理（第一条占领后，后续到达不闪烁 — game logic 保证）
- 音效

---

## QA Test Cases

*Derived from GDD acceptance criteria.*

- **AC-1**: 占领闪烁 (ENEMY→PLAYER)
  - Given: planet color=ENEMY(红), attacker_wins=true
  - When: animation t reaches 1.0
  - Then: planet flashes red↔blue 3 times, each flash 150ms

- **AC-2**: 占领闪烁 (NEUTRAL→PLAYER)
  - Given: planet color=NEUTRAL(灰), attacker_wins=true
  - When: animation t reaches 1.0
  - Then: planet flashes gray↔blue 3 times

- **AC-3**: 并行到达
  - Given: cmd1 duration=0.5s, cmd2 duration=0.75s
  - When: animations play
  - Then: cmd1 flash starts at ~0.5s, cmd2 flash starts at ~0.75s, both independently

- **AC-4**: 全部完成
  - Given: 2 commands, both moving + flashing
  - When: both flash sequences complete
  - Then: animations_complete emitted

- **AC-5**: 防守方胜不闪烁
  - Given: attacker_wins=false
  - When: animation t reaches 1.0
  - Then: no flash for that planet

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**:
- Screenshot of mid-flash (planet in transition color) + lead sign-off
- Evidence directory: `production/qa/evidence/battle-animation-flash.md`

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (移动动画基础框架) — must be DONE
- Depends on: Core deployment-system (DeploymentCommand) — must be DONE
- Depends on: Core planet-system (get_planet, position, owner) — must be DONE
- Depends on: Core combat-resolution (BattleResult.attacker_wins) — must be DONE
