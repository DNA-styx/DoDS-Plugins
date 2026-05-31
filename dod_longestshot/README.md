# dod_longestshot

A SourceMod plugin for Day of Defeat: Source that tracks the top 10 longest kill shots per map for scoped rifles and rocket weapons.

---

## Features

- Tracks the top 10 longest kills per map for the Kar98k Scoped, Springfield, Bazooka, and Panzerschreck
- Announces new weapon distance records in chat
- Displays the leaderboard to all players in the final 10 seconds of a map
- Players can view the leaderboard at any time with `!shots`
- Writes server log entries for HLstatsX ingestion
- Writes a `longshot_winner` action log entry for the map winner at end of map

---

## Installation

1. Copy `dod_longestshot.smx` to `addons/sourcemod/plugins/`
2. Restart the server or load the plugin with `sm plugins load dod_longestshot`

---

## Commands

| Command | Access | Description |
|---|---|---|
| `sm_shots` / `!shots` | All players | Display the longest shots leaderboard |

---

## ConVars

Generated automatically to `cfg/sourcemod/dod_longestshot.cfg` on first load.

| ConVar | Default | Description |
|---|---|---|
| `sm_longestshot_min_distance` | `50` | Minimum distance in metres for a shot to qualify |

---

## HLstatsX

The plugin writes standard Source engine log lines that HLstatsX can ingest.

**Kill event** (every qualifying shot):
```
"Name<userid><steamid><team>" killed "Name<userid><steamid><team>" with "longshot_k98_scoped"
```

**Action event** (map winner at end of map):
```
"Name<0><steamid><team>" triggered "longshot_winner"
```

The following entries must be added to your HLstatsX game configuration:

**Actions - PlyrPlyr Action** (kill events):

| Code | Description |
|---|---|
| `longshot_k98_scoped` | Longest shot kill with Kar98k Scoped |
| `longshot_spring` | Longest shot kill with Springfield |
| `longshot_pschreck` | Longest shot kill with Panzerschreck |
| `longshot_bazooka` | Longest shot kill with Bazooka |

**Actions - Player Action** (winner event):

| Code | Description |
|---|---|
| `longshot_winner` | Player held the longest shot at end of map |

---

## Notes

- Records reset on map change only.
- The end of map leaderboard panel will only display on servers using a time limit. On round-based maps it will not be shown. The `longshot_winner` log entry is written via `OnMapEnd()` and will always fire regardless of how the map ends.
- The `<0>` in the winner log is the userid, which may be invalid if the player has disconnected. The SteamID is always present as it is stored at the time of the kill, so HLstatsX will still attribute the action correctly.
- Distance is calculated from player origin to player origin at the time of death. 1 metre = 52.49 hammer units.

---

## Credits

Based on the original Longest Shot plugin by [Knoxville](https://forums.alliedmods.net/showthread.php?p=2843694).

Modified by Claude.ai, guided by DNA.styx.
