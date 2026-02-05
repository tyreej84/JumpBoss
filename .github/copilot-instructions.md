# JumpBoss Copilot Instructions

## Project Overview
JumpBoss is a **World of Warcraft (WoW) addon** that tracks player jumps during boss encounters. It communicates silently between addon users and posts a leaderboard only at encounter end, with only the jump winner posting results. This is a single-file Lua addon with minimal dependencies on WoW's internal API.

## Architecture & Key Concepts

### Phase Model
The addon operates in three distinct phases controlled by encounter events:
- **idle**: No active encounter (default state)
- **active**: During encounter (`ENCOUNTER_START` event) — tracks jumps, broadcasts state, handles live updates
- **ended**: After encounter ends (`ENCOUNTER_END` event) — executes winner arbitration and posting logic

All state management checks `phase` before executing to prevent incorrect behavior outside encounters.

### State Structures
- `totals`: Maps full player names → jump counts (only players who jumped ≥1 time)
- `lastSeen`: Tracks timestamp when each player last sent state (for fade-out timeout)
- `classByName`: Stores WoW class info for name coloring
- `jumped`: Boolean flag per player (jumps from 0 → 1 sets this)
- Winner arbitration: `claimWinnerFull`, `claimWinnerCount`, `postedByFull` track claimed winner and posting lock

### Communication Channel Priority
Uses WoW's addon message channel (silent, invisible to regular players):
1. **RAID** first (group authority)
2. **INSTANCE_CHAT** fallback (LFG/dungeon parties)
3. **PARTY** fallback (small groups)

See `GetGroupChannel()` for implementation.

## Protocol & Comms Messages

### Message Format
Prefix: `"JBT1"` (single addon version identifier)

**Message types:**
- `HELLO:<encounterID>:<classFile>` — Player joins, broadcasts class for name coloring
- `S:<encounterID>:<jumpCount>:<classFile>` — State broadcast (full player jump count)
- `REQ:<encounterID>` — Request for state from other players (pulls in late joiners)
- `C:<encounterID>:<winnerFullName>:<winnerCount>` — Claim: player declares themselves winner
- `P:<encounterID>:<posterFullName>` — Posted lock: only claimed winner can post

**Critical detail:** Encounter ID in messages prevents cross-encounter message confusion.

### Winner Arbitration Logic
At encounter end, all players with jumps → 1:
1. Find local max jumps, send `CLAIM`
2. Other players compare their winner claim; highest jumps + alphabetical tie-break wins
3. Claimed winner sends `POSTED` to lock others
4. Only `POSTED` player sends chat message to party/raid/instance

This prevents all winners from spam-posting.

## Jump Detection

**Primary method:** `PLAYER_JUMP` event (WoW's native jump event, most reliable)

**Fallback:** `JumpOrAscendStart` hook (Lua function intercept, debounced with 0.08s throttle)

**Safety checks:** Skip detection if `UnitInVehicle()` or `UnitOnTaxi()` (movement doesn't count)

Jump count increments on first detection only via `if myJumps == 1` flag.

## Broadcasting & Synchronization

### Update Timing
- **Live broadcast:** `broadcastInterval` (default 0.10s) — throttles sends to prevent spam, debounced via `pendingBroadcast`
- **Heartbeat:** `heartbeatInterval` (default 1.25s) — periodic HELLO + STATE to catch new players, recover lost state
- **REQ pulse:** `reqPulseInterval` (default 3.0s) — periodic REQUEST to pull state from other players (improves late-joiner sync)

All broadcasts immediately set `lastSeen[myName] = Now()` to track when player was last active.

## UI Rendering

### Frame Management
- Single translucent black backdrop frame (`ui`) with:
  - Title ("JumpBoss"), subtitle (status, "You: N" during encounter)
  - Dynamically created font string lines (count = `maxLines`, default 5)
  
### UpdateUI() Flow
1. Skip if `db.show == false`
2. Build sorted visible totals: `BuildSortedVisibleTotals()` filters stale players (older than `staleTimeout + fadeDuration`)
3. Sort by: count (descending) → name (ascending, alphabetical tie-break)
4. Render top N lines with:
   - **Alpha fade:** Players older than `staleTimeout` fade out over `fadeDuration` (visual only, doesn't affect posting)
   - **Class colors:** Look up `NameColor()` for RAID_CLASS_COLORS by `classByName[name]`

**Position tracking:** `db.pos` stores point, relPoint, x, y for drag persistence across reloads.

## Command System

**Slash commands:** `/jb` and `/jumpboss` (aliases)

| Command | Effect |
|---------|--------|
| `/jb show` | `db.show = true` |
| `/jb hide` | `db.show = false` |
| `/jb lock` / `/jb unlock` | Toggle `db.locked` (drag behavior) |
| `/jb scale <n>` | Set `db.scale` (UI zoom) |
| `/jb timeout <sec>` | Set `db.staleTimeout` (fade start) |
| `/jb fade <sec>` | Set `db.fadeDuration` (fade length) |
| `/jb top <n>` | Set `db.maxLines` ≥ 5 (posted leaderboard size, enforced minimum) |

All settings persist in `SavedVariables: JumpBossDB`.

## Key Functions & Patterns

### String Safety
**Critical:** Pipe character `|` escapes in WoW chat (escape codes). Hard-sanitize via `string.gsub(str, "|", "||")` before posting.

### Secure Chat Posting
Use `securecallfunction("SendChatMessage", ...)` to avoid taint protection violations when posting from protected frames.

### Full Name vs. Short Name
- **Full name:** `"PlayerName-RealmName"` (deterministic for winner arbitration, used in `claimWinnerFull`, `postedByFull`)
- **Short name:** Ambiguated short form for UI display (via `Ambiguate(fullName, "short")`)

Use full names in comms/arbitration; short names only in UI.

## Testing & Debugging

**Key events to verify:**
- `ENCOUNTER_START` → phase becomes "active", state reset
- `ENCOUNTER_END` → phase becomes "ended", winner arbitration triggers, posting occurs
- `GROUP_ROSTER_UPDATE` → detect new group members, may trigger fresh HELLO
- `ADDON_LOADED` → restore settings from SavedVariables

**Console debugging:** Add `print()` statements in state handlers (HELLO/REQ/STATE parsing) to trace comms flow.

**Live testing hints:**
- `/reload` to reload without restarting WoW
- Set `/jb timeout 30 /jb fade 5` for testing fade behavior
- Use `/jb top 10` to see more entries during long encounters
