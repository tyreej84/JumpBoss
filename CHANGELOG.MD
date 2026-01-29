# Changelog

## 1.0.9
### Fixed
- Fixed an issue where jump counts from other players did not appear on the leaderboard until the encounter ended.
- Resolved live synchronization failures caused by missing late-join and reload handling.
- Improved reliability of addon message delivery by using a single, correct group channel (Instance → Raid → Party).

### Added
- HELLO / REQUEST / STATE handshake system:
  - Ensures jump totals synchronize immediately when an encounter starts.
  - Allows players who reload or join late to receive current jump totals.
  - Enables fully **interactive, real-time leaderboard updates** during encounters.

### Changed
- Leaderboard now updates live throughout the fight instead of only at encounter end.
- End-of-encounter results wait ~5 seconds to collect final jump totals before determining the winner.
- Winner arbitration remains deterministic with alphabetical tie-breaking.
- Leaderboard remains visible for ~20 seconds after boss death without affecting results.
- Final chat output always includes at least the Top 5 jumpers (or fewer if fewer participants exist).

### Notes
- Chat output remains **winner-only** and posts exactly once per encounter.
- All addon communication remains silent via addon messages.
- Duplicate or late addon messages are safely handled and do not affect leaderboard accuracy.

---

## 1.0.8
### Fixed
- Fixed jump total synchronization failures between clients.
- Resolved multiple players posting the leaderboard due to missing or incomplete sync data.
- Ensured jump counts never increase after boss death.

---

## 1.0.7
### Fixed
- Fixed race conditions where multiple players could post the leaderboard simultaneously.
- Improved reliability of winner determination in tied scenarios.

---

## 1.0.6
### Fixed
- Jump counting fully stops immediately when the boss dies.
- Fixed missing participant lines in end-of-encounter chat output.

---

## 1.0.5
### Fixed
- Prevented post-kill jumps from affecting final totals.
- Improved end-of-encounter posting reliability.

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
- Limited leaderboard display to Top 5 players.

---

## 1.0.1
### Added
- Initial public release of JumpBoss.
