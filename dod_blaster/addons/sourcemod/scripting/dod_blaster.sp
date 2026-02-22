/**
 * dod_blaster.sp
 *
 * Slay players with a lightning bolt and dissolve effect.
 * Accessible via the SourceMod admin menu (Player Commands) or sm_blast.
 *
 * Changelog:
 *   1.0 - Initial release; lightning bolt slay with dissolve effect for DoDS.
 *         Adapted from "Admin Smite" by Hipster, spawn-area kill support by
 *         FeuerSturm, dissolve snippet from AlliedModders forums.
 *   1.1 - Modernised to SM 1.12 new syntax (#pragma newdecls, typed vars)
 *         Added admin menu integration (Player Commands category)
 *         Added translation support (dod_blaster.phrases.txt; EN/FR/DE)
 *         Player list shows all non-spectator players, alive and dead
 *         Replaced hardcoded French broadcast with translatable phrase
 *         Removed obsolete FCVAR_PLUGIN convar flag
 *         Fixed ragdoll timer crash on client disconnect
 *         Fixed compiler warning 219 (shadowed variable in helpers.inc)
 *         Various code simplifications and documentation
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

// adminmenu must be declared optional so that the forward wiring works
// correctly regardless of plugin load order. OnLibraryRemoved handles cleanup.
#undef REQUIRE_PLUGIN
#include <adminmenu>

#define PLUGIN_VERSION  "1.1"
#define SOUND_THUNDER_1 "ambient/explosions/explode_9.wav"
#define SOUND_THUNDER_2 "ambient/explosions/explode_6.wav"

// DoDS team indices
#define TEAM_ALLIES 2
#define TEAM_AXIS   3

// How far above the player's origin the beam should terminate (chest height)
#define BEAM_HEIGHT_OFFSET 26.0

// Vertical height above target the beam originates from
#define BEAM_START_HEIGHT 800.0

// Random horizontal spread for the beam start position
#define BEAM_SPREAD 500

public Plugin myinfo =
{
	name        = "dod_blaster",
	author      = "Hipster, FeuerSturm, vintage pour DoDs, claude.ai guided by DNA.styx",
	description = "Slay players with a lightning and dissolve effect",
	version     = PLUGIN_VERSION,
	url         = "https://github.com/DNA-styx/DoDS-Plugins"
};

// Precached resource handles
int g_SmokeSprite;
int g_LightningSprite;

// Per-client flag: suppress the next player_team chat message (used during
// the team-swap trick that guarantees a kill in spawn zones)
bool g_bSuppressTeamMsg[MAXPLAYERS + 1];

// Handle to the SM admin top menu — stored so we can navigate back to it
// from the player selection menu. Nulled in OnLibraryRemoved.
TopMenu g_hAdminMenu = null;

// ────────────────────────────────────────────────────────────────────────────
// Plugin lifecycle
// ────────────────────────────────────────────────────────────────────────────

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("dod_blaster.phrases");

	CreateConVar("sm_blast_version", PLUGIN_VERSION, "dod_blaster version",
		FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY);

	RegAdminCmd("sm_blast", Command_Blast, ADMFLAG_SLAY,
		"sm_blast <#userid|name> - Slay target(s) with a lightning bolt.");

	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);

	// OnAdminMenuReady only fires when adminmenu itself (re)loads.
	// If this plugin loads after adminmenu — the common case on a live server
	// — we must register immediately. Use TopMenu typed variable (not Handle)
	// to match the type expected by the duplicate-check guard in
	// OnAdminMenuReady; mismatching types cause the guard to fire falsely.
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
	{
		OnAdminMenuReady(topmenu);
	}
}

public void OnMapStart()
{
	PrecacheSound(SOUND_THUNDER_1, true);
	PrecacheSound(SOUND_THUNDER_2, true);
	g_SmokeSprite     = PrecacheModel("sprites/steam1.vmt");
	g_LightningSprite = PrecacheModel("sprites/lgtning.vmt");
}

// ────────────────────────────────────────────────────────────────────────────
// Admin menu integration
// ────────────────────────────────────────────────────────────────────────────

/**
 * Called when adminmenu unloads. Clear the stored handle so that
 * OnAdminMenuReady can re-register cleanly when adminmenu reloads.
 * Without this the duplicate-check guard in OnAdminMenuReady compares
 * a stale handle against the new one and blocks re-registration.
 */
public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "adminmenu"))
	{
		g_hAdminMenu = null;
	}
}

/**
 * Called when the admin menu is ready to have items added.
 * Also called manually from OnPluginStart when adminmenu is already loaded.
 */
