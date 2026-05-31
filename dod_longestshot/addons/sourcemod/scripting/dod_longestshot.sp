#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION  "1.10.dev.dna"
#define MAX_RECORDS     10

// DoD:S Team Constants
#define TEAM_ALLIES     2
#define TEAM_AXIS       3

// Source engine Hammer unit to metre conversion.
// Map/world scale: 1 foot = 16 HU, so 1 metre = 52.49 HU.
#define UNITS_PER_METRE 52.49

public Plugin myinfo =
{
    name        = "Longest Shot Tracker",
    author      = "Knoxville, Claude.ai guided by DNA.styx",
    description = "Tracks top 10 longest kill shots per map. Type !shots to view.",
    version     = PLUGIN_VERSION,
    url         = ""
};

// Per-record data
char  g_sName[MAX_RECORDS][64];
char  g_sVictimName[MAX_RECORDS][64];
char  g_sSteamID[MAX_RECORDS][32];       // Killer's SteamID, stored at kill time
int   g_iTeam[MAX_RECORDS];              // Killer's team, stored at kill time
float g_fDist[MAX_RECORDS];
char  g_sWeapon[MAX_RECORDS][64];        // Raw weapon name, used in logs
char  g_sWeaponDisplay[MAX_RECORDS][64]; // Display weapon name, used in panel

int   g_iRecordCount;

// Global StringMap to track the absolute longest shot per weapon for chat announcements
StringMap g_smWeaponRecords;

ConVar g_cvMinDistance;

public void OnPluginStart()
{
    g_smWeaponRecords = new StringMap();

    g_cvMinDistance = CreateConVar(
        "sm_longestshot_min_distance",
        "50",
        "Minimum distance in metres for a shot to qualify for the leaderboard.",
        FCVAR_NONE, true, 1.0
    );

    HookEvent("player_death", Event_PlayerDeath);
    RegConsoleCmd("sm_shots", Command_Shots, "Show longest shots this map");

    AutoExecConfig(true, "dod_longestshot");
}

bool g_bPanelShown;

public void OnMapStart()
{
    ResetRecords();
    g_smWeaponRecords.Clear();
    g_bPanelShown = false;
    CreateTimer(5.0, Timer_CheckTimeLeft, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_CheckTimeLeft(Handle timer)
{
    if (g_bPanelShown)
        return Plugin_Stop;

    int timeLeft;
    if (!GetMapTimeLeft(timeLeft))
        return Plugin_Continue;

    if (timeLeft > 0 && timeLeft <= 10 && g_iRecordCount > 0)
    {
        g_bPanelShown = true;

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i) || IsFakeClient(i))
                continue;

            ShowShotsPanel(i, 9);
        }

        return Plugin_Stop;
    }

    return Plugin_Continue;
}

public void OnMapEnd()
{
    // Log the winner at true map end regardless of how the map ended.
    // Uses stored SteamID and team so it works even if the player has disconnected.
    if (g_iRecordCount > 0)
    {
        LogToGame("\"%s<0><%s><%s>\" triggered \"longshot_winner\"",
            g_sName[0],
            g_sSteamID[0],
            LongShot_GetTeamName(g_iTeam[0])
        );
    }
}

