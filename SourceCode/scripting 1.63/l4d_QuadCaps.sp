#include <sourcemod>
#include <sdktools>
#include <l4d_lib>
#include <left4downtown>

//Left4Dead Version: v1037
#define PLUGIN_FILENAME		"l4d_QuadCaps"
#define DEBUG 0
#define ZC_TIMEROFFSET		0.8
#define TEAM_SPECTATORS		1
#define TEAM_SURVIVORS		2
#define TEAM_INFECTED		3
#define ZC_SMOKER		1
#define ZC_BOOMER		2
#define ZC_HUNTER		3
#define ZC_WITCH		4
#define ZC_TANK			5
#define TEAM_CLASS(%1)		(%1 == 1 ? "Smoker" : (%1 == 2 ? "Boomer" : (%1 == 3 ? "Hunter" :(%1 == 4 ? "Witch" : (%1 == 5 ? "Tank" : "None")))))
#define OnEnterGhostCheckDelay 0.2
#define KeepSITrackingCheckDelay 0.25
#define KEEPSICHECKDELAY 0.1

static bool:PluginDisable = false;
static bool:hasleftstartarea;
new Handle:HCVAR_Z_VS_SMOKER_LIMIT;
new Handle:HCVAR_Z_VS_BOOMER_LIMIT;
new Handle:HCVAR_Z_HUNTER_LIMIT;
new Handle:hCvar3HT1SProbability;
new CVAR_Z_VS_SMOKER_LIMIT_ORIGINAL = 1, CVAR_Z_VS_BOOMER_LIMIT_ORIGINAL = 1, CVAR_Z_HUNTER_LIMIT = 2, Cvar3HT1SProbability;
static Hunter_Starting_Line,Smoker_Starting_Line,Boomer_Starting_Line;
new Handle:g_hSetClass		= INVALID_HANDLE;
new Handle:g_hCreateAbility	= INVALID_HANDLE;
new g_oAbility			= 0;
native IsInReady();
native Is_Ready_Plugin_On();

public Plugin:myinfo = 
{
	name = "L4D Quad Caps Control",
	author = "Harry Potter",
	description = "9",
	version = "1.2",
	url = "https://steamcommunity.com/id/fbef0102/"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("Keep_SI_Starting", Native_KeepSIStarting);
	return APLRes_Success;
}

public Native_KeepSIStarting(Handle:plugin, numParams)
{
	CreateTimer(KEEPSICHECKDELAY,KeepSIStarting,_); // delay check
}

public OnPluginStart()
{
	Sub_HookGameData(PLUGIN_FILENAME);
	
	decl String:sGame[256];
	GetGameFolderName(sGame, sizeof(sGame));
	if (!StrEqual(sGame, "left4dead", false))
	{
		SetFailState("Plugin 'Quad Control' supports Left 4 Dead 1 only!");
	}
	
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("mission_lost", Event_RoundEnd);
	HookEvent("finale_win", Event_RoundEnd);
	HookEvent("player_death", Event_PlayerDeath,	EventHookMode_PostNoCopy);
	HookEvent("player_left_start_area", LeftStartAreaEvent, EventHookMode_PostNoCopy);
	
	HCVAR_Z_VS_SMOKER_LIMIT = FindConVar("z_versus_smoker_limit");
	HCVAR_Z_VS_BOOMER_LIMIT = FindConVar("z_versus_boomer_limit");
	HCVAR_Z_HUNTER_LIMIT = FindConVar("z_hunter_limit");
	hCvar3HT1SProbability = CreateConVar("sm_3ht1s_percent_chance", "90", "X% chance of 3+1 and 100-X% remaining chance of 4ht after Boomer dies", FCVAR_PLUGIN, true, 0.0,true, 100.0);
	
	CVAR_Z_VS_SMOKER_LIMIT_ORIGINAL = GetConVarInt(HCVAR_Z_VS_SMOKER_LIMIT);
	CVAR_Z_VS_BOOMER_LIMIT_ORIGINAL = GetConVarInt(HCVAR_Z_VS_BOOMER_LIMIT);
	CVAR_Z_HUNTER_LIMIT = GetConVarInt(HCVAR_Z_HUNTER_LIMIT);
	Cvar3HT1SProbability = GetConVarInt(hCvar3HT1SProbability);
	
	HookConVarChange(hCvar3HT1SProbability, ConVarChange_hCvar3HT1SProbability);
	
	AutoExecConfig(true, "l4d_QuadCpas");
	
	PluginDisable = false;
}