public void OnAdminMenuReady(Handle aTopMenu)
{
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);

	// Duplicate-check guard — prevents double-registration if both the manual
	// OnPluginStart call and the real forward fire for the same menu handle
	if (topmenu == g_hAdminMenu)
	{
		return;
	}

	g_hAdminMenu = topmenu;

	TopMenuObject playerCommands = g_hAdminMenu.FindCategory(ADMINMENU_PLAYERCOMMANDS);
	if (playerCommands != INVALID_TOPMENUOBJECT)
	{
		g_hAdminMenu.AddItem(
			"sm_blast",      // unique item name (also used in adminmenu_sorting.txt)
			AdminMenu_Blast, // display/select callback
			playerCommands,  // parent category
			"sm_blast",      // command whose access flags are checked for visibility
			ADMFLAG_SLAY     // required admin flag
		);
	}
}

/**
 * Top-menu callback — renders the menu label and handles selection.
 * param = client index of the admin viewing/selecting the menu.
 * Uses %T (capital) for per-client language translation.
 */
public void AdminMenu_Blast(TopMenu topmenu, TopMenuAction action,
	TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%T", "Blast Player", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		ShowBlastMenu(param);
	}
}

/**
 * Builds and displays the player-selection menu for the admin.
 * Manually iterates all clients to include dead players while still
 * excluding spectators (team < TEAM_ALLIES) and unassigned players.
 *
 * @param client    Admin client index.
 */
void ShowBlastMenu(int client)
{
	Menu menu = new Menu(BlastMenuHandler);
	menu.ExitBackButton = true;

	// SetMenuTitle is not variadic — format into a buffer first
	char title[64];
	Format(title, sizeof(title), "%T", "Blast Player", client);
	menu.SetTitle(title);

	char info[12];
	char name[MAX_NAME_LENGTH];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		if (GetClientTeam(i) < TEAM_ALLIES)  // exclude unassigned (0) and spectators (1)
			continue;
		if (!CanUserTarget(client, i))        // respect immunity
			continue;

		Format(info, sizeof(info), "%d", GetClientUserId(i));
		GetClientName(i, name, sizeof(name));
		menu.AddItem(info, name);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

/**
 * Handles selections and cancellations from the player-selection menu.
 * Mirrors the pattern used in official SM slay.sp and ban.sp.
 */
public int BlastMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
	}
	else if (action == MenuAction_Cancel)
	{
		// "Back" button — return the admin to the Player Commands category
		if (param2 == MenuCancel_ExitBack && g_hAdminMenu != null)
		{
			g_hAdminMenu.Display(param1, TopMenuPosition_LastCategory);
		}
	}
	else if (action == MenuAction_Select)
	{
		char info[12];
		menu.GetItem(param2, info, sizeof(info));
		int target = GetClientOfUserId(StringToInt(info));

		if (target == 0)
		{
			// Player disconnected between menu open and selection
			PrintToChat(param1, "[SM] %t", "Player no longer available");
		}
		else if (!CanUserTarget(param1, target))
		{
			// Immunity check — admin cannot target this player
			PrintToChat(param1, "[SM] %t", "Unable to target");
		}
		else
		{
			PerformBlast(param1, target);
		}

		// Redisplay so the admin can blast multiple players without reopening
		ShowBlastMenu(param1);
	}

	return 0;
}

// ────────────────────────────────────────────────────────────────────────────
// Client events — reset per-client state on connect and disconnect
// ────────────────────────────────────────────────────────────────────────────

public void OnClientPostAdminCheck(int client)
{
	g_bSuppressTeamMsg[client] = false;
}

public void OnClientDisconnect(int client)
{
	g_bSuppressTeamMsg[client] = false;
}

// ────────────────────────────────────────────────────────────────────────────
// Event hooks
// ────────────────────────────────────────────────────────────────────────────

/**
 * Suppresses the "player joined team X" chat notification that is broadcast
 * when we temporarily switch a stubborn target's team to force a kill.
 */
public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (g_bSuppressTeamMsg[client])
	{
		g_bSuppressTeamMsg[client] = false;
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

// ────────────────────────────────────────────────────────────────────────────
// Command handler
// ────────────────────────────────────────────────────────────────────────────

public Action Command_Blast(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "%t", "Blast Usage");
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));

	char targetName[MAX_TARGET_LENGTH];
	int  targetList[MAXPLAYERS];
	bool tnIsML;

	int targetCount = ProcessTargetString(
		arg, client,
		targetList, MAXPLAYERS,
		COMMAND_FILTER_NO_BOTS,   // exclude bots; alive and dead players both valid
		targetName, sizeof(targetName),
		tnIsML);

	if (targetCount <= 0)
	{
		ReplyToTargetError(client, targetCount);
		return Plugin_Handled;
	}

	for (int i = 0; i < targetCount; i++)
	{
		PerformBlast(client, targetList[i]);
	}

	// Broadcast a translated warning to all players.
	// tnIsML true = target name is itself a translation key (e.g. "@all"),
	// use %t with {t} so SM translates per-recipient. Otherwise plain {s}.
	if (tnIsML)
	{
		PrintToChatAll("\x04[SM]\x01 %t", "Blast Broadcast ML", targetName);
	}
	else
	{
		PrintToChatAll("\x04[SM]\x01 %t", "Blast Broadcast", targetName);
	}

	return Plugin_Handled;
}