void ResetRecords()
{
    g_iRecordCount = 0;
    for (int i = 0; i < MAX_RECORDS; i++)
    {
        g_sName[i][0]          = '\0';
        g_sVictimName[i][0]    = '\0';
        g_sSteamID[i][0]       = '\0';
        g_iTeam[i]             = 0;
        g_fDist[i]             = 0.0;
        g_sWeapon[i][0]        = '\0';
        g_sWeaponDisplay[i][0] = '\0';
    }
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim   = GetClientOfUserId(event.GetInt("userid"));

    if (attacker <= 0 || victim <= 0 || attacker == victim)
        return Plugin_Continue;

    if (!IsClientInGame(attacker) || !IsClientInGame(victim))
        return Plugin_Continue;

    if (IsFakeClient(attacker) || IsFakeClient(victim))
        return Plugin_Continue;

    float vAttacker[3], vVictim[3];
    GetClientAbsOrigin(attacker, vAttacker);
    GetClientAbsOrigin(victim, vVictim);

    float distance = GetVectorDistance(vAttacker, vVictim) / UNITS_PER_METRE;

    if (distance < g_cvMinDistance.FloatValue)
        return Plugin_Continue;

    char rawWeapon[64], displayWeapon[64];
    event.GetString("weapon", rawWeapon, sizeof(rawWeapon));

    char stripped[64];
    if (StrContains(rawWeapon, "weapon_") == 0)
        strcopy(stripped, sizeof(stripped), rawWeapon[7]);
    else
        strcopy(stripped, sizeof(stripped), rawWeapon);

    if (!StrEqual(stripped, "k98_scoped", false) &&
        !StrEqual(stripped, "spring",     false) &&
        !StrEqual(stripped, "pschreck",   false) &&
        !StrEqual(stripped, "bazooka",    false))
    {
        return Plugin_Continue;
    }

    FormatWeaponName(rawWeapon, displayWeapon, sizeof(displayWeapon));

    char shooterName[64], victimName[64];
    GetClientName(attacker, shooterName, sizeof(shooterName));
    GetClientName(victim,   victimName,  sizeof(victimName));

    char attackerSteamID[32], victimSteamID[32];
    GetClientAuthId(attacker, AuthId_Steam2, attackerSteamID, sizeof(attackerSteamID));
    GetClientAuthId(victim,   AuthId_Steam2, victimSteamID,   sizeof(victimSteamID));

    int attackerUserID = GetClientUserId(attacker);
    int victimUserID   = GetClientUserId(victim);
    int attackerTeam   = GetClientTeam(attacker);
    int victimTeam     = GetClientTeam(victim);

    // Standard Source engine kill log — fires for every qualifying shot
    LogToGame("\"%s<%d><%s><%s>\" killed \"%s<%d><%s><%s>\" with \"longshot_%s\"",
        shooterName, attackerUserID, attackerSteamID, LongShot_GetTeamName(attackerTeam),
        victimName,  victimUserID,   victimSteamID,   LongShot_GetTeamName(victimTeam),
        stripped
    );

    float currentBest = 0.0;
    g_smWeaponRecords.GetValue(displayWeapon, currentBest);

    bool isNewWeaponRecord = false;
    if (distance > currentBest)
    {
        g_smWeaponRecords.SetValue(displayWeapon, distance);
        isNewWeaponRecord = true;
    }

    InsertRecord(shooterName, victimName, attackerSteamID, attackerTeam, distance, stripped, displayWeapon);

    if (isNewWeaponRecord)
    {
        char coloredKiller[128], coloredVictim[128];
        GetColoredName(attacker, coloredKiller, sizeof(coloredKiller));
        GetColoredName(victim,   coloredVictim, sizeof(coloredVictim));

        PrintToChatAll("\x01\x04[LongShot]\x01 %s\x01 killed %s\x01 with \x01%s\x01: \x01%.0fm",
            coloredKiller, coloredVictim, displayWeapon, distance);
    }

    return Plugin_Continue;
}

// Helper: return the DoD:S team name string used in standard game logs
char[] LongShot_GetTeamName(int team)
{
    char teamName[16];
    switch (team)
    {
        case TEAM_ALLIES: strcopy(teamName, sizeof(teamName), "Allies");
        case TEAM_AXIS:   strcopy(teamName, sizeof(teamName), "Axis");
        default:          strcopy(teamName, sizeof(teamName), "Unassigned");
    }
    return teamName;
}

// Helper: wrap a player name in their team colour using hex colour codes
void GetColoredName(int client, char[] buffer, int maxlen)
{
    char name[64];
    GetClientName(client, name, sizeof(name));
    int team = GetClientTeam(client);

    switch (team)
    {
        case TEAM_ALLIES:
            Format(buffer, maxlen, "\x074d7942%s", name); // Allied Green
        case TEAM_AXIS:
            Format(buffer, maxlen, "\x07ff4040%s", name); // Axis Red
        default:
            Format(buffer, maxlen, "\x01%s", name);       // Default White
    }
}

