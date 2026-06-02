# Test Infrastructure

**Engine**: Godot 4.6
**Test Framework**: GdUnit4
**CI**: `.github/workflows/tests.yml`
**Setup date**: 2026-06-02

## Directory Layout

```
tests/
  unit/           # Isolated unit tests (formulas, state machines, logic)
  integration/    # Cross-system and save/load tests
  smoke/          # Critical path test list for /smoke-check gate
  evidence/       # Screenshot logs and manual test sign-off records
```

## Running Tests

### Local (Godot Editor)
1. Open project in Godot 4.6
2. GdUnit4 panel appears at the bottom (if plugin enabled)
3. Click "Run" to execute all tests

### CLI (Headless)
```bash
godot --headless --script tests/gdunit4_runner.gd
```

## Test Naming

- **Files**: `[system]_[feature]_test.gd`
- **Functions**: `test_[scenario]_[expected]`
- **Example**: `combat_damage_test.gd` → `test_base_attack_returns_expected_damage()`

## Story Type → Test Evidence

| Story Type | Required Evidence | Location |
|---|---|---|
| Logic | Automated unit test — must pass | `tests/unit/[system]/` |
| Integration | Integration test OR playtest doc | `tests/integration/[system]/` |
| Visual/Feel | Screenshot + lead sign-off | `tests/evidence/` |
| UI | Manual walkthrough OR interaction test | `tests/evidence/` |
| Config/Data | Smoke check pass | `production/qa/smoke-*.md` |

## Installing GdUnit4

GdUnit4 must be installed manually (not via filesystem — it's an AssetLib plugin):

1. Open the project in Godot 4.6
2. Go to AssetLib tab → search "GdUnit4"
3. Download & Install
4. Enable: Project → Project Settings → Plugins → GdUnit4 ✓
5. Restart the editor
6. Verify: `res://addons/gdunit4/` exists

Note: GdUnit4 is NOT committed to the repo. Each developer installs it locally.
CI installs it via the `MikeSchulze/gdUnit4-action@v1` GitHub Action.

## CI

Tests run automatically on every push to `main` and on every pull request.
A failed test suite blocks merging.
