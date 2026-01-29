# Changelog

## 1.0.8
### Fixed
- Fixed an issue where JumpBoss clients were **not synchronizing jump counts** between players during encounters.
- Addon messages are now broadcast to **all applicable group channels** (Instance, Raid, and Party), ensuring reliable syncing across:
  - LFG instance groups
  - premade parties
  - raid conversions
- Resolved cases where multiple players could incorrectly post the leaderboard due to missing or incomplete sync data.
- Ensured jump counts never increase after boss death, even while the leaderboard remains visible.

### Changed
- End-of-encounter result posting now waits **~5 seconds** to fully synchronize all final jump totals before determining the winner.
- Winner arbitration is now fully deterministic:
  - Local claim is assumed immediately
  - Competing claims are collected
  - A single winner is selected using alphabetical tie-breaking
- Leaderboard remains visible for **~20 seconds after boss death** without affecting results.
- Final chat output always includes **at least the Top 5 jumpers**, or fewer if fewer participants exist.

### Notes
- Chat output remains **winner-only** and posts only once per encounter.
- All addon communication remains silent via addon messages.
- Duplicate addon messages are safely handled and do not affect accuracy.

---

## 1.0.7
### Fixed
- Fixed multiple players posting the leaderboard simultaneously due to claim race conditions.
- Improved reliability of winner determination in tied or near-simultaneous claim scenarios.

---

## 1.0.6
### Fixed
- Jump counting fully stops immediately when the boss dies.
- Fixed end-of-encounter chat output missing participant lines.

---

## 1.0.5
### Fixed
- Prevented post-kill jumps from affecting final totals.
- Improved reliability of end-of-encounter posting.

---

## 1.0.4
### Changed
- End-of-encounter posting waits longer before announcing results.
- Leaderboard remains visible for ~20 seconds after boss death.

---

## 1.0.3
### Changed
- Extended stale timeout to 120 seconds.
- Extended fade duration to 10 seconds.
- Improved spacing between the `You:` counter and leaderboard rows.

---

## 1.0.2
### Changed
- Reduced on-screen leaderboard size.
- Limited display to Top 5 players.

---

## 1.0.1
### Added
- Initial public release of JumpBoss.
