# Entity Inventory — 星辰之轭 Part 2 (MVP)

**Date**: 2026-06-02
**Scope**: MVP Demo — 4星图 + 拖线发兵 + 占点产兵 + 全歼制胜
**Rendering**: 大部分程序化绘制（`_draw()` circle/line/string），精灵资产极少

---

## Asset Summary

| Category | Count | Format | Procedural? |
|----------|-------|--------|-------------|
| Sprites/Textures | 4 | .png | 3 procedural, 1 texture needed |
| Fonts | 2 | .ttf/.otf | — |
| Audio | 6 | .ogg | — |
| Data (.tres) | 10+ | .tres | — |
| Godot Scenes | 5 | .tscn | — |
| **Total** | **25+** | | |

---

## 1. Visual Assets

### 1.1 Sprites (极为精简 — 大部分用 _draw() 程序化生成)

| Asset | Format | Size | Description | Priority |
|-------|--------|------|-------------|----------|
| `ui_panel_bg.png` | .png 16×16 | 9-slice tile | UI 面板背景贴图（纯色 `#1A1F2E` + 1px 边框） | P0 |
| `icon_king_default.png` | .png 16×16 | — | 国王默认图标（王冠/权杖简笔画） | P1 |

**程序化绘制（不需要精灵）：**
- 星球圆形 → `draw_circle()` 填色（蓝/红/灰）
- 连接线 → `draw_line()` 2px 半透白
- 选中高亮 → `draw_arc()` 白边框
- 兵力数字 → `draw_string()` 14px 白色
- 星球名字 → `draw_string()` 8px 白色
- 出征面板、按钮、滑块 → Godot 内置 Control 节点 + Theme 样式
- 胜利/失败 overlay → 半透明 `ColorRect`

### 1.2 UI Theme（Godot Theme 资源）

| Theme Item | 样式 | 用途 |
|------------|------|------|
| Button (normal) | bg: `#2A3050`, text: `#E8ECF4`, 4px radius | 所有按钮 |
| Button (hover) | bg: `#3A4070` | 悬停反馈 |
| Button (pressed) | bg: `#4488FF` | 按下反馈 |
| Button (disabled) | bg: `#1A1F2E`, text: `#555555` | 禁用状态 |
| HSlider | track: `#2A3050`, fill: `#4488FF`, grabber: 12×12 | 出征兵力滑块 |
| Panel | bg: `#1A1F2E`, 80% opacity, 4px radius | 所有面板容器 |
| Label (normal) | color: `#E8ECF4`, size: 14px | 正文 |
| Label (title) | color: `#E8ECF4`, size: 24px | 标题 |
| Label (error) | color: `#FF4444`, size: 12px | 错误提示 |
| Label (hint) | color: `#8899AA`, size: 10px | 快捷键提示 |

---

## 2. Fonts

| Font | File | Usage |
|------|------|-------|
| **思源黑体** (Noto Sans SC) | `fonts/NotoSansSC-Regular.ttf` | UI 正文 — 中文 + 英文 |
| **等宽字体** (Courier Prime /内置) | `fonts/CourierPrime.ttf` 或 Godot 内置 | 兵力数字对齐 |

**MVP 备选**: 如果不想引入字体文件，Godot 4.6 内置 `ThemeDB.fallback_font` 可覆盖基本需求。等宽数字用 `SystemFont` + `fixed_size` 强制对齐。

---

## 3. Audio Assets

| Asset | File | Duration | Description | Priority |
|-------|------|----------|-------------|----------|
| `bgm_ambient.ogg` | 60s loop | 氛围电子乐 | 星图背景 — 低沉、缓慢、太空感 | P0 |
| `sfx_click.ogg` | 0.1s | 短促点击音 | UI 按钮/星球选中 | P0 |
| `sfx_deploy.ogg` | 0.3s | 上升音 | 确认发兵 | P1 |
| `sfx_turn_end.ogg` | 0.5s | 节奏型打击 | 回合结束结算 | P1 |
| `sfx_victory.ogg` | 3s | 温暖上扬 | 胜利画面 | P2 |
| `sfx_defeat.ogg` | 3s | 低沉下落 | 失败画面 | P2 |

