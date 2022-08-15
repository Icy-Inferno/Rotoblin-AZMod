#pragma semicolon 1

#include <sourcemod>
#include <left4dhooks>
#include <multicolors>

#define MAX(%0,%1) (((%0) > (%1)) ? (%0) : (%1))

new Handle:g_hVsBossBuffer;
new SurCurrent = 0;
native Is_Ready_Plugin_On();

public Plugin:myinfo =
{
    name = "L4D1 Survivor Progress",
    author = "CanadaRox, Visor, L4D1 port by harry",
    description = "Print survivor progress in flow percents ",
    version = "2.3",
    url = "https://github.com/Attano/ProMod"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("GetSurCurrent",Native_SurCurrent);
	CreateNative("GetSurCurrentFloat",Native_SurCurrentFloat);
	return APLRes_Success;
}

public Native_SurCurrentFloat(Handle:plugin, numParams) {
	return _:GetBossProximity();
}
public Native_SurCurrent(Handle:plugin, numParams) {
	SurCurrent = RoundToNearest(GetBossProximity() * 100.0);
	return SurCurrent;
}


public OnPluginStart()
{
	LoadTranslations("Roto2-AZ_mod.phrases");
	g_hVsBossBuffer = FindConVar("versus_boss_buffer");

	RegConsoleCmd("sm_cur", CurrentCmd);
	RegConsoleCmd("sm_current", CurrentCmd);
	HookEvent("round_start", RoundStartEvent, EventHookMode_PostNoCopy);
	HookEvent("player_left_start_area", LeftStartAreaEvent, EventHookMode_PostNoCopy);
}
public RoundStartEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
	CreateTimer(5.0, SaveSurCurrent);
}

public Action:SaveSurCurrent(Handle:timer)
{
	SurCurrent = RoundToNearest(GetBossProximity() * 100.0);
}

public LeftStartAreaEvent(Handle:event, String:name[], bool:dontBroadcast)
{
	if(!Is_Ready_Plugin_On())
		CPrintToChatAll("{default}[{olive}TS{default}] %t","l4d_current_survivor_progress", SurCurrent);
}

public Action:CurrentCmd(client, args)
{
	SurCurrent = RoundToNearest(GetBossProximity() * 100.0);
	SurCurrent = SurCurrent>=100 ? 100 : SurCurrent;
	CPrintToChat(client, "{default}[{olive}TS{default}] %T","l4d_current_survivor_progress",client, SurCurrent);
	
}

stock Float:GetBossProximity()
{
	new Float:proximity = GetMaxSurvivorCompletion();
	return proximity;
}

stock Float:GetMaxSurvivorCompletion()
{
	new Float:flow = 0.0;
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			flow = MAX(flow, L4D2Direct_GetFlowDistance(i));
		}
	}
	return (flow / L4D2Direct_GetMapMaxFlowDistance());
}