// ────────────────────────────────────────────────────────────────────────────
// Core blast logic
// ────────────────────────────────────────────────────────────────────────────

/**
 * Plays the visual/audio effects on a target then kills them.
 *
 * @param client    Admin who issued the command (0 = server).
 * @param target    Client index of the player to blast.
 */
void PerformBlast(int client, int target)
{
	LogAction(client, target, "\"%L\" blasted \"%L\"", client, target);

	// Target position — offset upward to hit the player's chest
	float targetPos[3];
	GetClientAbsOrigin(target, targetPos);
	targetPos[2] += BEAM_HEIGHT_OFFSET;

	// Beam origin — randomly offset in X/Y and elevated above the target
	float startPos[3];
	startPos[0] = targetPos[0] + float(GetRandomInt(-BEAM_SPREAD, BEAM_SPREAD));
	startPos[1] = targetPos[1] + float(GetRandomInt(-BEAM_SPREAD, BEAM_SPREAD));
	startPos[2] = targetPos[2] + BEAM_START_HEIGHT;

	int   color[4] = { 255, 255, 255, 255 };
	float dir[3]   = { 0.0, 0.0, 0.0 };

	// Lightning beam
	TE_SetupBeamPoints(startPos, targetPos, g_LightningSprite, 0,
		0, 0, 0.2, 20.0, 10.0, 0, 1.0, color, 3);
	TE_SendToAll();

	// Electrical sparks at impact point
	TE_SetupSparks(targetPos, dir, 5000, 1000);
	TE_SendToAll();

	// Energy splash
	TE_SetupEnergySplash(targetPos, dir, false);
	TE_SendToAll();

	// Smoke puff
	TE_SetupSmoke(targetPos, g_SmokeSprite, 5.0, 10);
	TE_SendToAll();

	// Thunder sounds originating from the beam start point
	EmitAmbientSound(SOUND_THUNDER_1, startPos, target, SNDLEVEL_RAIDSIREN);
	EmitAmbientSound(SOUND_THUNDER_2, startPos, target, SNDLEVEL_RAIDSIREN);

	// Schedule ragdoll dissolve just after death is processed
	CreateTimer(0.1, Timer_DissolveRagdoll, target);

	// Attempt a clean suicide first; fall back to the team-swap trick for
	// players who are in a spawn zone and cannot be killed normally
	ForcePlayerSuicide(target);
	if (IsPlayerAlive(target))
	{
		SureKillPlayer(target);
	}
}

// ────────────────────────────────────────────────────────────────────────────
// Timers
// ────────────────────────────────────────────────────────────────────────────

public Action Timer_DissolveRagdoll(Handle timer, int target)
{
	// Ensure the client is still valid before touching their ragdoll
	if (!IsClientInGame(target))
	{
		return Plugin_Stop;
	}

	int ragdoll = GetEntPropEnt(target, Prop_Send, "m_hRagdoll");
	if (ragdoll != -1)
	{
		DissolveRagdoll(ragdoll);
	}

	return Plugin_Stop;
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

/**
 * Attaches an env_entity_dissolver to a ragdoll entity and fires it.
 *
 * @param ragdoll   Entity index of the ragdoll to dissolve.
 */
void DissolveRagdoll(int ragdoll)
{
	int dissolver = CreateEntityByName("env_entity_dissolver");
	if (dissolver == -1)
	{
		return;
	}

	DispatchKeyValue(dissolver, "dissolvetype", "0");
	DispatchKeyValue(dissolver, "magnitude",    "1");
	DispatchKeyValue(dissolver, "target",       "!activator");

	AcceptEntityInput(dissolver, "Dissolve", ragdoll);
	AcceptEntityInput(dissolver, "Kill");
}

/**
 * Guarantees a kill by temporarily switching the target to the opposing team
 * and back, suppressing both broadcast messages. Used when ForcePlayerSuicide
 * fails (e.g. inside spawn zones).
 *
 * @param target    Client index of the player to kill.
 */
stock void SureKillPlayer(int target)
{
	int team   = GetClientTeam(target);
	int opTeam = (team == TEAM_ALLIES) ? TEAM_AXIS : TEAM_ALLIES;

	// Switch away — suppress the team-change broadcast
	g_bSuppressTeamMsg[target] = true;
	ChangeClientTeam(target, opTeam);
	ShowVGUIPanel(target, (opTeam == TEAM_AXIS) ? "class_ger" : "class_us", INVALID_HANDLE, false);

	// Switch back — suppress the return broadcast
	g_bSuppressTeamMsg[target] = true;
	ChangeClientTeam(target, team);
	ShowVGUIPanel(target, (team == TEAM_AXIS) ? "class_ger" : "class_us", INVALID_HANDLE, false);
}
