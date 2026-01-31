# Changelog

## 1.2.3
### Fixed
- Fixed cases where **more than one player** could post the leaderboard.
  - Added a silent `P:<enc>:<poster>` “posted” lock message.
  - Winner posting is now staggered with a deterministic delay to avoid simultaneous posts.
  - Winner is re-validated right before posting to reduce race conditions.

## 1.2.2
### Fixed
- Fixed `SendChatMessage(): Invalid escape code` by removing pipe (`|`) separators from leaderboard output and sanitizing any pipe characters.
- Fixed `[ADDON_ACTION_FORBIDDEN] ... SendChatMessage()` issues by posting via `securecallfunction` when available (prevents taint/protected call failures caused by other addons hooking `SendChatMessage`).

## 1.2.1
### Changed
- Updated final leaderboard chat formatting to use:
  - `PlayerName - X Jumps!`
  - Includes proper singular/plural (`1 Jump!` vs `2 Jumps!`).

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
