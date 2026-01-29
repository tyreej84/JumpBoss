# Changelog

## 1.0.7
### Fixed
- Fixed an issue where **multiple players could post the end-of-encounter leaderboard** at the same time.
- Added robust winner arbitration so **only one winner can ever post**, even in ties or near-simultaneous claims.
- Prevented race conditions during end-of-encounter claim handling that caused duplicate chat messages.

### Changed
- End-of-encounter winner claiming now:
  - Assumes local claim immediately
  - Waits for competing claims
  - Deterministically resolves to a single winner (alphabetical tie-break)
- End-of-encounter posting flow is now fully synchronized and resilient to latency.
- No changes to chat verbosity: output remains **winner-only**.

### Notes
- Jump counting still stops immediately on boss death.
- Leaderboard display remains visible for ~20 seconds after boss death without affecting results.
- All addon communication continues to use silent addon messages only.

---

## 1.0.6
### Fixed
- Jump counting fully stops immediately when the boss dies, even while the leaderboard remains visible.
- Fixed end-of-encounter chat output missing participant lines.

### Changed
- Added a ~5 second sync window after encounter end to allow final jump totals to propagate.
- Final chat output always includes at least the Top 5 jumpers (or fewer if fewer participants are present).

---

## 1.0.5
### Fixed
- Prevented post-kill jumps from affecting final totals.
- Improved reliability of end-of-encounter posting.

---

## 1.0.4
### Changed
- End-of-encounter posting waits longer before announcing results.
- Final chat output includes at least the Top 5 jumpers.
- Leaderboard remains visible for ~20 seconds after boss death.

---

## 1.0.3
### Changed
- Extended default stale timeout to 120 seconds before fading begins.
- Extended fade duration to 10 seconds to prevent premature removal of players.
- Improved vertical spacing between the `You: X` counter and leaderboard rows.

---

## 1.0.2
### Changed
- Reduced on-screen leaderboard size.
- Limited leaderboard display to Top 5 players.
- Adjusted layout for minimal screen footprint.

---

## 1.0.1
### Added
- Initial public release of JumpBoss.
- Tracks jump counts during boss encounters.
- Small, movable, translucent on-screen leaderboard.
- Class-colored player names (fallback to white).
- Silent addon communication during encounters.
- End-of-encounter leaderboard posted to chat only by the winner.
- Deterministic tie-breaking to prevent duplicate posts.
- Timeout + fade-out system for stale players.
- Slash commands for UI control and tuning.
