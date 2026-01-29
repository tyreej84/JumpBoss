# Changelog

## 1.0.3
### Fixed
- Fixed players disappearing from the leaderboard mid-encounter if they:
  - reloaded their UI during a boss fight
  - joined late or missed `ENCOUNTER_START`
- Addon now accepts silent jump updates during an active encounter even if encounter IDs do not match, ensuring leaderboard stability.

### Changed
- Leaderboard now remains visible for **~20 seconds after boss death**, allowing time to view or copy results.
- Extended default stale timeout to **120 seconds** before fading begins.
- Extended fade duration to **10 seconds** to prevent premature removal of players.
- Improved vertical spacing between the `You: X` counter and the leaderboard rows for better readability.

### Notes
- These changes do **not** affect chat behavior.
- Chat output remains **winner-only**, posted only at encounter end.
- All communication remains silent via addon messages.

---

## 1.0.2
### Changed
- Reduced on-screen leaderboard size.
- Limited leaderboard display to **Top 5** players.
- Adjusted layout for minimal screen footprint.

---

## 1.0.1
### Added
- Initial public release of JumpBoss.
- Tracks jump counts during boss encounters.
- Small, movable, translucent on-screen leaderboard.
- Class-colored player names (fallback to white).
- Silent addon communication during encounters.
- End-of-encounter leaderboard posted to chat **only by the winner**.
- Deterministic tie-breaking to prevent duplicate posts.
- Timeout + fade-out system for stale players.
- Slash commands for UI control and tuning.
