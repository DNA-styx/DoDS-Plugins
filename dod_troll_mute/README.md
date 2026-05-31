# dod_troll_mute

In Day of Defeat: Source, voice commands triggered by a killer play on the victim's screen. This is commonly abused by players who fire taunts such as *Negative* immediately after a kill. The typical server response is to disable voice commands entirely — which penalises everyone.

This plugin takes a targeted approach: a player's voice commands are suppressed for a configurable period after they make a kill. Legitimate use before and after that window is unaffected.

---

## Requirements

- SourceMod 1.11 or later

## Installation

1. Copy `dod_troll_mute.smx` to `addons/sourcemod/plugins/`
2. Copy the translation files to `addons/sourcemod/translations/`
3. Restart the server or change map

The configuration file is generated automatically at `cfg/sourcemod/dod_troll_mute.cfg` on first load.

---

## Configuration

| ConVar | Default | Description |
|---|---|---|
| `dod_troll_mute_enabled` | `1` | Enable or disable the plugin |
| `dod_troll_mute_duration` | `3` | Mute duration in seconds after a kill (0–10) |
| `dod_troll_mute_whitelist_medic` | `1` | Allow `voice_medic` to bypass the mute |
| `dod_troll_mute_targets` | `0` | `0` = mute on human kills only, `1` = all kills including bots |
| `dod_troll_mute_notify` | `0` | `1` = notify the player in chat when a command is suppressed |

`dod_troll_mute_notify` is useful during testing to confirm the plugin is working.

---

Created with Claude.ai, guided by DNA.styx
