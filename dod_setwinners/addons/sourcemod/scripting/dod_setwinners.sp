/**
 * dod_setwinners.sp
 *
 * Sets the winning team at map end in favour of the team with more tick points.
 * Re-arms automatically when mp_timelimit changes (e.g. via a player vote).
 *
 * Based on "DoD:S Set Winners" by Root.
 * Modernised to SM 1.12 syntax by Claude.ai guided by DNA.styx
 *
 * Changelog:
 *   2.0.7 - Modernised to SM 1.12 (new syntax, typed vars, methodmap ConVars)
 *           Switched from dodhooks to dronelektron/sm-dod-hooks via #include "dod-hooks/api"
 *           Uses Team_Allies/Team_Axis enum constants from dod-hooks/api
 *           Timer re-arms on mp_timelimit change (vote-extend support)
 *           Fixed off-by-one: replaced TEAM_SIZE array with explicit per-team variables
 *           Removed FCVAR_PLUGIN (invalid in SM 1.12)
 *           5-second centre-screen countdown fires before bonus round starts
 *           Broadcasts team-coloured chat message with winner and point totals on map end
 *   1.0   - Initial release by Root
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include "dod-hooks/api"

#define PLUGIN_VERSION  "2.0.7"

#define COLOR_ALLIES    "\x074d7942"
#define COLOR_AXIS      "\x07ff4040"
#define COLOR_TAG       "\x04"
#define COLOR_RESET     "\x01"

public Plugin myinfo =
{
    name        = "DoD:S Set Winners",
    author      = "Root, Claude.ai guided by DNA.styx",
    description = "Sets winners in favour of the team with more tick points",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/DNA-styx/DoDS-Plugins"
};

ConVar  g_cvEnabled;
ConVar  g_cvTimelimit;
ConVar  g_cvFinishRoundSource;

Handle  g_hWinnersTimer;
int     g_iTeamPoints[4]; // indexed by team index (Team_Allies = 2, Team_Axis = 3)
int     g_iCountdown;
int     g_iPendingWinner;

public void OnPluginStart()
{
    CreateConVar("dod_setwinners_version", PLUGIN_VERSION,
        "DoD:S Set Winners version",
        FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    g_cvEnabled = CreateConVar("dod_setwinners_enabled", "1",
        "Enable setting winners by tick points at map end (1 = on, 0 = off)",
        FCVAR_NOTIFY,
        true, 0.0, true, 1.0);

    g_cvTimelimit         = FindConVar("mp_timelimit");
    g_cvFinishRoundSource = FindConVar("dod_finishround_source");

    if (g_cvTimelimit != null)
        g_cvTimelimit.AddChangeHook(OnTimeConVarChanged);

    HookEvent("dod_tick_points", Event_OnTickPoints,  EventHookMode_Post);
    HookEvent("dod_round_start", Event_OnRoundStart,  EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
    g_hWinnersTimer  = null;
    g_iCountdown     = 0;
    g_iPendingWinner = 0;
    g_iTeamPoints[Team_Allies] = 0;
    g_iTeamPoints[Team_Axis]   = 0;
    ArmWinnersTimer();
}

public void OnTimeConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    ArmWinnersTimer();
}

public void Event_OnTickPoints(Event event, const char[] name, bool dontBroadcast)
{
    int team  = event.GetInt("team");
    int score = event.GetInt("score");

    if (team == Team_Allies || team == Team_Axis)
        g_iTeamPoints[team] += score;
}

public void Event_OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_iTeamPoints[Team_Allies] = 0;
    g_iTeamPoints[Team_Axis]   = 0;
}

public Action Timer_SetWinners(Handle timer)
{
    g_hWinnersTimer = null;

    if (g_cvFinishRoundSource != null && g_cvFinishRoundSource.BoolValue)
        return Plugin_Stop;

    if (!g_cvEnabled.BoolValue)
        return Plugin_Stop;

    int winner = 0;

    if (g_iTeamPoints[Team_Allies] > g_iTeamPoints[Team_Axis])
        winner = Team_Allies;
    else if (g_iTeamPoints[Team_Axis] > g_iTeamPoints[Team_Allies])
        winner = Team_Axis;

    if (winner != 0)
    {
        g_iPendingWinner = winner;
        g_iCountdown     = 5;
        CenterTextToAll("Map ending in %d", g_iCountdown);
        CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }

    return Plugin_Stop;
}

public Action Timer_Countdown(Handle timer)
{
    g_iCountdown--;

    if (g_iCountdown <= 0)
    {
        GameRules_SetWinningTeam(g_iPendingWinner);

        char teamColor[16];
        char teamName[16];
        int loserPoints = (g_iPendingWinner == Team_Allies) ? g_iTeamPoints[Team_Axis] : g_iTeamPoints[Team_Allies];

        if (g_iPendingWinner == Team_Allies)
        {
            strcopy(teamColor, sizeof(teamColor), COLOR_ALLIES);
            strcopy(teamName,  sizeof(teamName),  "Allies");
        }
        else
        {
            strcopy(teamColor, sizeof(teamColor), COLOR_AXIS);
            strcopy(teamName,  sizeof(teamName),  "Axis");
        }

        PrintToChatAll("%s[Stalemate]%s %s%s%s won on points: %d vs. %d",
            COLOR_TAG, COLOR_RESET,
            teamColor, teamName, COLOR_RESET,
            g_iTeamPoints[g_iPendingWinner], loserPoints);

        g_iPendingWinner = 0;
        return Plugin_Stop;
    }

    CenterTextToAll("Map ending in %d", g_iCountdown);
    return Plugin_Continue;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

void CenterTextToAll(const char[] format, any...)
{
    char buffer[256];
    VFormat(buffer, sizeof(buffer), format, 2);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            PrintCenterText(i, "%s", buffer);
    }
}

void ArmWinnersTimer()
{
    if (g_hWinnersTimer != null)
    {
        KillTimer(g_hWinnersTimer);
        g_hWinnersTimer = null;
    }

    if (g_cvTimelimit == null)
        return;

    int timeLeft;
    if (!GetMapTimeLeft(timeLeft))
        timeLeft = g_cvTimelimit.IntValue * 60;

    float fireAt = float(timeLeft) - 5.0;

    if (fireAt <= 0.0)
        return;

    g_hWinnersTimer = CreateTimer(fireAt, Timer_SetWinners, _, TIMER_FLAG_NO_MAPCHANGE);
}