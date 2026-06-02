# Godot — Current Best Practices (4.6)

> **Last verified**: 2026-05-31 | **Engine**: Godot 4.6 | **Language**: GDScript
>
> Practices that are **new or changed** since the LLM training cutoff (~4.3).
> This supplements (not replaces) built-in knowledge. Focus on 2D GDScript.

---

## GDScript Language Features (4.5+)

### Variadic Arguments

```gdscript
func log_all(prefix: String, values: Variant...) -> void:
    for v in values:
        print(prefix, ": ", v)

log_all("DEBUG", 1, 2, "hello", Vector2(5, 5))
```

### Abstract Classes & Methods

```gdscript
@abstract
class_name BaseUnit extends Node2D

@abstract
func get_attack_power() -> int:
    pass  # Subclasses MUST override

func take_damage(amount: int) -> void:
    health -= amount
```

- `@abstract` enforces that subclasses implement the method
- Abstract classes cannot be instantiated directly

### Script Backtracing

- Detailed call stacks are now available in Release builds (not just Debug)
- Makes production debugging significantly easier

### Variadic Args + Typed Arrays

```gdscript
# Both work:
func foo(args: Variant...) -> void: pass
func bar(args: Array[int]) -> void: pass  # typed array parameter
```

---

## 2D-Specific (Critical for Our Project)

### TileMapLayer (since 4.3)

- **Always use `TileMapLayer`**, NOT the old `TileMap` node
- One layer = one `TileMapLayer` node
- Physics chunking is **enabled by default** (4.5+)
  - `get_coords_for_body_rid()` is less precise with chunking
  - Set `physics_quadrant_size = 1` to disable and get exact coordinates
- Scene tiles can be rotated like atlas tiles (4.6+)

### AStar2D / AStarGrid2D (4.6 behavior)

- `get_point_path()` returns **empty array** when `from_id` is a disabled/solid point
- Always check if path is empty before using:
  ```gdscript
  var path = astar.get_point_path(from, to)
  if path.is_empty():
      return  # No valid path
  ```

### CanvasItem draw methods (4.5+)

- All `draw_*` methods now accept an optional `oversampling` parameter
- Affects: `draw_char`, `draw_string`, `draw_multiline_string` (+outline variants)
- Default behavior unchanged; only matters if you need font oversampling

---

## Physics

### 2D Physics (Unchanged)

- 2D physics is still Godot Physics 2D — **Jolt is 3D only**
- No breaking changes for 2D physics across 4.4→4.5→4.6

### 3D Physics (Informational)

- Jolt Physics is the default 3D engine for new projects (4.6)
- Some HingeJoint3D properties (`damp`) only work with GodotPhysics
- Switch: Project Settings → Physics → 3D → Physics Engine

---

## Rendering

### Defaults Changed (4.6)

| Setting | Old | New | Note |
|---------|-----|-----|------|
| Windows rendering driver | Vulkan | **D3D12** | New projects only. Better driver compatibility. |
| Glow blend mode | Soft Light (2) | Screen (1) | Brighter. Adjust `glow_intensity` if needed. |
| `glow_intensity` | 0.8 | 0.3 | |
| `PopupMenu.submenu_popup_delay` | 0.3 | 0.2 | Slightly faster menus |

### Best Practices

- For 2D pixel art: Compatibility renderer is perfectly fine
- D3D12 on Windows should "just work" — try it first
- SMAA 1x (4.5): Sharper than FXAA, cheaper than TAA — good for UI text

---

## Resources

### Deep Duplication (4.5)

```gdscript
# Old behavior (4.4 and prior) — still works but changed meaning:
var copy = resource.duplicate(true)

# New explicit deep copy (4.5+):
var copy = resource.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
```

- `duplicate(true)` now only duplicates internal resources, NOT external refs
- Use `duplicate_deep(DEEP_DUPLICATE_ALL)` when you need a full independent copy

### Curve Resource (4.4+)

- Now enforces `[min_value, max_value]` range — default is `[0, 1]`
- Set `min_value`/`max_value` before adding points outside that range

---

## File I/O

### FileAccess.store_*() Returns bool (4.4+)

```gdscript
# Always check return value:
if not file.store_string("data"):
    push_error("Failed to write data")
```

### @export_file vs @export_file_path (4.4+)

```gdscript
# 4.4+: Returns uid:// paths from Inspector
@export_file var sprite_path: String  # May get "uid://..." 

# 4.5+: Explicitly get res:// paths
@export_file_path var sprite_path: String  # Always "res://..."
```

---

## UI / GUI

### RichTextLabel (4.5)

```gdscript
# Old (still works but deprecated pattern):
label.add_image(image, 0, Color.WHITE, true)

# New parameter names:
label.add_image(image, 0, Color.WHITE, true, false)
# width_in_percent, height_in_percent — not size_in_percent
```

### Focus System (4.6)

- Dual-focus: mouse/touch focus separate from keyboard/gamepad focus
- `Control.grab_focus()` now has `hide_focus` optional param
- `Control.has_focus()` now has `ignore_hidden_focus` optional param

---

## Project Settings (4.5+)

```gdscript
# DON'T use usage key in add_property_info:
ProjectSettings.add_property_info({
    "name": "my_setting",
    "type": TYPE_INT,
    "usage": PROPERTY_USAGE_DEFAULT  # WARNING in 4.5!
})

# DO use dedicated methods:
ProjectSettings.set_as_basic("my_setting", true)
ProjectSettings.set_restart_if_changed("my_setting", true)
ProjectSettings.set_as_internal("my_setting", false)
```

---

## Navigation (4.5+)

- **Dedicated 2D navigation server** — smaller export for 2D-only games
- `NavigationServer2D` is no longer a proxy to 3D
- Navmesh regions update asynchronously by default (performance boost)
- Toggle with `navigation/world/region_use_async_iterations` project setting

---

## Editor Workflow (4.6)

- Floating docks: most panels can float across multiple monitors
- New "Modern" theme: grayscale default. Classic theme still available in Editor Settings
- **Select Mode** (V key): Prevents accidental transforms. Old mode renamed "Transform Mode" (Q key)
- Drag resources from FileSystem into script editor → auto-generates export variable
- Quick Open dialog has Live Preview mode
- Alt+O = Output panel, Alt+S = Shader editor

---

## Tooling

- **ripgrep has no `gdscript` type**: `*.gd` is registered under `gap`.
  `rg --type gdscript` errors. Use `rg --glob "*.gd"` or `glob: "*.gd"` in the Grep tool.
- Use `godot --headless --script tests/gdunit4_runner.gd` for CI test runs