public OnConfigsExecuted()
{
	CVAR_Z_VS_SMOKER_LIMIT_ORIGINAL = GetConVarInt(HCVAR_Z_VS_SMOKER_LIMIT);
	CVAR_Z_VS_BOOMER_LIMIT_ORIGINAL = GetConVarInt(HCVAR_Z_VS_BOOMER_LIMIT);
	CVAR_Z_HUNTER_LIMIT = GetConVarInt(HCVAR_Z_HUNTER_LIMIT);
	
	if(CVAR_Z_VS_BOOMER_LIMIT_ORIGINAL == 0  && CVAR_Z_VS_SMOKER_LIMIT_ORIGINAL == 0) 
	{
		//LogMessage("detect \"Hunters Only\" mode, disable Quad Caps");
		PluginDisable = true;
	}
	else if(CVAR_Z_VS_BOOMER_LIMIT_ORIGINAL == 0)
	{
		//LogMessage("detect \"No Boomer\" mode, disable Quad Caps");
		PluginDisable = true;
	}
	else if(CVAR_Z_HUNTER_LIMIT < 2)
	{
		//LogMessage("detect \"z_hunter_limit < 2\", disable Quad Caps");
		PluginDisable = true;
	}
}

public OnPluginEnd()
{
	ResetConVar(HCVAR_Z_VS_SMOKER_LIMIT, true, true);
	ResetConVar(HCVAR_Z_VS_BOOMER_LIMIT, true, true);
	SetConvarDefault();
	PluginDisable = false;
}

public OnMapEnd()
{
	ResetConVar(HCVAR_Z_VS_SMOKER_LIMIT, true, true);
	ResetConVar(HCVAR_Z_VS_BOOMER_LIMIT, true, true);
	SetConvarDefault();
	PluginDisable = false;
}

public Sub_HookGameData(String:GameDataFile[])
{
	new Handle:g_hGameConf = LoadGameConfigFile(GameDataFile);

	if (g_hGameConf != INVALID_HANDLE)
	{
		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Signature, "SetClass");
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		g_hSetClass = EndPrepSDKCall();

		if (g_hSetClass == INVALID_HANDLE)
			SetFailState("Error: Unable to find SetClass signature.");

		StartPrepSDKCall(SDKCall_Static);
		PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Signature, "CreateAbility");
		PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
		g_hCreateAbility = EndPrepSDKCall();

		if (g_hCreateAbility == INVALID_HANDLE)
			SetFailState("Error: Unable to find CreateAbility signature.");

		g_oAbility = GameConfGetOffset(g_hGameConf, "oAbility");

		CloseHandle(g_hGameConf);
	}

	else
		SetFailState("Error: Unable to load gamedata file, exiting.");
}

public Action:Event_RoundStart(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
	Sub_DebugPrint("round start event");
	hasleftstartarea = false;
}

public Action:Event_RoundEnd(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
	Sub_DebugPrint("round end event");
	SetConvarDefault();
}

public LeftStartAreaEvent(Handle:event, String:name[], bool:dontBroadcast)
{
	if(!Is_Ready_Plugin_On())
	{
		CreateTimer(KEEPSICHECKDELAY,KeepSIStarting,_); // delay check
		hasleftstartarea = true;
	}
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(IsInReady()||IsPluginDisable()) return ;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!IsClientAndInGame(client)) return;
	
	if(GetClientTeam(client) == TEAM_INFECTED)
	{
		if(GetZombieClass(client) == ZC_BOOMER)
		{
			new random = GetRandomInt(1, 100)
			if (random <=Cvar3HT1SProbability)
			{
				SetConVarInt(HCVAR_Z_VS_SMOKER_LIMIT, 1);
				SetConVarInt(HCVAR_Z_VS_BOOMER_LIMIT, 0);
				Sub_DebugPrint("No Boomer");
			}
			else
			{
				SetConVarInt(HCVAR_Z_VS_BOOMER_LIMIT, 0);
				SetConVarInt(HCVAR_Z_VS_SMOKER_LIMIT, 0);
				Sub_DebugPrint("No Boomer and Smoker");
			}
		}
		else
		{
			if(GetConVarInt(HCVAR_Z_VS_BOOMER_LIMIT) == 0)
			{
				SetConvarDefault();
				Sub_DebugPrint("Boomer and Smoker limit reset");
			}
		}	
	}
}

public L4D_OnEnterGhostState(client)
{
	if(!InSecondHalfOfRound())
	{
		Sub_DebugPrint("Round 1");
		return;
	}
	Sub_DebugPrint("%N: OnEnterGhostState %s",client,TEAM_CLASS(GetEntProp(client, Prop_Send, "m_zombieClass")));
	
	CreateTimer(OnEnterGhostCheckDelay,COLD_DOWN,client); // delay check since team change event is before round start event
}

public Action:COLD_DOWN(Handle:timer,any:client)
{
	if(!IsClientAndInGame(client)||GetClientTeam(client)!=3)	return;
	
	if(!Is_Ready_Plugin_On()&&!hasleftstartarea)
	{
		Sub_DebugPrint("Is in saferoom");
		Sub_DetermineClass(client, GetEntProp(client, Prop_Send, "m_zombieClass"));
		return;
	}
	if(IsInReady())
	{
		Sub_DebugPrint("Is in Ready");
		Sub_DetermineClass(client, GetEntProp(client, Prop_Send, "m_zombieClass"));
		return;
	}
}

