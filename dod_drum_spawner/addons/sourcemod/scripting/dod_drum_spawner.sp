/* Explosive Oildrum Spawner by KTM! */
#include <sourcemod>
#include <sdktools>

// ── Constants ────────────────────────────────────────────────────────────────
#define DRUM_MODEL          "models/props_c17/oildrum001_explosive.mdl"
#define BEAM_SPRITE         "materials/sprites/laser.vmt"
#define HALO_SPRITE         "materials/sprites/halo01.vmt"

#define DRUM_HEALTH         "20"
#define DRUM_EXPLODE_DMG    "120"
#define DRUM_EXPLODE_RADIUS "256"
#define DRUM_SPAWNFLAGS     "8192"

#define DRUM_Z_OFFSET       15.0
#define DRUM_BEAM_Z_OFFSET  20.0
#define DRUM_SPAWN_COOLDOWN 3.0
#define DRUM_MAX_PER_PLAYER 5

// ── Globals ───────────────────────────────────────────────────────────────────
int   g_BeamSprite;
int   g_HaloSprite;
int   g_DrumCount[MAXPLAYERS + 1];
float g_LastSpawn[MAXPLAYERS + 1];
int   redColor[4] = {200, 25, 25, 255};

// ── Plugin Info ───────────────────────────────────────────────────────────────
public Plugin myinfo =
{
	name        = "Explosive_oildrum_spawner",
	author      = "KTM, claude.ai guided by DNA.styx",
	description = "Spawns an explosive oildrum",
	version     = "1.3",
	url         = "https://forums.alliedmods.net/showthread.php?t=194301"
};

// ── Plugin Start ──────────────────────────────────────────────────────────────
public void OnPluginStart()
{
	CreateConVar("explosive_oildrum_version", "1.3",
		"KTM's explosive oildrum spawner!",
		FCVAR_SPONLY | FCVAR_UNLOGGED | FCVAR_DONTRECORD | FCVAR_REPLICATED | FCVAR_NOTIFY);

	RegAdminCmd("sm_spawndrum", Command_Spawndrum, ADMFLAG_SLAY, "Spawns an explosive oildrum");

	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
}

// ── Map Start ─────────────────────────────────────────────────────────────────
public void OnMapStart()
{
	g_BeamSprite = PrecacheModel(BEAM_SPRITE);
	g_HaloSprite = PrecacheModel(HALO_SPRITE);
}

// Reset a player's drum count when they leave
public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		g_DrumCount[client] = 0;
		g_LastSpawn[client] = 0.0;
	}
	return Plugin_Continue;
}

// Reset drum counts each new map so limits don't carry across map changes
public void OnMapEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_DrumCount[i] = 0;
		g_LastSpawn[i] = 0.0;
	}
}

// ── Spawn Command ─────────────────────────────────────────────────────────────
public Action Command_Spawndrum(int client, int args)
{
	// Validity check
	if (client <= 0 || !IsClientInGame(client))
		return Plugin_Handled;

	// Cooldown check
	float now = GetGameTime();
	if (now - g_LastSpawn[client] < DRUM_SPAWN_COOLDOWN)
	{
		PrintToChat(client, " \x04[Oildrum]\x01 You must wait before spawning another drum.");
		return Plugin_Handled;
	}

	// Per-player limit check
	if (g_DrumCount[client] >= DRUM_MAX_PER_PLAYER)
	{
		PrintToChat(client, " \x04[Oildrum]\x01 You have reached the limit of %d drums.", DRUM_MAX_PER_PLAYER);
		return Plugin_Handled;
	}

	// Work out where the admin is looking
	float absAngles[3], spawnAngles[3], spawnPos[3], beamPos[3];

	GetClientAbsAngles(client, absAngles);
	GetCollisionPoint(client, spawnPos);

	// Keep only yaw so the drum always stands upright
	spawnAngles[0] = 0.0;
	spawnAngles[1] = absAngles[1];
	spawnAngles[2] = 0.0;

	spawnPos[2] += DRUM_Z_OFFSET;
	beamPos[0]   = spawnPos[0];
	beamPos[1]   = spawnPos[1];
	beamPos[2]   = spawnPos[2] + DRUM_BEAM_Z_OFFSET;

	// Spawn the drum entity
	int drum = CreateEntityByName("prop_physics_override");
	if (drum == -1)
	{
		PrintToChat(client, " \x04[Oildrum]\x01 Failed to create drum entity.");
		return Plugin_Handled;
	}

	TeleportEntity(drum, spawnPos, spawnAngles, NULL_VECTOR);

	DispatchKeyValue(drum, "model",         DRUM_MODEL);
	DispatchKeyValue(drum, "health",         DRUM_HEALTH);
	DispatchKeyValue(drum, "ExplodeDamage",  DRUM_EXPLODE_DMG);
	DispatchKeyValue(drum, "ExplodeRadius",  DRUM_EXPLODE_RADIUS);
	DispatchKeyValue(drum, "spawnflags",     DRUM_SPAWNFLAGS);
	DispatchSpawn(drum);
	ActivateEntity(drum);

	// Update counters
	g_DrumCount[client]++;
	g_LastSpawn[client] = now;

	// Visual ring effect
	TE_SetupBeamRingPoint(spawnPos, 10.0, 150.0,
		g_BeamSprite, g_HaloSprite,
		0, 10, 0.6, 10.0, 0.5,
		redColor, 20, 0);
	TE_SendToAll();

	return Plugin_Handled;
}

// ── Helpers ───────────────────────────────────────────────────────────────────
stock void GetCollisionPoint(int client, float pos[3])
{
	float vOrigin[3], vAngles[3];

	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);

	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SOLID, RayType_Infinite, TraceEntityFilterPlayer);

	if (TR_DidHit(trace))
		TR_GetEndPosition(pos, trace);
	else
		GetClientAbsOrigin(client, pos); // fallback: spawn at feet

	delete trace;
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask)
{
	return entity > MaxClients;
}
