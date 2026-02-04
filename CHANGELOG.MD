# Changelog

All notable changes to **JumpBoss** are documented in this file.

---

## 1.2.6
### Fixed
- Fixed addon communication desync during encounters:
  - All addon messages now consistently use a **single shared channel per group type** (RAID → INSTANCE_CHAT → PARTY).
  - Prevents split-brain scenarios where different clients believed they were alone or the winner.
- Fixed cases where **multiple players could still post** after wipes:
  - Winner arbitration now fully converges before any post is allowed.
  - Clients that do not receive complete state data will no longer post.
- Fixed missing or incomplete participant data in end-of-encounter results:
  - Final leaderboard now reflects the full synced state, not partial local totals.

### Improved
- Real-time leaderboard updates during encounters:
  - State broadcasts are now reliably received mid-fight, allowing the on-screen leaderboard to update live.
  - HELLO / REQ / STATE handshake reliability improved for raids, wipes, reloads, and late joins.
- End-of-encounter behavior clarified and stabilized:
  - Leaderboard posts on both **kills and wipes**, but still **winner-only**.
  - Posting is delayed until synchronization completes, ensuring correct totals.
- Chat output formatting consistency:
  - Leaderboard entries are posted **one player per line** for readability.
  - Uses short names (`Name` instead of `Name-Realm`) consistently.

### Notes
- JumpBoss remains fully peer-to-peer:
  - There is **no host or leader** — all clients participate equally.
  - Deterministic arbitration guarantees only one poster.
- Jump counting still stops immediately on encounter end.
- The on-screen leaderboard remains visible for the configured post-encounter duration.

## 1.2.5
### Fixed
- Fixed remaining cases where **multiple players could still post** the leaderboard:
  - Final posting now uses **winner-only deterministic arbitration** with:
    - A shared `C:<enc>:<winner>` claim
    - A hard `P:<enc>:<poster>` posted-lock
    - Deterministic per-player delay to prevent simultaneous posts
  - All scheduled post timers are cancelled immediately once a `P:` message is received.
- Fixed chat posting taint issues permanently:
  - All chat output now uses `C_ChatInfo.SendChatMessage` exclusively.
  - No calls to the global `SendChatMessage` remain.
- Fixed “Invalid escape code” errors:
  - All outgoing chat lines are fully sanitized (`|` → `||`) before posting.

### Improved
- End-of-encounter sync is more reliable:
  - Clients wait for a full sync window before resolving the winner.
  - Winner is re-validated immediately before posting to avoid stale data.
- Short names (`Name-Realm` → `Name`) are now consistently used in chat output.

---

## 1.2.4
### Fixed
- Fixed chat taint/protection errors when posting results:
  - JumpBoss now posts via `C_ChatInfo.SendChatMessage` (avoids tainted global `SendChatMessage`).
- Prevented “Invalid escape code” chat errors by sanitizing `|` as `||` in all outgoing messages.

---

## 1.2.3
### Fixed
- Fixed cases where **more than one player** could post the leaderboard.
  - Added a silent `P:<enc>:<poster>` “posted” lock message.
  - Winner posting is now staggered with a deterministic delay to avoid simultaneous posts.
  - Winner is re-validated right before posting to reduce race conditions.

---

## 1.2.2
### Fixed
- Fixed `SendChatMessage(): Invalid escape code` by removing pipe (`|`) separators from leaderboard output and sanitizing any pipe characters.
- Fixed `[ADDON_ACTION_FORBIDDEN] ... SendChatMessage()` issues by posting via `securecallfunction` when available (prevents taint/protected call failures caused by other addons hooking `SendChatMessage`).

---

## 1.2.1
### Changed
- Updated final leaderboard chat formatting to use:
  - `PlayerName - X Jumps!`
  - Includes proper singular/plural (`1 Jump!` vs `2 Jumps!`).

---

## 1.2.0
### Changed
- **Non-jumpers are no longer recorded.**
  - Players running JumpBoss but who never jump will not appear on the leaderboard.
  - The final chat post includes only players who jumped at least once.
- State broadcasts (`STATE`) are no longer sent at 0 jumps to prevent non-jumper tracking.

### Improved
- Real-time leaderboard syncing during encounters is now more reliable with a HELLO/REQ/STATE handshake:
  - Encounter start triggers a handshake so active jumpers appear quickly.
  - Roster/world changes during an encounter re-trigger handshake to support reloads and late joins.
- End-of-encounter posting behavior remains winner-only and more deterministic:
  - Waits ~5 seconds to gather final totals, then resolves a single winner via claim arbitration.

### Notes
- Jump counting stops immediately after boss death.
- The on-screen leaderboard remains visible for ~20 seconds after the encounter ends.
- Chat output remains **winner-only** and posts at most once per encounter.

---

## 1.0.9
### Fixed
- Fixed an issue where other players’ jumps would not appear until the encounter ended.
- Improved message delivery reliability and real-time syncing.

---

## 1.0.8
### Fixed
- Fixed synchronization failures between clients in some group types.
- Prevented multiple winners posting due to missing sync data.

---

## 1.0.7
### Fixed
- Fixed race conditions where multiple players could post the leaderboard simultaneously.

---

## 1.0.6
### Fixed
- Jump counting stops immediately when the boss dies.
- Fixed missing participant lines in end-of-encounter chat output.

---

## 1.0.5
### Fixed
- Prevented post-kill jumps from affecting final totals.

---

## 1.0.4
### Changed
- Leaderboard remains visible for ~20 seconds after boss death.

---

## 1.0.3
### Changed
- Extended stale timeout and fade duration.
- Improved spacing between the `You:` counter and leaderboard rows.

---

## 1.0.2
### Changed
- Reduced leaderboard size.
- Limited display to Top 5 players.

---

## 1.0.1
### Added
- Initial public release.