public Sub_DetermineClass(any:Client, any:ZClass)
{
	if(IsPlayerGhost(Client))
	{
		decl zombieclass;
		new Hunter_Now_Line = 0, Smoker_Now_Line = 0, Boomer_Now_Line = 0, NeedChange = 0;
		for(new i=1; i <= MaxClients; i++)
		{
			if(IsClientAndInGame(i) && IsInfected(i) && !IsFakeClient(i))
			{
				zombieclass = GetEntProp(i, Prop_Send, "m_zombieClass");
				switch(zombieclass)
				{
					case ZC_SMOKER:  
					{
						Smoker_Now_Line++;
					}
					case ZC_BOOMER:  
					{
						Boomer_Now_Line++;
					}
					case ZC_HUNTER:  
					{
						Hunter_Now_Line++;
					}			
				}
			}
		}

		zombieclass = GetEntProp(Client, Prop_Send, "m_zombieClass");
		if(Smoker_Now_Line<Smoker_Starting_Line)
		{
			if(zombieclass != ZC_SMOKER)
				NeedChange = ZC_SMOKER;
		}
		else if (Boomer_Now_Line<Boomer_Starting_Line)
		{
			if(zombieclass != ZC_BOOMER)
				NeedChange = ZC_BOOMER;
		}
		else if (Hunter_Now_Line<Hunter_Starting_Line)
		{
			if(zombieclass != ZC_HUNTER)
				NeedChange = ZC_HUNTER;
		}
		
		if(NeedChange > 0)
		{
			decl WeaponIndex;
			while ((WeaponIndex = GetPlayerWeaponSlot(Client, 0)) != -1)
			{
				RemovePlayerItem(Client, WeaponIndex);
				RemoveEdict(WeaponIndex);
			}
			SDKCall(g_hSetClass, Client, NeedChange);
			AcceptEntityInput(MakeCompatEntRef(GetEntProp(Client, Prop_Send, "m_customAbility")), "Kill");
			SetEntProp(Client, Prop_Send, "m_customAbility", GetEntData(SDKCall(g_hCreateAbility, Client), g_oAbility));
			Sub_DebugPrint("H: %d, S:%d, B:%d, %N has changed to %s",Hunter_Now_Line,Smoker_Now_Line,Boomer_Now_Line,Client,TEAM_CLASS(GetEntProp(Client, Prop_Send, "m_zombieClass")));
		}
	}
	return;
}

public Action:KeepSIStarting(Handle:timer,any:client)
{
	Sub_DebugPrint("Keep it");
	Hunter_Starting_Line = Smoker_Starting_Line = Boomer_Starting_Line = 0;
	new zombieclass;
	for(new i=1; i <= MaxClients; i++)
	{
		if(IsClientAndInGame(i) && IsInfected(i) && !IsFakeClient(i))
		{
			zombieclass = GetEntProp(i, Prop_Send, "m_zombieClass")
			switch(zombieclass)
			{
				case ZC_SMOKER:  
				{
					Smoker_Starting_Line++;
				}
				case ZC_BOOMER:  
				{
					Boomer_Starting_Line++;
				}
				case ZC_HUNTER:  
				{
					Hunter_Starting_Line++;
				}			
			}
		}
	}
	Sub_DebugPrint("H: %d, S: %d, B: %d",Hunter_Starting_Line,Smoker_Starting_Line,Boomer_Starting_Line);
	if(Smoker_Starting_Line + Boomer_Starting_Line + Hunter_Starting_Line > GetConVarInt(FindConVar("z_max_player_zombies")))	
	{
		Sub_DebugPrint("Error! infected players more than z_max_player_zombies");
		CreateTimer(KeepSITrackingCheckDelay,KeepSIStarting,_); // keep checking
	}
}

public ConVarChange_hCvar3HT1SProbability(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!StrEqual(oldValue, newValue))
	{
		Cvar3HT1SProbability = GetConVarInt(hCvar3HT1SProbability);
		LogMessage("If Boomer dies last -> %d%% 3+1, %d%% 4ht",Cvar3HT1SProbability,100-Cvar3HT1SProbability)
	}
}

public Sub_DebugPrint(const String:Message[], any:...)
{
	#if DEBUG
		decl String:DebugBuff[128];
		VFormat(DebugBuff, sizeof(DebugBuff), Message, 2);
		PrintToChatAll("%s",DebugBuff);
	#endif
}

stock GetZombieClass(client) return GetEntProp(client, Prop_Send, "m_zombieClass");

SetConvarDefault()
{
	SetConVarInt(HCVAR_Z_VS_SMOKER_LIMIT, CVAR_Z_VS_SMOKER_LIMIT_ORIGINAL);
	SetConVarInt(HCVAR_Z_VS_BOOMER_LIMIT, CVAR_Z_VS_BOOMER_LIMIT_ORIGINAL);
}

bool:InSecondHalfOfRound()
{
	return GameRules_GetProp("m_bInSecondHalfOfRound");
}

bool:IsPluginDisable()
{
	return PluginDisable;
}