# Smoke Test: Critical Paths

**Purpose**: Run these checks in under 15 minutes before any QA hand-off.
**Run via**: `/smoke-check` (which reads this file)
**Update**: Add new entries when new core systems are implemented.

## Core Stability (always run)

1. Game launches without crash
2. Main menu / title screen loads correctly
3. Core scene responds to keyboard and mouse input

## Core Mechanic (update per sprint)

<!-- Add the primary mechanic for each sprint here as it is implemented -->
4. [Sprint 1] EventBus signals fire and propagate correctly
5. [Sprint 1] GameState transitions work: TITLE → PLAYING → PAUSED → PLAYING
6. [Sprint 1] TurnManager cycles through DEPLOYMENT → EXECUTION → CLEANUP
7. [Sprint 2] Planet system: data structure, adjacency, owner changes
8. [Sprint 2] Combat: resolve() returns correct BattleResult for all valid inputs
9. [Sprint 2] Deployment: validate() rejects invalid commands, deploy() deducts troops
10. [Sprint 3] Star Map renders planets, connections, and garrison counts
11. [Sprint 3] Full demo loop: deploy → end turn → watch battle → win/lose

## Data Integrity

12. Game state can be serialized and deserialized correctly (once save system exists)
13. Save/load round-trip produces identical game state (once save system exists)

## Performance

14. No visible frame rate drops on target hardware (60fps target)
15. No memory growth over 5 minutes of play (once core loop is implemented)
