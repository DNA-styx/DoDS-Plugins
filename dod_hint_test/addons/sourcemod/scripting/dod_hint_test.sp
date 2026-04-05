#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0.3"

public Plugin myinfo =
{
    name        = "DoDS Spawn Hint",
    author      = "DNA.styx",
    description = "Tests hint not being displayed after being killed.",
    version     = PLUGIN_VERSION,
    url         = ""
};

public void OnPluginStart()
{
    HookEvent("player_spawn", Event_PlayerSpawn);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int userid = event.GetInt("userid");
    CreateTimer(0.5, Timer_SpawnHint, userid);
}

public Action Timer_SpawnHint(Handle timer, int userid)
{
    RequestFrame(Frame_SpawnHint, userid);
    return Plugin_Stop;
}

public void Frame_SpawnHint(int userid)
{
    int client = GetClientOfUserId(userid);

    if (client == 0 || !IsClientInGame(client))
        return;

    PrintHintText(client, "Test");
    PrintToChat(client, "Test to chat");
}