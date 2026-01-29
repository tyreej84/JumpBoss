# Changelog

## 1.0.6
### Fixed
- Jump counting now **completely stops immediately when the boss dies**, even while the leaderboard remains visible.
- Resolved an issue where end-of-encounter chat output could post only the leaderboard header without player results.
- Fixed unreliable winner selection caused by late or missed final jump updates.

### Changed
- End-of-encounter result posting now waits **~5 seconds** to allow all addon users to synchronize final jump totals before determining the winner.
- Leaderboard display remains visible for **~20 seconds after boss death**, without affecting jump counts.
- Final chat output always includes **at least the Top 5 jumpers**, or fewer if fewer participants are present.

### Notes
- Chat output remains **winner-only**, posted only once per encounter.
- All addon communication continues to use silent addon messages only.

---

## 1.0.5
### Fixed
- Prevented post-kill jumps from affecting final jump totals.
- Improved reliability of end-of-encounter result posting.

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
- Improved vertical spacing between the `You: X` counter and the leaderboard rows.

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
