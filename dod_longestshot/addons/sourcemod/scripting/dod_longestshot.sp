#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION  "1.4.dev.dna"
#define MIN_DISTANCE    75.0
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
float g_fDist[MAX_RECORDS];
char  g_sWeapon[MAX_RECORDS][64];
int   g_iRecordCount;

// Global StringMap to track the absolute longest shot per weapon for chat announcements
StringMap g_smWeaponRecords;

public void OnPluginStart()
{
    g_smWeaponRecords = new StringMap();

    HookEvent("player_death", Event_PlayerDeath);
    RegConsoleCmd("sm_shots", Command_Shots, "Show longest shots this map");
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

void ResetRecords()
{
    g_iRecordCount = 0;
    for (int i = 0; i < MAX_RECORDS; i++)
    {
        g_sName[i][0]       = '\0';
        g_sVictimName[i][0] = '\0';
        g_fDist[i]          = 0.0;
        g_sWeapon[i][0]     = '\0';
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

    if (distance < MIN_DISTANCE)
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

    float currentBest = 0.0;
    g_smWeaponRecords.GetValue(displayWeapon, currentBest);

    bool isNewWeaponRecord = false;
    if (distance > currentBest)
    {
        g_smWeaponRecords.SetValue(displayWeapon, distance);
        isNewWeaponRecord = true;
    }

    InsertRecord(shooterName, victimName, distance, displayWeapon);

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

void InsertRecord(const char[] playerName, const char[] victimName, float distance, const char[] weapon)
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
            strcopy(g_sName[i],       sizeof(g_sName[]),       g_sName[i+1]);
            strcopy(g_sVictimName[i], sizeof(g_sVictimName[]), g_sVictimName[i+1]);
            g_fDist[i] = g_fDist[i+1];
            strcopy(g_sWeapon[i],     sizeof(g_sWeapon[]),     g_sWeapon[i+1]);
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
        strcopy(g_sName[i],       sizeof(g_sName[]),       g_sName[i-1]);
        strcopy(g_sVictimName[i], sizeof(g_sVictimName[]), g_sVictimName[i-1]);
        g_fDist[i] = g_fDist[i-1];
        strcopy(g_sWeapon[i],     sizeof(g_sWeapon[]),     g_sWeapon[i-1]);
    }

    strcopy(g_sName[insertPos],       sizeof(g_sName[]),       playerName);
    strcopy(g_sVictimName[insertPos], sizeof(g_sVictimName[]), victimName);
    g_fDist[insertPos] = distance;
    strcopy(g_sWeapon[insertPos],     sizeof(g_sWeapon[]),     weapon);

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
        menu.AddItem("", "No qualifying shots yet. (min 75m)");
    }
    else
    {
        char line[128];
        for (int i = 0; i < g_iRecordCount; i++)
        {
            Format(line, sizeof(line), "%s vs. %s | %s | %.0fm",
                g_sName[i],
                g_sVictimName[i],
                g_sWeapon[i],
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

    if      (StrEqual(stripped, "k98_scoped",    false)) strcopy(display, maxlen, "Kar98k Scoped");
    else if (StrEqual(stripped, "k98",           false)) strcopy(display, maxlen, "Kar98k");
    else if (StrEqual(stripped, "spring",        false)) strcopy(display, maxlen, "Springfield");
    else if (StrEqual(stripped, "garand",        false)) strcopy(display, maxlen, "M1 Garand");
    else if (StrEqual(stripped, "mp40",          false)) strcopy(display, maxlen, "MP40");
    else if (StrEqual(stripped, "mp44",          false)) strcopy(display, maxlen, "MP44");
    else if (StrEqual(stripped, "bar",           false)) strcopy(display, maxlen, "BAR");
    else if (StrEqual(stripped, "30cal",         false)) strcopy(display, maxlen, "30 Cal MG");
    else if (StrEqual(stripped, "mg42",          false)) strcopy(display, maxlen, "MG42");
    else if (StrEqual(stripped, "thompson",      false)) strcopy(display, maxlen, "Thompson");
    else if (StrEqual(stripped, "greasegun",     false)) strcopy(display, maxlen, "Grease Gun");
    else if (StrEqual(stripped, "colt",          false)) strcopy(display, maxlen, "Colt .45");
    else if (StrEqual(stripped, "p38",           false)) strcopy(display, maxlen, "P38");
    else if (StrEqual(stripped, "c96",           false)) strcopy(display, maxlen, "C96");
    else if (StrEqual(stripped, "bazooka",       false)) strcopy(display, maxlen, "Bazooka");
    else if (StrEqual(stripped, "pschreck",      false)) strcopy(display, maxlen, "Panzerschreck");
    else if (StrEqual(stripped, "riflegren_us",  false) ||
             StrEqual(stripped, "riflegren_ger", false)) strcopy(display, maxlen, "Rifle Grenade");
    else if (StrEqual(stripped, "frag_us",       false) ||
             StrEqual(stripped, "frag_ger",      false)) strcopy(display, maxlen, "Grenade");
    else if (StrEqual(stripped, "smoke_us",      false) ||
             StrEqual(stripped, "smoke_ger",     false)) strcopy(display, maxlen, "Smoke Grenade");
    else
    {
        strcopy(display, maxlen, stripped);
        if (display[0] >= 'a' && display[0] <= 'z')
            display[0] -= 32;
    }
}
