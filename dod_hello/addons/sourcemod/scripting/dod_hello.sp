#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

char g_sLatestPlayer[MAX_NAME_LENGTH];

public Plugin myinfo = 
{
    name = "Admin Welcome Greet",
    author = "Gemini, guided by DNA.styx",
    description = "Admins 'say' a welcome message to the latest joiner.",
    version = "1.1",
    url = "https://github.com/DNA-styx/DoDS-Plugins"
};

public void OnPluginStart()
{
    RegAdminCmd("sm_hello", Command_Hello, ADMFLAG_GENERIC, "Greets the latest player as the admin.");
}

public void OnClientPostAdminCheck(int client)
{
    // Update the name whenever a real player connects.
    if (!IsFakeClient(client))
    {
        GetClientName(client, g_sLatestPlayer, sizeof(g_sLatestPlayer));
    }
}

public Action Command_Hello(int client, int args)
{
    char sBuffer[255];
    Format(sBuffer, sizeof(sBuffer), "Hi %s - Welcome", g_sLatestPlayer);

    if (client == 0) 
    {
        // For Server Console execution
        PrintToChatAll("Console: %s", sBuffer);
    }
    else 
    {
        // Forces the admin to say the message in chat
        FakeClientCommand(client, "say %s", sBuffer);
    }

    return Plugin_Handled;
}