void InsertRecord(const char[] playerName, const char[] victimName, const char[] steamID, int team, float distance, const char[] weapon, const char[] weaponDisplay)
{
    int existingIndex = -1;
    for (int i = 0; i < g_iRecordCount; i++)
    {
        if (StrEqual(g_sName[i], playerName) && StrEqual(g_sWeapon[i], weapon))
        {
            existingIndex = i;
            break;
        }
    }

    if (existingIndex != -1)
    {
        if (distance <= g_fDist[existingIndex])
            return;

        for (int i = existingIndex; i < g_iRecordCount - 1; i++)
        {
            strcopy(g_sName[i],          sizeof(g_sName[]),          g_sName[i+1]);
            strcopy(g_sVictimName[i],    sizeof(g_sVictimName[]),    g_sVictimName[i+1]);
            strcopy(g_sSteamID[i],       sizeof(g_sSteamID[]),       g_sSteamID[i+1]);
            g_iTeam[i] = g_iTeam[i+1];
            g_fDist[i] = g_fDist[i+1];
            strcopy(g_sWeapon[i],        sizeof(g_sWeapon[]),        g_sWeapon[i+1]);
            strcopy(g_sWeaponDisplay[i], sizeof(g_sWeaponDisplay[]), g_sWeaponDisplay[i+1]);
        }
        g_iRecordCount--;
    }

    int insertPos = -1;
    for (int i = 0; i < MAX_RECORDS; i++)
    {
        if (i >= g_iRecordCount || distance > g_fDist[i])
        {
            insertPos = i;
            break;
        }
    }

    if (insertPos == -1)
        return;

    int shiftTo = (g_iRecordCount < MAX_RECORDS) ? g_iRecordCount : MAX_RECORDS - 1;
    for (int i = shiftTo; i > insertPos; i--)
    {
        strcopy(g_sName[i],          sizeof(g_sName[]),          g_sName[i-1]);
        strcopy(g_sVictimName[i],    sizeof(g_sVictimName[]),    g_sVictimName[i-1]);
        strcopy(g_sSteamID[i],       sizeof(g_sSteamID[]),       g_sSteamID[i-1]);
        g_iTeam[i] = g_iTeam[i-1];
        g_fDist[i] = g_fDist[i-1];
        strcopy(g_sWeapon[i],        sizeof(g_sWeapon[]),        g_sWeapon[i-1]);
        strcopy(g_sWeaponDisplay[i], sizeof(g_sWeaponDisplay[]), g_sWeaponDisplay[i-1]);
    }

    strcopy(g_sName[insertPos],          sizeof(g_sName[]),          playerName);
    strcopy(g_sVictimName[insertPos],    sizeof(g_sVictimName[]),    victimName);
    strcopy(g_sSteamID[insertPos],       sizeof(g_sSteamID[]),       steamID);
    g_iTeam[insertPos] = team;
    g_fDist[insertPos] = distance;
    strcopy(g_sWeapon[insertPos],        sizeof(g_sWeapon[]),        weapon);
    strcopy(g_sWeaponDisplay[insertPos], sizeof(g_sWeaponDisplay[]), weaponDisplay);

    if (g_iRecordCount < MAX_RECORDS)
        g_iRecordCount++;
}

public Action Command_Shots(int client, int args)
{
    if (client == 0)
    {
        PrintToServer("Command available in-game only.");
        return Plugin_Handled;
    }

    ShowShotsPanel(client, 15);
    return Plugin_Handled;
}

void ShowShotsPanel(int client, int duration)
{
    Menu menu = new Menu(Menu_Shots, MENU_ACTIONS_DEFAULT);
    menu.SetTitle("= LONGEST SHOTS THIS MAP =");

    if (g_iRecordCount == 0)
    {
        char emptyMsg[64];
        Format(emptyMsg, sizeof(emptyMsg), "No qualifying shots yet. (min %.0fm)", g_cvMinDistance.FloatValue);
        menu.AddItem("", emptyMsg);
    }
    else
    {
        char line[128];
        for (int i = 0; i < g_iRecordCount; i++)
        {
            Format(line, sizeof(line), "%s vs. %s | %s | %.0fm",
                g_sName[i],
                g_sVictimName[i],
                g_sWeaponDisplay[i],
                g_fDist[i]
            );
            menu.AddItem("", line);
        }
    }

    menu.ExitButton = true;
    menu.Display(client, duration);
}

public int Menu_Shots(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

void FormatWeaponName(const char[] raw, char[] display, int maxlen)
{
    char stripped[64];

    if (StrContains(raw, "weapon_") == 0)
        strcopy(stripped, sizeof(stripped), raw[7]);
    else
        strcopy(stripped, sizeof(stripped), raw);

    if      (StrEqual(stripped, "k98_scoped", false)) strcopy(display, maxlen, "Kar98k Scoped");
    else if (StrEqual(stripped, "spring",     false)) strcopy(display, maxlen, "Springfield");
    else if (StrEqual(stripped, "pschreck",   false)) strcopy(display, maxlen, "Panzerschreck");
    else if (StrEqual(stripped, "bazooka",    false)) strcopy(display, maxlen, "Bazooka");
}
