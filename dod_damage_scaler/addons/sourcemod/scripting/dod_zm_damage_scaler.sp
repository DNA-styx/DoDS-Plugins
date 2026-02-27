#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define PLUGIN_VERSION "1.5"

ConVar g_cvDamageScale;
ConVar g_cvDebug;

bool g_bHooked[2048];

static const char g_BreakableClasses[][] =
{
    "func_breakable",
    "prop_physics",
    "prop_physics_multiplayer",
    "prop_physics_override"
};

public Plugin myinfo =
{
    name        = "Entity Damage Scaler",
    author      = "claude.ai guided by DNA.styx",
    description = "Scales damage on breakable/physics entities",
    version     = PLUGIN_VERSION
};

public void OnPluginStart()
{
    g_cvDamageScale = CreateConVar(
        "sm_entity_damage_scale",
        "0.1",
        "Damage multiplier applied to hooked entities. 0.1 = 10% of original damage.",
        FCVAR_NOTIFY,
        true, 0.01,
        true, 1.0
    );

    g_cvDebug = CreateConVar(
        "sm_entity_damage_scale_debug",
        "0",
        "Set to 1 to print damage debug info to chat and log.",
        FCVAR_NOTIFY
    );

    HookAllBreakables();
}

public void OnMapStart()
{
    for (int i = 0; i < sizeof(g_bHooked); i++)
        g_bHooked[i] = false;

    HookAllBreakables();

    CreateTimer(0.5, Timer_LateHook, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_LateHook(Handle timer)
{
    HookAllBreakables();
    return Plugin_Stop;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!IsValidEntity(entity))
        return;

    if (IsBreakableClass(classname))
        TryHookEntity(entity);
}

public void OnEntityDestroyed(int entity)
{
    if (entity > 0 && entity < sizeof(g_bHooked))
        g_bHooked[entity] = false;
}

bool IsBreakableClass(const char[] classname)
{
    for (int i = 0; i < sizeof(g_BreakableClasses); i++)
    {
        if (StrEqual(classname, g_BreakableClasses[i], false))
            return true;
    }
    return false;
}

void TryHookEntity(int entity)
{
    if (entity <= 0 || entity >= sizeof(g_bHooked))
        return;

    // Bail out completely if already hooked — do not SDKUnhook/SDKHook again.
    // Re-hooking on prop_physics_override -> prop_physics conversion causes
    // duplicate hooks even after an SDKUnhook, resulting in double damage scaling.
    if (g_bHooked[entity])
        return;

    SDKHook(entity, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
    g_bHooked[entity] = true;

    if (g_cvDebug.BoolValue)
    {
        char classname[64];
        GetEntityClassname(entity, classname, sizeof(classname));
        LogMessage("[DmgScaler] Hooked ent %d (%s)", entity, classname);
    }
}

void FixTakeDamage(int entity)
{
    if (!HasEntProp(entity, Prop_Data, "m_takedamage") ||
        !HasEntProp(entity, Prop_Data, "m_iHealth"))
        return;

    int health     = GetEntProp(entity, Prop_Data, "m_iHealth");
    int takeDamage = GetEntProp(entity, Prop_Data, "m_takedamage");

    // Entities Stripper gave health to may still have m_takedamage = 0 (DAMAGE_NO),
    // meaning the engine ignores all damage. Force DAMAGE_YES.
    if (health > 0 && takeDamage == 0)
    {
        SetEntProp(entity, Prop_Data, "m_takedamage", 2);

        if (g_cvDebug.BoolValue)
        {
            char classname[64];
            GetEntityClassname(entity, classname, sizeof(classname));
            LogMessage("[DmgScaler] Fixed m_takedamage on ent %d (%s) HP:%d", entity, classname, health);
        }
    }
}

void HookAllBreakables()
{
    // prop_physics excluded — on this map they originate as prop_physics_override
    // and are caught via OnEntityCreated. Including prop_physics here would cause
    // double hooks on converted entities.
    static const char classes[][] =
    {
        "func_breakable",
        "prop_physics_override"
    };

    int total = 0;

    for (int i = 0; i < sizeof(classes); i++)
    {
        int entity = -1;
        while ((entity = FindEntityByClassname(entity, classes[i])) != -1)
        {
            if (!IsValidEntity(entity))
                continue;

            TryHookEntity(entity);
            FixTakeDamage(entity);
            total++;
        }
    }

    LogMessage("[DmgScaler] HookAllBreakables — processed %d entities", total);
}

public Action Hook_OnTakeDamage(int entity, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!IsValidEntity(entity))
        return Plugin_Continue;

    if (damage <= 0.0)
        return Plugin_Continue;

    float originalDamage = damage;
    damage *= g_cvDamageScale.FloatValue;

    if (damage < 1.0)
        damage = 1.0;

    if (g_cvDebug.BoolValue)
    {
        int healthBefore = 0;
        if (HasEntProp(entity, Prop_Send, "m_iHealth"))
            healthBefore = GetEntProp(entity, Prop_Send, "m_iHealth");
        else if (HasEntProp(entity, Prop_Data, "m_iHealth"))
            healthBefore = GetEntProp(entity, Prop_Data, "m_iHealth");

        int healthAfter = healthBefore - RoundToNearest(damage);

        char classname[64];
        GetEntityClassname(entity, classname, sizeof(classname));

        char msg[256];
        FormatEx(msg, sizeof(msg),
            "[DmgScaler] Ent %d (%s) | HP: %d | Dmg In: %.1f | Dmg Out: %.1f | HP After: ~%d",
            entity, classname, healthBefore, originalDamage, damage, healthAfter
        );

        PrintToChatAll("%s", msg);
        LogMessage("%s", msg);
    }

    return Plugin_Changed;
}