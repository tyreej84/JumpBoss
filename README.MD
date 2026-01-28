# JumpBoss

JumpBoss is a fun mini-game addon for World of Warcraft that tracks how many times players jump during boss encounters (Encounter Journal encounters). It shows a small, movable, translucent leaderboard during the fight (addon users only), and **posts results to chat only at the end** — **and only the winner posts**.

## Features
- Tracks jumps during boss encounters
- Small on-screen leaderboard (Top 5 by default)
- Translucent black frame, draggable (lock/unlock)
- Class-colored names when available (otherwise white)
- **Silent addon communication** (no visible messages)
- **No chat output until encounter end**
- **Only the jump winner posts** the final leaderboard
- Timeout + fade: players who stop reporting fade out and disappear

## Important Notes
- JumpBoss can only track and rank **players who are running JumpBoss**.
- Addon communication uses WoW’s addon message channel (invisible to players). The only visible output is the end-of-fight chat post by the winner.
- This addon is intended as a lighthearted mini-game.

## Installation
1. Download the latest release zip.
2. Extract into:
   - `World of Warcraft/_retail_/Interface/AddOns/`
3. Ensure the folder structure is:
   - `Interface/AddOns/JumpBoss/JumpBoss.toc`
   - `Interface/AddOns/JumpBoss/JumpBoss.lua`
4. Reload the UI (`/reload`).

## Commands
- `/jb show` — show the on-screen frame
- `/jb hide` — hide the on-screen frame
- `/jb lock` — lock the frame position
- `/jb unlock` — unlock the frame (drag to move)
- `/jb scale <n>` — set scale (example: `/jb scale 1.1`)
- `/jb timeout <seconds>` — how long before stale players fade (example: `/jb timeout 3`)
- `/jb fade <seconds>` — fade duration after timeout (example: `/jb fade 2`)

Aliases:
- `/jumpboss`
- `/jb`

## How the Winner Posting Works
At encounter end, everyone silently shares their final totals via addon comms. The top jumper (tie-broken alphabetically) sends a silent “claim”, then **only that winner posts** the final leaderboard in party/raid/instance chat.

## Packaging for Wago.io
Releases are built by GitHub Actions into a zip with the correct AddOns folder structure for Wago:
- `JumpBoss/JumpBoss.toc`
- `JumpBoss/JumpBoss.lua`

## License
MIT — see `LICENSE.md`.