**MVP 备选**: 极简方案 — 只用 bgm_ambient + sfx_click + sfx_turn_end。3 个音效即可支撑 Demo 氛围。

---

## 4. Data Assets (.tres Resources)

### 4.1 兵种配置

| File | Content | Priority |
|------|---------|----------|
| `data/units/infantry.tres` | UnitStats: attack=10, defense=8, speed=3, cost=5 | P0 |
| `data/units/archer.tres` | UnitStats: attack=12, defense=5, speed=4, cost=6 | P0 |
| `data/units/cavalry.tres` | UnitStats: attack=15, defense=6, speed=5, cost=8 | P0 |

### 4.2 关卡配置

| File | Content | Priority |
|------|---------|----------|
| `data/levels/tutorial_1.tres` | LevelData: 4 planets + 3 connections | P0 |

### 4.3 星球配置

| File | Content | Priority |
|------|---------|----------|
| `data/planets/earth.tres` | PlanetDef: 地球, NORMAL, position(200,200), connections[2,3] | P0 |
| `data/planets/moon.tres` | PlanetDef: 月球, BARREN, position(350,120), connections[1] | P0 |
| `data/planets/mars.tres` | PlanetDef: 火星, FORTRESS, position(400,300), connections[1,4] | P0 |
| `data/planets/phobos.tres` | PlanetDef: 火卫一, NORMAL, position(520,250), connections[3] | P0 |

### 4.4 AI 难度配置

| File | Content | Priority |
|------|---------|----------|
| `data/ai/easy.tres` | AIDifficulty: aggression=0.3, defense_priority=0.7, counter_pick=true | P1 |

---

## 5. Godot Scene Files (.tscn)

| Scene | Root Node | Content | Priority |
|-------|-----------|---------|----------|
| `scenes/game.tscn` | Node2D | 主游戏场景 — 包含 StarMapView + TurnControlUI + KingPanel + DeploymentPanel | P0 |
| `scenes/ui/star_map_view.tscn` | Node2D | 星图渲染 _draw() | P0 |
| `scenes/ui/turn_control_ui.tscn` | Control | 回合数 + 按钮 + 阶段指示 | P0 |
| `scenes/ui/deployment_panel.tscn` | Control | 出征弹出面板 | P0 |
| `scenes/ui/king_panel.tscn` | Control | 国王信息面板 | P1 |

---

## 6. Autoload Scripts (not scenes, but project-level singletons)

| Script | Purpose | Priority |
|--------|---------|----------|
| `autoload/data_def.gd` | 枚举和常量定义 | P0 |
| `autoload/event_bus.gd` | 全局信号中转 | P0 |
| `autoload/game_state.gd` | 游戏状态机 | P0 |
| `autoload/turn_manager.gd` | 回合管线 | P0 |
| `autoload/planet_system.gd` | 星球数据管理 | P0 |
| `autoload/deployment_system.gd` | 出征命令管理 | P0 |

---

## 7. Asset Production Order

按依赖关系排列：

| Phase | Assets | 由谁产出 |
|-------|--------|----------|
| **Phase 0: 程序化** | 所有 _draw() 渲染、Theme 样式 | 程序员（写代码即可，零精灵） |
| **Phase 1: 数据** | 10+ .tres 文件 | 程序员 + 策划（Godot 编辑器内填值） |
| **Phase 2: 字体** | 2 字体文件 | 开源下载 |
| **Phase 3: 音频** | 3-6 .ogg 音效 | 音效设计师 / 免费素材库 |
| **Phase 4: 精灵** | 2 .png | 像素画师（MVP 可跳过 — 用程序化代替） |

**结论**: MVP 可以用 **0 精灵、3 音效、2 字体** 做出完整可玩 Demo。大部分视觉效果由 Godot `_draw()` API 程序化生成。

---

## 8. Gap Analysis

| 缺口 | 影响 | 缓解 |
|------|------|------|
| 字体未采购 | UI 文字可能显示为 fallback 字体，视觉效果打折 | MVP 用 Godot `ThemeDB.fallback_font` 撑过去 |
| 音效未采购 | 游戏静音 | MVP 用免费版权音效素材（freesound.org / OpenGameArt） |
| 像素精灵未绘制 | 国王图标等细节缺失 | 程序化绘制替代 — 国王面板用纯文字也能显示信息 |
