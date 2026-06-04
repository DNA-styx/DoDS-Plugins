# dod_setwinners

Sets the winning team at map end in favour of the team with more tick points, preventing draws when the time limit expires. Broadcasts a team-coloured chat message when a winner is decided on points.

Based on the original "DoD:S Set Winners" by Root.

## Requirements

- [SourceMod](https://www.sourcemod.net/) 1.11 or later
- [sm-dod-hooks](https://github.com/dronelektron/sm-dod-hooks) by Dron-elektron

## Installation

1. Install sm-dod-hooks first — copy its `plugins` and `gamedata` folders to `addons/sourcemod/`
2. Copy `dod_setwinners.smx` to `addons/sourcemod/plugins/`

## ConVars

| ConVar | Default | Description |
|---|---|---|
| `dod_setwinners_enabled` | `1` | Enable or disable the plugin (1 = on, 0 = off) |

## Notes

- If both teams have equal tick points at map end, no winner is set and the result remains a draw
- The plugin re-arms automatically if a vote extends the round time
- If sm-dod-hooks is not loaded, a warning is written to the SourceMod log and the plugin will not set a winner

## Credits

- **Root** — original plugin https://forums.alliedmods.net/showthread.php?p=1999456 & https://github.com/zadroot/DoD_SetWinners
- **Dron-elektron** — sm-dod-hooks
- **Claude.ai guided by DNA.styx** — modernisation to SM 1.12
