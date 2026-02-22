 // Plugin modifications
// 1.0 version
// From : Admin Smite by Hipster
// http://forums.alliedmods.net/showthread.php?t=118534
// Adapted for DoDs with help of snippet from FeuerSturm
// http://forums.alliedmods.net/showthread.php?t=78512
// Now it kills in Spawn Area !
// Yeah :)
// 1.1 version
// added dissolve effect
// with snippet Dissolve Ragdolls
// http://forums.alliedmods.net/showthread.php?t=161012

#include <sourcemod>
#include <sdktools>
#undef REQUIRE_PLUGIN

#define PLUGIN_VERSION "1.1"
#define SOUND_THUNDER_1 "ambient/explosions/explode_9.wav"
#define SOUND_THUNDER_2 "ambient/explosions/explode_6.wav"
#define ALLIES 2
#define AXIS 3

public Plugin:myinfo = 
{
	name = "dod_blaster", 
	author = "Hipster,FeuerSturm,vintage pour DoDs", 
	description = "Slay players with a lightning and dissolve effect", 
	version = PLUGIN_VERSION, 
	url = ""
}

new g_SmokeSprite
new g_LightningSprite
new g_nomessage[MAXPLAYERS + 1]

public OnPluginStart()
{
	LoadTranslations("common.phrases")
	
	CreateConVar("sm_blast_version", PLUGIN_VERSION, "dod_blast Version", FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY)
	RegAdminCmd("sm_blast", Command_Blast, ADMFLAG_SLAY, "sm_blast <#userid|name> - Slay with a lightning bolt effect.")
	HookEvent("player_team", Surpress_TeamMSG, EventHookMode_Pre)
}

public OnMapStart()
{
	PrecacheSound(SOUND_THUNDER_1, true)
	PrecacheSound(SOUND_THUNDER_2, true)
	g_SmokeSprite = PrecacheModel("sprites/steam1.vmt")
	g_LightningSprite = PrecacheModel("sprites/lgtning.vmt")
}

public OnClientPostAdminCheck(client)
{
	g_nomessage[client] = 0
}

public OnClientDisconnect(client)
{
	g_nomessage[client] = 0
}

public Action:Surpress_TeamMSG(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"))
	if (g_nomessage[client] == 1)
	{
		g_nomessage[client] = 0
		return Plugin_Handled
	}
	return Plugin_Continue
}


public Action:PerformBlast(client, target)
{
	LogAction(client, target, "\"%L\" blast \"%L\"", client, target)
	
	// define where the lightning strike ends
	new Float:targetpos[3]
	GetClientAbsOrigin(target, targetpos)
	targetpos[2] += 26 // increase y-axis by 26 to strike at player's chest instead of the ground
	
	// get random numbers for the x and y starting positions
	new randomx = GetRandomInt(-500, 500)
	new randomy = GetRandomInt(-500, 500)
	
	// define where the lightning strike starts
	new Float:startpos[3]
	startpos[0] = targetpos[0] + randomx
	startpos[1] = targetpos[1] + randomy
	startpos[2] = targetpos[2] + 800
	
	// define the color of the strike
	new color[4] =  { 255, 255, 255, 255 }
	
	// define the direction of the sparks
	new Float:dir[3] =  { 0.0, 0.0, 0.0 }
	
	TE_SetupBeamPoints(startpos, targetpos, g_LightningSprite, 0, 0, 0, 0.2, 20.0, 10.0, 0, 1.0, color, 3)
	TE_SendToAll()
	
	TE_SetupSparks(targetpos, dir, 5000, 1000)
	TE_SendToAll()
	
	TE_SetupEnergySplash(targetpos, dir, false)
	TE_SendToAll()
	
	TE_SetupSmoke(targetpos, g_SmokeSprite, 5.0, 10)
	TE_SendToAll()
	
	EmitAmbientSound(SOUND_THUNDER_1, startpos, target, SNDLEVEL_RAIDSIREN)
	EmitAmbientSound(SOUND_THUNDER_2, startpos, target, SNDLEVEL_RAIDSIREN)
	
	CreateTimer(0.1, Timer_DissolveRagdoll, any:target)
	
	ForcePlayerSuicide(target)
	if (IsPlayerAlive(target))
	{
		SureKillPlayer(target)
		return Plugin_Handled
	}
	else
	{
		return Plugin_Handled
	}
}

public Action:Command_Blast(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_blast <#userid|name>")
		return Plugin_Handled
	}
	
	decl String:arg[65]
	GetCmdArg(1, arg, sizeof(arg))
	
	decl String:target_name[MAX_TARGET_LENGTH]
	decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml
	
	if ((target_count = ProcessTargetString(
				arg, 
				client, 
				target_list, 
				MAXPLAYERS, 
				COMMAND_FILTER_ALIVE, 
				target_name, 
				sizeof(target_name), 
				tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count)
		return Plugin_Handled
	}
	
	for (new i = 0; i < target_count; i++)
	{
		new target = target_list[i]
		PerformBlast(client, target)
	}
	
	if (!tn_is_ml)
	{
		PrintToChatAll("\x04[TDF Admin Warning !]\x01 Attention aux avertissements \x04Admins! \x04 Merci!")
	}
	
	return Plugin_Handled
}

public Action:Timer_DissolveRagdoll(Handle:timer, any:target)
{
	new ragdoll = GetEntPropEnt(target, Prop_Send, "m_hRagdoll")
	
	if (ragdoll != -1)
	{
		DissolveRagdoll(ragdoll)
	}
}

DissolveRagdoll(ragdoll)
{
	new dissolver = CreateEntityByName("env_entity_dissolver")
	
	if (dissolver == -1)
	{
		return 
	}
	
	DispatchKeyValue(dissolver, "dissolvetype", "0")
	DispatchKeyValue(dissolver, "magnitude", "1")
	DispatchKeyValue(dissolver, "target", "!activator")
	
	AcceptEntityInput(dissolver, "Dissolve", ragdoll)
	AcceptEntityInput(dissolver, "Kill")
	
	return 
}

stock SureKillPlayer(target)
{
	new Team = GetClientTeam(target)
	new OpTeam = Team == ALLIES ? AXIS : ALLIES
	SecretTeamSwitch(target, OpTeam)
	SecretTeamSwitch(target, Team)
}

stock SecretTeamSwitch(target, newteam)
{
	g_nomessage[target] = 1
	ChangeClientTeam(target, newteam)
	ShowVGUIPanel(target, newteam == AXIS ? "class_ger" : "class_us", INVALID_HANDLE, false)
}
