# Godot — Deprecated APIs

> **Last verified**: 2026-05-31
> **Sources**: Official Godot 4.3→4.4→4.5→4.6 migration guides
>
> **Rule**: If any agent suggests an API in the "Deprecated/Removed" column, stop and use the replacement.
> For our 2D GDScript project, many 3D/C# entries are informational only.

---

## Removed APIs (Will Error at Runtime)

| Removed | Replacement | Since | Notes |
|---------|-------------|-------|-------|
| `EditorFileDialog.add_side_menu()` | *(none — removed)* | 4.6 | Editor plugin only |
| `RenderingServer.instance_reset_physics_interpolation()` | *(none — removed)* | 4.5 | 3D only |
| `RenderingServer.instance_set_interpolated()` | *(none — removed)* | 4.5 | 3D only |
| `EditorSceneFormatImporter._get_import_flags()` | *(none — removed)* | 4.4 | Never actually used by engine |
| `EditorTranslationParserPlugin._parse_file()` old signature | New signature with Array return | 4.4 | Editor plugin only |

## Renamed APIs

| Old Name | New Name | Since |
|----------|----------|-------|
| `JSONRPC.set_scope()` | `JSONRPC.set_method()` | 4.5 |
| `Node.get_rpc_config()` | `Node.get_node_rpc_config()` | 4.5 |
| `TileMap` (single node, multi-layer) | `TileMapLayer` (one per layer) | 4.3 |
| `Skeleton3D` signal `bone_pose_updated` | `skeleton_updated` | 4.3 |
| `AnimationPlayer.method_call_mode` | `AnimationMixer.callback_mode_method` | 4.3 |
| `AnimationPlayer.playback_active` | `AnimationMixer.active` | 4.3 |
| `EditorSceneFormatImporterFBX` | `EditorSceneFormatImporterFBX2GLTF` | 4.3 |
| `VisibilityNotifier2D` | `VisibleOnScreenNotifier2D` | 4.0 |
| `VisibilityNotifier3D` | `VisibleOnScreenNotifier3D` | 4.0 |
| `YSort` (separate node) | `Node2D.y_sort_enabled` (property) | 4.0 |
| `Navigation2D` / `Navigation3D` | `NavigationServer2D` / `NavigationServer3D` | 4.0 |

## Signature Changes (Old Signature May Error or Misbehave)

| Method (Old) | Method (New) | Since |
|-------------|-------------|-------|
| `RichTextLabel.add_image(size_in_percent)` | `add_image(width_in_percent, height_in_percent)` | 4.5 |
| `RichTextLabel.update_image(size_in_percent)` | `update_image(width_in_percent, height_in_percent)` | 4.5 |
| `OS.read_string_from_stdin()` | `read_string_from_stdin(buffer_size)` — param now required | 4.4 |
| `@export_file var path: String` | Use `@export_file_path` for `res://`; otherwise handles `uid://` | 4.4 |
| `GraphEdit.signal frame_rect_changed(new_rect: Vector2)` | `new_rect` is now `Rect2` type | 4.4 |

## Behavior Changes (API Works but Result Differs)

| API | Old Behavior | New Behavior | Since |
|-----|-------------|-------------|-------|
| `Resource.duplicate(true)` | Deep-copied everything including external resources | Only duplicates internal resources | 4.5 |
| `Resource.duplicate_deep(DEEP_DUPLICATE_ALL)` | *(new method)* | Full deep copy of all resources | 4.5 |
| `AStar2D.get_point_path(from, to)` | Returned path even for disabled points | Returns **empty array** if `from` is disabled/solid | 4.6 |
| `AStarGrid2D.get_id_path(from, to)` | Same | Returns **empty array** | 4.6 |
| `AStarGrid2D.get_point_path(from, to)` | Same | Returns **empty array** | 4.6 |
| `TileMapLayer.get_coords_for_body_rid()` | Exact cell coordinates | Less precise with physics chunking enabled | 4.5 |
| `ProjectSettings.add_property_info()` | Silently ignored `usage` key | Prints **warning** when `usage` key passed | 4.5 |
| `FileAccess.store_*()` | Returned `void` | Returns **`bool`** (success/failure) | 4.4 |
| `Curve` resource | No range enforcement | Enforces `[min_value, max_value]` range (default [0,1]) | 4.4 |

## Pre-4.3 Legacy (Model Should Know These)

| Deprecated | Replacement | Since |
|------------|-------------|-------|
| `yield()` | `await` | 4.0 |
| `instance()` | `instantiate()` | 4.0 |
| `connect("signal", obj, "method")` | `signal.connect(callable)` | 4.0 |
| `get_world()` | `get_world_2d()` / `get_world_3d()` | 4.0 |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` | 4.0 |
| String-based signal connections | Typed `signal.connect(callable)` | 4.0 |
| Untyped `Array` / `Dictionary` | `Array[Type]`, typed variables | 4.0 |

## Patterns to Avoid

| Pattern | Why | Better |
|---------|-----|--------|
| `$NodePath` inside `_process()` | Path lookup every frame | `@onready var` cached reference |
| `Texture2D` in shader parameters | Changed to base `Texture` type | Use `Texture` |
| GodotPhysics3D for new 3D projects | Jolt is default since 4.6 | Jolt Physics (3D only — doesn't affect our 2D game) |
