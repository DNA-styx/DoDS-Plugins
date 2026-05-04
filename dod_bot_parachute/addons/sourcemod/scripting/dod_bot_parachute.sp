#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.1"

// Falling velocity threshold (negative Z velocity)
#define FALL_THRESHOLD -300.0

// Track which bots are currently using parachute
bool g_bUsingParachute[MAXPLAYERS + 1];

public Plugin myinfo = 
{
    name = "Bot Auto-Parachute",
    author = "Claude.ai. guided by DNA.styx",
    description = "Automatically activates parachutes for bots when falling",
    version = PLUGIN_VERSION,
    url = "https://github.com/DNA-styx/DoDS-Plugins"
};

public void OnPluginStart()
{
    // Create a repeating timer to check bot states every 0.1 seconds
    CreateTimer(0.1, Timer_CheckBots, _, TIMER_REPEAT);
}

public void OnClientDisconnect(int client)
{
    // Clean up tracking when client disconnects
    g_bUsingParachute[client] = false;
}

public Action Timer_CheckBots(Handle timer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        // Skip if not connected, not in game, or not a bot
        if (!IsClientInGame(client) || !IsFakeClient(client))
            continue;
        
        // Skip if dead
        if (!IsPlayerAlive(client))
        {
            g_bUsingParachute[client] = false;
            continue;
        }
        
        // Check if bot is in the air
        int groundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
        bool isOnGround = (groundEntity != -1);
        
        if (!isOnGround)
        {
            // If not already using parachute, check if we should activate it
            if (!g_bUsingParachute[client])
            {
                // Get velocity to check if falling
                float velocity[3];
                GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
                
                // If falling fast enough, activate parachute
                if (velocity[2] < FALL_THRESHOLD)
                {
                    g_bUsingParachute[client] = true;
                }
            }
            
            // If parachute is active, keep holding +use
            if (g_bUsingParachute[client])
            {
                int buttons = GetClientButtons(client);
                buttons |= IN_USE;
                SetEntProp(client, Prop_Data, "m_nButtons", buttons);
            }
        }
        else
        {
            // Bot is on ground, release parachute
            if (g_bUsingParachute[client])
            {
                g_bUsingParachute[client] = false;
            }
        }
    }
    
    return Plugin_Continue;
}
