# Godot — Breaking Changes (Complete)

> **Last verified**: 2026-05-31
> **Sources**: Official migration guides (HTML saved locally from docs.godotengine.org)
> **Project context**: 2D GDScript strategy game. ✅ = affects us. ❌ = irrelevant (3D/C#/Editor-only).

---

## Quick-Use Checklist

When writing GDScript for this project, AVOID these:

| ❌ Don't Use | ✅ Use Instead | Since |
|-------------|---------------|-------|
| `JSONRPC.set_scope()` | `JSONRPC.set_method()` | 4.5 |
| `Node.get_rpc_config()` | `Node.get_node_rpc_config()` | 4.5 |
| `RenderingServer.instance_reset_physics_interpolation()` | *(removed, no replacement)* | 4.5 |
| `RenderingServer.instance_set_interpolated()` | *(removed, no replacement)* | 4.5 |
| `@export_file` expecting `res://` paths | `@export_file_path` for res://; or handle `uid://` | 4.4 |
| `RichTextLabel.add_image(size_in_percent)` | `add_image(width_in_percent, height_in_percent)` | 4.5 |
| `Resource.duplicate(true)` for deep copy | `Resource.duplicate_deep(DEEP_DUPLICATE_ALL)` | 4.5 |
| `EditorFileDialog.add_side_menu()` | *(removed, no replacement)* | 4.6 |

---

## 4.5 → 4.6 (Jan 2026)

**Overall**: Very safe for GDScript. Almost all breaking changes are C# binary-compatible only or editor-only.

### Core — ALL GDScript Compatible

| Change | Note |
|--------|------|
| `FileAccess.create_temp` — `mode_flags` param `int` → `FileAccess.ModeFlags` | |
| `FileAccess.get_as_text` — `skip_cr` parameter removed | |
| `Performance.add_custom_monitor` — new optional `type` param | |

### Animation — ALL GDScript Compatible

`String` → `StringName` changes in AnimationPlayer: `assigned_animation`, `autoplay`, `current_animation`, `get_queue()`. C# only.

### GUI Nodes — ALL GDScript Compatible

New optional parameters added to: `Control.grab_focus`, `Control.has_focus`, `FileDialog.add_filter`, `LineEdit.edit`, `SplitContainer.clamp_split_offset`.

### Networking — ALL GDScript Compatible

Methods moved to base classes: `StreamPeerTCP.*` → `StreamPeerSocket`, `TCPServer.*` → `SocketServer`.

### ⚠️ Breaking for GDScript

| Change | Impact on us |
|--------|-------------|
| `OpenXRExtensionWrapper._get_requested_extensions` adds `xr_version` param | ❌ VR only, irrelevant |
| `EditorFileDialog.add_side_menu` **removed** | ❌ Editor plugin only |

### Behavior Changes

| Change | Relevant? |
|--------|-----------|
| TSCN format: `load_steps` removed, unique node IDs added | ⚠️ First save in 4.6 produces large diff — expected |
| Glow defaults changed (blend mode, intensity, level distribution) | ❌ 3D rendering |
| Volumetric fog physically accurate blending → brighter | ❌ 3D rendering |
| **`AStar2D.get_point_path()`** returns empty when `from_id` is disabled/solid | ✅ If we use AStar2D |
| **`AStarGrid2D.get_id_path()` / `get_point_path()`** — same | ✅ If we use AStarGrid2D |

### Changed Defaults (New Projects)

| Setting | Old | New | Relevant? |
|---------|-----|-----|-----------|
| Rendering driver on Windows | Vulkan | **D3D12** | ⚠️ Keep Vulkan for 2D pixel? Try D3D12 first |
| 3D physics engine | GodotPhysics | **Jolt Physics** | ❌ 2D game |
| `PopupMenu.submenu_popup_delay` | 0.3 | 0.2 | ✅ Minor UI |
| `Environment.glow_*` | various | various | ❌ 3D only |

---

## 4.4 → 4.5 (Late 2025)

### ⚠️ Breaking for GDScript

| Change | Impact |
|--------|--------|
| `JSONRPC.set_scope` → `set_method` | If we do multiplayer/RPC later |
| `Node.get_rpc_config` → `get_node_rpc_config` | If we do multiplayer/RPC later |
| `RenderingServer.instance_reset_physics_interpolation` **removed** | ❌ 3D only |
| `RenderingServer.instance_set_interpolated` **removed** | ❌ 3D only |

### Text/GUI Changes (Mostly Compatible)

| Change | Note |
|--------|------|
| Many `draw_*` methods: new optional `oversampling` param | `CanvasItem`, `Font`, `TextLine`, `TextParagraph`, `TextServer` — all compatible |
| `RichTextLabel.add_image`: `size_in_percent` → `width_in_percent` + `height_in_percent` | Old arg mapped to `width_in_percent`; `height_in_percent` defaults to `false` |
| `RichTextLabel.push_strikethrough/push_underline`: new optional `color` param | |
| `RichTextLabel.add_image`: new optional `alt_text` param | |
| `TreeItem.add_button`: new optional `alt_text` param | |

### Behavior Changes

| Change | Relevant? |
|--------|-----------|
| **`Resource.duplicate(true)`** now only duplicates internal resources | ✅ Must use `duplicate_deep(DEEP_DUPLICATE_ALL)` for full deep copy |
| **`ProjectSettings.add_property_info()`** now warns on `usage` key | ✅ Use `set_as_basic()`, `set_restart_if_changed()`, `set_as_internal()` |
| **`TileMapLayer`** physics chunking enabled by default | ✅ `get_coords_for_body_rid()` less precise; set `physics_quadrant_size = 1` to disable |
| Navigation mesh regions update async by default | Only if using NavigationServer |
| 3D model import skeleton fix | ❌ 2D game |
| C# changes (StringExtensions, Quaternion) | ❌ GDScript only |

---

## 4.3 → 4.4 (Mid 2025)

### Core

| Change | GDScript | Note |
|--------|----------|------|
| **`FileAccess.store_*()`** — return `void` → `bool` | ✔️ Compatible | Now returns success/failure. ALL store methods affected: `store_8/16/32/64/buffer/csv_line/double/float/half/line/pascal_string/real/string/var` |
| `FileAccess.open_encrypted` — new `iv` param | ✔️ Compatible | |
| `OS.execute_with_pipe` — new `blocking` param | ✔️ Compatible | |
| `OS.read_string_from_stdin` — new `buffer_size` param | ❌ GDScript | Default was 1024 |
| `RegEx.compile/create_from_string` — new `show_error` param | ✔️ Compatible | |
| `Semaphore.post` — new `count` param | ✔️ Compatible | |
| `TranslationServer.standardize_locale` — new `add_defaults` param | ✔️ Compatible | |

### ⚠️ `@export_file` Breaking Change

**THIS IS IMPORTANT**: In 4.4, `@export_file` changed to return `uid://` paths instead of `res://` paths when assigned from the Inspector. This breaks any script that expects `res://`-based paths.

**Fix**: In 4.5+, use `@export_file_path` to get the old `res://` behavior.

### GUI

| Change | GDScript | Note |
|--------|----------|------|
| `RichTextLabel.push_meta` — new `tooltip` param | ✔️ Compatible | |
| `GraphEdit.connect_node` — new `keep_alive` param | ✔️ Compatible | |
| `GraphEdit.signal frame_rect_changed` — param `Vector2` → `Rect2` | ❌ Breaking | Editor tool only |

### Rendering (3D/C# mostly)

| Change | Relevant? |
|--------|-----------|
| `Shader.get/set_default_texture_parameter` — `Texture2D` → `Texture` | Only if using custom shaders |
| `*Particles*.restart` — new `keep_seed` param | Only if using particles |

### Behavior Changes

| Change | Note |
|--------|------|
| **Curve resource** now enforces `[min_value, max_value]` range | Default `[0, 1]`. If we use Curve resources, ensure points within range. |
| CSG now uses Manifold library | 3D only |
| Android sensor events no longer enabled by default | Android only |

---

## Pre-4.3 (In Training Data — Documented for Completeness)

### 4.2 → 4.3

| Change | Note |
|--------|------|
| `Skeleton3D.add_bone` returns `int32` (was `void`) | 3D |
| `Skeleton3D` signal `bone_pose_updated` → `skeleton_updated` | 3D |
| **`TileMap` → `TileMapLayer`** | ✅ One node per layer instead of multi-layer |
| `NavigationRegion2D` removed `avoidance_layers`, `constrain_avoidance` | |
| `EditorSceneFormatImporterFBX` → `EditorSceneFormatImporterFBX2GLTF` | |
| `AnimationPlayer` and `AnimationTree` now extend `AnimationMixer` | Property access changed |

### 4.0 → 4.2

Major 4.0 changes — model should already know these:
- `yield()` → `await`
- `instance()` → `instantiate()`
- `connect(string, obj, string)` → `signal.connect(callable)`
- `get_world()` → `get_world_2d()` / `get_world_3d()`
- `OS.get_ticks_msec()` → `Time.get_ticks_msec()`
- `VisibilityNotifier2D` → `VisibleOnScreenNotifier2D`
- `YSort` node → `Node2D.y_sort_enabled` property
