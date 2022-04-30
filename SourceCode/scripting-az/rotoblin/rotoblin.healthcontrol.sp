/*
 * ============================================================================
 *
 *  Rotoblin
 *
 *  File:			rotoblin.healthcontrol.sp
 *  Type:			Module
 *  Description:	Removes/replaces health items depending on settings
 *
 *  Copyright (C) 2010  Mr. Zero <mrzerodk@gmail.com>
 *  Copyright (C) 2017-2022 Harry <fbef0102@gmail.com>
 *  This file is part of Rotoblin.
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * ============================================================================
 */

// --------------------
//       Public
// --------------------

// This used to pertain solely to replacing kits, but it now pertains to health kits and pills
enum HEALTH_STYLE
{
	REPLACE_NO_KITS = 0, // Don't replace any medkits with pills
	REPLACE_ALL_KITS = 1, // Replace all medkits with pills
	REPLACE_ALL_BUT_FINALE_KITS = 2, // Replace all medkits besides finale medkits
	SAFEROOM_AND_FINALE_PILLS_ONLY = 3, // Replace the saferoom and finale kits with pills and remove all other pills/kits
	ZONEMOD_PILLS = 4 // Replace all medkits with pills, only remove saferoom kits
}
// --------------------
//       Private
// --------------------

static	const	String:	CONVERT_PILLS_CVAR[]			= "director_convert_pills";
static	const	String:	CONVERT_PILLS_VS_CVAR[]		= "director_vs_convert_pills"; // setting this var to 0 will convert no pills to health kits

static	const	String:	FIRST_AID_KIT_CLASSNAME[]		= "weapon_first_aid_kit_spawn";
static	const	String:	PAIN_PILLS_CLASSNAME[]			= "weapon_pain_pills_spawn";
static	const	String:	MODEL_PAIN_PILLS[]				= "w_models/weapons/w_eq_painpills.mdl";
static 	const 	String: MODEL_FIRST_AID_KIT[]			= "w_models/weapons/w_eq_medkit.mdl";

static	const	Float:	REPLACE_DELAY					= 0.1; // Short delay on OnEntityCreated before replacing

static			bool:	g_bIsFinale						= false;
static			bool:	g_bHaveRunRoundStart			= false;

static HEALTH_STYLE: g_iHealthStyle					= REPLACE_ALL_KITS; // How we replace kits
static			Handle:	g_hHealthStyle_Cvar			= INVALID_HANDLE;

static					g_iDebugChannel					= 0;
static	const	String:	DEBUG_CHANNEL_NAME[]		= "HealthControl";


static Float:SurvivorStart[3];
static g_iPlayerSpawn, g_iRoundStart;
static bool g_bIsRound1Over;

// Item lists for tracking/decoding/etc
enum ItemList {
	IL_PainPills,
};

// Names for cvars, kv, descriptions
// [ItemIndex][shortname=0,fullname=1,spawnname=2]
enum ItemNames {	
	IN_shortname,	
	IN_longname, 	
	IN_officialname, 	
	IN_modelname 
};

static const String:g_sItemNames[view_as<int>(ItemList)][view_as<int>(ItemNames)][] =
{
	{ "pills", "pain pills", "pain_pills", "painpills" },
};

// For spawn entires adt_array
enum ItemTracking {
	IT_entity,
	Float:IT_origins,
	Float:IT_origins1,
	Float:IT_origins2,
	Float:IT_angles,
	Float:IT_angles1,
	Float:IT_angles2
};

// ADT Array Handle for actual item spawns
static Handle:g_hItemSpawns[view_as<int>(ItemList)];
static KeyValues g_hMIData = null;

// **********************************************
//                   Forwards
// **********************************************

/**
 * Plugin is starting.
 *
 * @noreturn
 */

public _HealthControl_OnPluginStart()
{
	HookPublicEvent(EVENT_ONPLUGINENABLE, _HC_OnPluginEnable);
	HookPublicEvent(EVENT_ONPLUGINDISABLE, _HC_OnPluginDisable);

	decl String:buffer[10];
	IntToString(view_as<int>(g_iHealthStyle), buffer, sizeof(buffer)); // Get default value for replacement style
	g_hHealthStyle_Cvar = CreateConVarEx("health_style", 
		buffer, 
		"How medkits and pills will be configured. 0 - Don't replace any medkits, 1 - Replace all medkits with pills, 2 - Replace all but finale medkits with pills, 3 - Replace safe room and finale kits with pills; remove all other health sources", 
		FCVAR_NOTIFY);

	if (g_hHealthStyle_Cvar == INVALID_HANDLE) 
	{
		ThrowError("Unable to create health style cvar!");
	}
	
	AddConVarToReport(g_hHealthStyle_Cvar); // Add to report status module
	UpdateHealthStyle();

	g_iDebugChannel = DebugAddChannel(DEBUG_CHANNEL_NAME);
	DebugPrintToAllEx("Module is now setup");

	// Create item spawns array;
	for (new i = 0; i < _:ItemList; i++)
	{
		g_hItemSpawns[i] = CreateArray(_:ItemTracking); 
	}

	MI_KV_Load();
}

/**
 * Plugin is now enabled.
 *
 * @noreturn
 */
public _HC_OnPluginEnable()
{
	if (g_iHealthStyle == REPLACE_NO_KITS) // If we do not want to replace any medkits
	{
		ResetConVar(FindConVar(CONVERT_PILLS_CVAR)); // Reset medkit conversion of pain pills cvar
		ResetConVar(FindConVar(CONVERT_PILLS_VS_CVAR));
	}
	else
	{
		SetConVarFloat(FindConVar(CONVERT_PILLS_CVAR), 0.0); // Otherwise set it 0 to disable director from spawning medkits
		SetConVarFloat(FindConVar(CONVERT_PILLS_VS_CVAR), 0.0);
	}

	HookEvent("round_start", _HC_RoundStart_Event, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", _HC_PlayerSpawn_Event,	EventHookMode_PostNoCopy);
	HookEvent("player_left_start_area", _HC_player_left_start_area, EventHookMode_PostNoCopy);
	HookEvent("round_end", _HC_RoundEnd_Event, EventHookMode_PostNoCopy);
	HookPublicEvent(EVENT_ONMAPSTART, _HC_OnMapStart);
	HookPublicEvent(EVENT_ONMAPEND, _HC_OnMapEnd);

	UpdateHealthStyle();
	HookConVarChange(g_hHealthStyle_Cvar, _HC_HealthStyle_CvarChange);
	DebugPrintToAllEx("Module is now loaded");
}

/**
 * Plugin is now disabled.
 *
 * @noreturn
 */
public _HC_OnPluginDisable()
{
	ResetPlugin();
	ResetConVar(FindConVar(CONVERT_PILLS_CVAR));
	ResetConVar(FindConVar(CONVERT_PILLS_VS_CVAR));

	UnhookEvent("round_start", _HC_RoundStart_Event, EventHookMode_Post);
	UnhookEvent("player_spawn", _HC_PlayerSpawn_Event,	EventHookMode_PostNoCopy);
	UnhookEvent("player_left_start_area", _HC_player_left_start_area, EventHookMode_PostNoCopy);
	UnhookEvent("round_end", _HC_RoundEnd_Event, EventHookMode_PostNoCopy);
	UnhookPublicEvent(EVENT_ONMAPSTART, _HC_OnMapStart);
	UnhookPublicEvent(EVENT_ONMAPEND, _HC_OnMapEnd);
	UnhookPublicEvent(EVENT_ONENTITYCREATED, _HC_OnEntityCreated);
	UnhookConVarChange(g_hHealthStyle_Cvar, _HC_HealthStyle_CvarChange);

	DebugPrintToAllEx("Module is now unloaded");

	MI_KV_Close();
}

char g_sCurMap[64];
public _HC_OnMapStart()
{
	g_bIsRound1Over = false;
	for (new i = 0; i < _:ItemList; i++)
	{
		ClearArray(g_hItemSpawns[i]);
	}

	GetCurrentMap(g_sCurMap, 64);
	MI_KV_Close();
	MI_KV_Load();
	if (!KvJumpToKey(g_hMIData, g_sCurMap)) {
		//LogError("[MI] MapInfo for %s is missing.", g_sCurMap);
	}
	KvRewind(g_hMIData);
}

public _HC_OnMapEnd()
{
	ResetPlugin();
	g_bHaveRunRoundStart = false;
	UnhookPublicEvent(EVENT_ONENTITYCREATED, _HC_OnEntityCreated);
	DebugPrintToAllEx("Map is ending, unhook OnEntityCreated");
	KvRewind(g_hMIData);
}

public _HC_HealthStyle_CvarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	DebugPrintToAllEx("Health style cvar was changed, update style var. Old value %s, new value %s", oldValue, newValue);
	UpdateHealthStyle();
}

public _HC_player_left_start_area(Handle:event, const String:name[], bool:dontBroadcast)
{
	new Handle:cvarEnforceReady = FindConVar("l4d_ready_enabled");
	if(cvarEnforceReady != INVALID_HANDLE)
	{
		if(GetConVarInt(cvarEnforceReady) == 1)
		{
			return;
		}
	}
	
	if(g_iHealthStyle == SAFEROOM_AND_FINALE_PILLS_ONLY||g_iHealthStyle == ZONEMOD_PILLS)
	{				
		// Finally: Now we either have 0 (standard) or 4 (finale) sets of pills remaining.
		// Give the survivors the pills that we've removed from the saferoom.
			GivePillsToSurvivors();
	}
}

public Native_GiveSurAllPills(Handle:plugin, numParams)
{
	if(g_iHealthStyle == SAFEROOM_AND_FINALE_PILLS_ONLY||g_iHealthStyle == ZONEMOD_PILLS)
	{				
		// Finally: Now we either have 0 (standard) or 4 (finale) sets of pills remaining.
		// Give the survivors the pills that we've removed from the saferoom.
			GivePillsToSurvivors();
	}
}

public _HC_PlayerSpawn_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	if( g_iPlayerSpawn == 0 && g_iRoundStart == 1) 
	{
		DetermineIfMapIsFinale();
		CreateTimer(0.25, TimerStart, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	g_iPlayerSpawn = 1;
}

public _HC_RoundStart_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	
	if( g_iPlayerSpawn == 1 && g_iRoundStart == 0)
	{
		DetermineIfMapIsFinale();
		CreateTimer(0.25, TimerStart, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	g_iRoundStart = 1;
}

static Action:TimerStart(Handle:timer)
{
	ResetPlugin();
	if (g_iHealthStyle == REPLACE_NO_KITS)
	{
		DebugPrintToAllEx("Round start - Will not replace medkits");
		return; // Not replacing any medkits, return
	}
	
	//LogMessage("Round start - Running health control - Final map: %d", g_bIsFinale);

	if(g_iHealthStyle == ZONEMOD_PILLS)
	{
		if(!g_bIsRound1Over)
		{
			// Round1
			EnumAndElimPillSpawns();
		}
		else
		{
			// Round2
			GenerateStoredPillSpawns();
		}
	}

	UpdateStartingHealthItems();
	UnhookPublicEvent(EVENT_ONENTITYCREATED, _HC_OnEntityCreated);
	HookPublicEvent(EVENT_ONENTITYCREATED, _HC_OnEntityCreated);
	g_bHaveRunRoundStart = true;
}

public _HC_RoundEnd_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	ResetPlugin();
	g_bHaveRunRoundStart = false;
	UnhookPublicEvent(EVENT_ONENTITYCREATED, _HC_OnEntityCreated);
	DebugPrintToAllEx("Round end");
	g_bIsRound1Over = true;
}

/**
 * When an entity is created.
 *
 * @param entity		Entity index.
 * @param classname		Classname.
 * @noreturn
 */
public _HC_OnEntityCreated(entity, const String:classname[])
{
	if(g_bHaveRunRoundStart == false) return;
		
	if (( g_iHealthStyle == SAFEROOM_AND_FINALE_PILLS_ONLY)&& 
		StrEqual(classname, PAIN_PILLS_CLASSNAME))
	{						
		new entRef = EntIndexToEntRef(entity);
		CreateTimer(REPLACE_DELAY, _HC_RemoveItem_Delayed_Timer, entRef);
	} 	
	/*else if(( g_iHealthStyle == ZONEMOD_PILLS)&& 
		StrEqual(classname, PAIN_PILLS_CLASSNAME) && g_bIsFinale)
	{
		int random = GetRandomInt(1,100);
		new entRef = EntIndexToEntRef(entity);
		CreateTimer(REPLACE_DELAY, _HC_RemoveItem_Delayed_Timer, entRef);
	}*/
	else if(StrEqual(classname, FIRST_AID_KIT_CLASSNAME) && ShouldReplaceKitWithPills()) 
	{		
		new entRef = EntIndexToEntRef(entity);
		CreateTimer(REPLACE_DELAY, _HC_ReplaceKit_Delayed_Timer, entRef); // Replace medkit
		DebugPrintToAllEx("Late spawned medkit, timer created. Entity %i", entity);
	}
}

public Action:_HC_RemoveItem_Delayed_Timer(Handle:timer, any:entRef)
{
	new entity = EntRefToEntIndex(entRef);	
	if (entity == INVALID_ENT_REFERENCE)
		return;
	
	//decl Float:entityPos[3];
	//GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entityPos);	
	//LogMessage("KITS here4 %d: %f %f %f",entity,entityPos[0],entityPos[1],entityPos[2]);
	SafelyRemoveEdict(entity);
	DebugPrintToAllEx("Removed item");
}

/**
 * Called when the replace kit timer interval has elapsed.
 * 
 * @param timer			Handle to the timer object.
 * @param medkitEntRef	Entity reference to the medkit to be removed
 * @noreturn
 */
public Action:_HC_ReplaceKit_Delayed_Timer(Handle:timer, any:medkitEntRef)
{
	new entity = EntRefToEntIndex(medkitEntRef);
	if (entity == INVALID_ENT_REFERENCE)
	{
		return;
	}
	
	ReplaceKitWithPills(entity);	
}

// **********************************************
//                 Public API
// **********************************************

/**
 * Return current health style.
 *
 * @return				Health style.
 */
stock HEALTH_STYLE:GetHealthStyle()
{
	return g_iHealthStyle;
}

// **********************************************
//                 Private API
// **********************************************

/**
 * Updates the global health style variable with the cvar.
 *
 * @noreturn
 */
static UpdateHealthStyle()
{
	g_iHealthStyle = view_as<HEALTH_STYLE>(GetConVarInt(g_hHealthStyle_Cvar));
	DebugPrintToAllEx("Updated global style variable; %i", GetConVarInt(g_hHealthStyle_Cvar));
}

/**
 * Replaces or removes items present at the start of the round.  Logic run is based on the chosen health style.
 * 
 */
static UpdateStartingHealthItems()
{	
	new entity = -1;
	/*
	//尋找地圖中的藥丸與治療包
	while ( ((entity = FindEntityByClassnameEx(entity, PAIN_PILLS_CLASSNAME)) != -1) )
	{
		if(!IsValidEntity(entity))
			continue;
			
		decl Float:entityPos[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entityPos);	
		LogMessage("PILLS here1 %d: %f %f %f",entity,entityPos[0],entityPos[1],entityPos[2]);	
	}
	entity = -1;
	while ( ((entity = FindEntityByClassnameEx(entity, FIRST_AID_KIT_CLASSNAME)) != -1) )
	{
		if(!IsValidEntity(entity))
			continue;
			
		decl Float:entityPos[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entityPos);	
		LogMessage("KITS here1 %d: %f %f %f",entity,entityPos[0],entityPos[1],entityPos[2]);	
	}
	*/
	
	decl SaferoomKits[4];
	DebugPrintToAllEx("Updating starting health items.");
	if (g_iHealthStyle == ZONEMOD_PILLS||g_iHealthStyle == SAFEROOM_AND_FINALE_PILLS_ONLY)//only remove saferoom medkits
	{
		//find where the survivors start so we know which medkits to replace,
		FindSurvivorStart();
		//and remove the medkits
		RemoveMedkits(SaferoomKits);
	}
	
	if(g_iHealthStyle == REPLACE_ALL_BUT_FINALE_KITS || g_iHealthStyle == REPLACE_ALL_KITS) 
	{
		FindSurvivorStart();
		ReplaceSafeRoomMedkits(SaferoomKits);
	}
	
	new k =0;
	entity = -1;
	new pillsleft = GetConVarInt(FindConVar("survivor_limit"));
	if(g_bIsFinale)//救援關四顆藥丸符合當前人類數量
	{
		if(g_iHealthStyle == SAFEROOM_AND_FINALE_PILLS_ONLY /*|| g_iHealthStyle == ZONEMOD_PILLS*/)
			RemoveAllPills();

		while ((entity = FindEntityByClassnameEx(entity, FIRST_AID_KIT_CLASSNAME)) != -1)
		{
			if(!IsValidEntity(entity) || !IsValidEdict(entity))
				continue;	
			
			if(!(entity==SaferoomKits[0]||entity==SaferoomKits[1]||entity==SaferoomKits[2]||entity==SaferoomKits[3]))//全部醫療包變成藥丸
			{
				//decl Float:entityPos[3];
				//GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entityPos);	
				//LogMessage("KITS here3 %d: %f %f %f",entity,entityPos[0],entityPos[1],entityPos[2]);
				if(k==1&&g_iHealthStyle == REPLACE_ALL_BUT_FINALE_KITS) {ReplaceEntity(entity, FIRST_AID_KIT_CLASSNAME, MODEL_FIRST_AID_KIT, 1);return;}
				if(pillsleft<=0)
					RemoveEdict(entity);
				else if(pillsleft>=5)
					{ReplaceKitWithPills(entity);ReplaceKitWithPills(entity);}
				else
					ReplaceKitWithPills(entity);
				pillsleft--;
				k++;
			}
		}
		
		return;
	}
	
	
	//非救援關 移除所有kits
	if(g_iHealthStyle != REPLACE_ALL_BUT_FINALE_KITS)
	{
		while ((entity = FindEntityByClassnameEx(entity, FIRST_AID_KIT_CLASSNAME)) != -1)
		{
			if(!IsValidEntity(entity))
				continue;
			
			//decl Float:entityPos[3];
			//GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entityPos);	
			//LogMessage("KITS here2 %d: %f %f %f: %d,%d,%d,%d",entity,entityPos[0],entityPos[1],entityPos[2],SaferoomKits[0],SaferoomKits[1],SaferoomKits[2],SaferoomKits[3]);
			if(!(entity==SaferoomKits[0]||entity==SaferoomKits[1]||entity==SaferoomKits[2]||entity==SaferoomKits[3]))//全部非起始安全室的醫療包移除
			{
				SafelyRemoveEdict(entity);
			}
		}
	}
				
	// Then, if we're using the hardcore setting, remove all pills from the map
	if(g_iHealthStyle == SAFEROOM_AND_FINALE_PILLS_ONLY)
	{		
		RemoveAllPills();
	}
}

/**
 * Removes all sets of pills from the map
 *
 * @noreturn
 */
static RemoveAllPills()
{
	DebugPrintToAllEx("Removing all pills");
	new removedCount = 0;
	new entity = -1;
	while ((entity = FindEntityByClassnameEx(entity, PAIN_PILLS_CLASSNAME)) != -1)
	{	
		if(!IsValidEntity(entity))
			continue;
		
		if(SafelyRemoveEdict(entity))
		{			
			removedCount++;
			DebugPrintToAllEx("Removed pills (ent: %i)", entity);
		}
		else
		{
			DebugPrintToAllEx("Failed to remove pills (ent: %i)", entity);
		}
	}
	
	DebugPrintToAllEx("Removed %i sets of pills", removedCount);
}

/**
 * Dishes out pills to the survivors
 * 
 * @noreturn
 */
static GivePillsToSurvivors()
{
	DebugPrintToAllEx("Giving pills to survivors.");
	new String:cmdGive[] = "give";
	new originalCmdFlags = GetCommandFlags(cmdGive);
	
	// Basically, make the command a non-cheat, execute it and then reset its flags.
	SetCommandFlags(cmdGive, originalCmdFlags & ~FCVAR_CHEAT);
	
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2)
		{			
			FakeClientCommand(i, "give pain_pills");
		}				
	}
	
	SetCommandFlags(cmdGive, originalCmdFlags);
}

/**
 * Determines whether the map is the finale and sets the global flag to identify it
 * 
 * @noreturn
 */
static DetermineIfMapIsFinale()
{	
	if (L4D_IsMissionFinalMap())
	{
		g_bIsFinale = true;
	}
	else
	{
		g_bIsFinale = false;
	}
}

/**
 * Predicate used to determine whether we should replace kits with pills
 * @param entity 	medkit entity to be considered for replacement
 * @return			whether the kit should be replaced with pills
 */
bool ShouldReplaceKitWithPills()
{
	if ((g_bIsFinale && 
		g_iHealthStyle == REPLACE_ALL_BUT_FINALE_KITS)||
		g_iHealthStyle == REPLACE_NO_KITS||
		g_iHealthStyle == REPLACE_ALL_BUT_FINALE_KITS)
	{
		// Finale medkit and we're not replacing them; can't touch this!
		//or REPLACE_NO_KITS
		return false;					
	}			
	
	return true;
}

/**
 * Replaces medkit with pills unless the health style precludes it
 * @param entity the medkit entity to be considered for replacement
 * @noreturn				
 */
static ReplaceKitWithPills(entity)
{	
	new result = ReplaceEntity(entity, PAIN_PILLS_CLASSNAME, MODEL_PAIN_PILLS, 1);
	if (!result)
	{
		ThrowError("Failed to replace medkit with pills! Entity %i", entity);
	}
	DebugPrintToAllEx("Medkit (entity %i) replaced with pills (entity %i)", entity, result);	
}

/**
 * Wrapper for printing a debug message without having to define channel index
 * everytime.
 *
 * @param format		Formatting rules.
 * @param ...			Variable number of format parameters.
 * @noreturn
 */
static DebugPrintToAllEx(const String:format[], any:...)
{
	decl String:buffer[DEBUG_MESSAGE_LENGTH];
	VFormat(buffer, sizeof(buffer), format, 2);
	DebugPrintToAll(g_iDebugChannel, buffer);
}

public FindSurvivorStart()
{
	new EntityCount = GetEntityCount();
	new String:EdictClassName[128];
	new Float:Location[3];
	//Search entities for either a locked saferoom door,
	for (new i = MaxClients + 1; i <= EntityCount; i++)
	{
		if (IsValidEntity(i) && IsValidEdict(i))
		{
			GetEdictClassname(i, EdictClassName, sizeof(EdictClassName));
			if ((StrContains(EdictClassName, "prop_door_rotating_checkpoint", false) != -1) && (GetEntProp(i, Prop_Send, "m_bLocked")==1))
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Location);
				SurvivorStart = Location;
				return;
			}
		}
	}
	//or a survivor start point.
	for (new i = MaxClients + 1; i <= EntityCount; i++)
	{
		if (IsValidEntity(i) && IsValidEdict(i))
		{
			GetEdictClassname(i, EdictClassName, sizeof(EdictClassName));
			if (StrContains(EdictClassName, "info_survivor_position", false) != -1)
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Location);
				SurvivorStart = Location;
				return;
			}
		}
	}
}

public RemoveMedkits(SaferoomKits[4])
{
	SaferoomKits[0] = -1;
	SaferoomKits[1] = -1;
	SaferoomKits[2] = -1;
	SaferoomKits[3] = -1;
	
	new k = 0;
	new EntityCount = GetEntityCount();
	new String:EdictClassName[128];
	new Float:NearestMedkit[3];
	new Float:Location[3];
	//Look for the nearest medkit from where the survivors start,
	for (new i = MaxClients + 1; i <= EntityCount; i++)
	{
		if (IsValidEntity(i) && IsValidEdict(i))
		{
			GetEdictClassname(i, EdictClassName, sizeof(EdictClassName));
			if (StrContains(EdictClassName, "weapon_first_aid_kit", false) != -1)
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Location);
				//If NearestMedkit is zero, then this must be the first medkit we found.
				if ((NearestMedkit[0] + NearestMedkit[1] + NearestMedkit[2]) == 0.0)
				{
					NearestMedkit = Location;
					continue;
				}
				//If this medkit is closer than the last medkit, record its location.
				if (GetVectorDistance(SurvivorStart, Location, false) < GetVectorDistance(SurvivorStart, NearestMedkit, false)) NearestMedkit = Location;
			}
		}
	}
	//then remove the kits
	for (new i = MaxClients + 1; i <= EntityCount; i++)
	{
		if (IsValidEntity(i) && IsValidEdict(i))
		{
			GetEdictClassname(i, EdictClassName, sizeof(EdictClassName));
			if (StrContains(EdictClassName, "weapon_first_aid_kit", false) != -1)
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Location);
				if (GetVectorDistance(NearestMedkit, Location, false) < 400)
				{			
					AcceptEntityInput(i, "Kill");
					SaferoomKits[k++] = i;
				}
			}
		}
	}
}

public ReplaceSafeRoomMedkits(SaferoomKits[4])
{
	SaferoomKits[0] = -1;
	SaferoomKits[1] = -1;
	SaferoomKits[2] = -1;
	SaferoomKits[3] = -1;
	
	new k = 0;
	new EntityCount = GetEntityCount();
	new String:EdictClassName[128];
	new Float:NearestMedkit[3];
	new Float:Location[3];
	//Look for the nearest medkit from where the survivors start,
	for (new i = MaxClients + 1; i <= EntityCount; i++)
	{
		if (IsValidEntity(i) && IsValidEdict(i))
		{
			GetEdictClassname(i, EdictClassName, sizeof(EdictClassName));
			if (StrContains(EdictClassName, "weapon_first_aid_kit", false) != -1)
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Location);
				//If NearestMedkit is zero, then this must be the first medkit we found.
				if ((NearestMedkit[0] + NearestMedkit[1] + NearestMedkit[2]) == 0.0)
				{
					NearestMedkit = Location;
					continue;
				}
				//If this medkit is closer than the last medkit, record its location.
				if (GetVectorDistance(SurvivorStart, Location, false) < GetVectorDistance(SurvivorStart, NearestMedkit, false)) NearestMedkit = Location;
			}
		}
	}
	//then replace the kits
	for (new i = MaxClients + 1; i <= EntityCount; i++)
	{
		if (IsValidEntity(i) && IsValidEdict(i))
		{
			GetEdictClassname(i, EdictClassName, sizeof(EdictClassName));
			if (StrContains(EdictClassName, "weapon_first_aid_kit", false) != -1)
			{
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Location);
				if (GetVectorDistance(NearestMedkit, Location, false) < 400)
				{
					//decl Float:entityPos[3];
					//GetEntPropVector(i, Prop_Send, "m_vecOrigin", entityPos);	
					//LogMessage("saferoom KIT here %d: %f %f %f",i,entityPos[0],entityPos[1],entityPos[2]);	
					if(!(k==3 && g_iHealthStyle == REPLACE_ALL_BUT_FINALE_KITS))
						ReplaceKitWithPills(i);
					SaferoomKits[k++] = i;
					
				}
			}
		}

		if(k == 4)
		{
			break;
		}
	}
}

void ResetPlugin()
{
	g_iRoundStart = 0;
	g_iPlayerSpawn = 0;
}

void EnumAndElimPillSpawns()
{
	EnumeratePillSpawns();
	RemoveToLimits();
}

int curitem[view_as<int>(ItemTracking)];
static EnumeratePillSpawns()
{
	//LogMessage("EnumeratePillSpawns()");

	new ItemList:itemindex;
	float origins[3], angles[3];
	new psychonic = GetEntityCount();
	for(new i = MaxClients + 1; i <= psychonic; i++)
	{
		if(IsValidEntity(i))
		{
			itemindex = GetItemIndexFromEntity(i);
			if(itemindex >= ItemList:0 /* && !IsEntityInSaferoom(i) */ )
			{
				if(IsInCabinet(i)) continue;

				KvJumpToKey(g_hMIData, g_sCurMap);

				int mylimit = KvGetNum(g_hMIData, "pill_limit", 2);
				KvRewind(g_hMIData);

				if(mylimit == 0)
				{
					//LogMessage("[IT] Killing spawn");

					if(!AcceptEntityInput(i, "kill"))
					{
						LogError("[IT] Error killing instance of item %s", g_sItemNames[itemindex][IN_longname]);
					}
				}
				else 
				{
					//LogMessage("[IT] Found an instance of item %s (%d)", g_sItemNames[itemindex][IN_longname], itemindex);
				
					// Store entity, angles, origin
					curitem[IT_entity]=i;
					GetEntPropVector(i, Prop_Send, "m_vecOrigin", origins);
					GetEntPropVector(i, Prop_Send, "m_angRotation", angles);

					//LogMessage("[IT] Saving spawn #%d at %.02f %.02f %.02f", GetArraySize(g_hItemSpawns[itemindex]), origins[0], origins[1], origins[2]);

					curitem[IT_origins]=origins[0];
					curitem[IT_origins1]=origins[1];
					curitem[IT_origins2]=origins[2];
					curitem[IT_angles]=angles[0];
					curitem[IT_angles1]=angles[1];
					curitem[IT_angles2]=angles[2];
					
					// Push this instance onto our array for that item
					PushArrayArray(g_hItemSpawns[itemindex], curitem[0]);
				}
			}
		}
	}
}

static RemoveToLimits()
{
	new curlimit;
	for(new itemidx = 0; itemidx < _:ItemList; itemidx++)
	{
		KvJumpToKey(g_hMIData, g_sCurMap);

		int curlimit = KvGetNum(g_hMIData, "pill_limit", 2);
		if (curlimit >0)
		{
			// Kill off item spawns until we've reduced the item to the limit
			while(GetArraySize(g_hItemSpawns[itemidx]) > curlimit)
			{
				// Pick a random
				new killidx = GetURandomIntRange(0, GetArraySize(g_hItemSpawns[itemidx])-1);
				
				//LogMessage("[IT] Killing randomly chosen %s (%d) #%d", g_sItemNames[itemidx][IN_longname], itemidx, killidx);

				GetArrayArray(g_hItemSpawns[itemidx], killidx, curitem[0]);
				if(IsValidEntity(curitem[IT_entity]) && !AcceptEntityInput(curitem[IT_entity], "kill"))
				{
					LogError("[IT] Error killing instance of item %s", g_sItemNames[itemidx][IN_longname]);
				}
				RemoveFromArray(g_hItemSpawns[itemidx],killidx);
			}
		}
		// If limit is 0, they're already dead. If it's negative, we kill nothing.
	}
}

static GenerateStoredPillSpawns()
{
	KillRegisteredItems();
	SpawnItems();
}

static KillRegisteredItems()
{
	//LogMessage("KillRegisteredItems()");

	decl ItemList:itemindex;
	new psychonic = GetEntityCount();
	for(new i = MaxClients + 1; i <= psychonic; i++)
	{
		if(IsValidEntity(i))
		{
			itemindex = GetItemIndexFromEntity(i);
			if(itemindex >= ItemList:0 /* && !IsEntityInSaferoom(i) */ )
			{
				if(IsInCabinet(i)) continue;

				// Kill items we're tracking;
				if(!AcceptEntityInput(i, "kill"))
				{
					LogError("[IT] Error killing instance of item %s", g_sItemNames[itemindex][IN_longname]);
				}
			}
		}
	}
}

static SpawnItems()
{
	decl Float:origins[3], Float:angles[3];
	new arrsize;
	new itement;
	decl String:sModelname[PLATFORM_MAX_PATH];
	int wepid;
	for(new itemidx = 0; itemidx < _:ItemList; itemidx++)
	{
		Format(sModelname, sizeof(sModelname), "models/w_models/weapons/w_eq_%s.mdl", g_sItemNames[itemidx][IN_modelname]);
		arrsize = GetArraySize(g_hItemSpawns[itemidx]);
		for(new idx = 0; idx < arrsize; idx++)
		{
			GetArrayArray(g_hItemSpawns[itemidx], idx, curitem[0]);

			origins[0]=curitem[IT_origins];
			origins[1]=curitem[IT_origins1];
			origins[2]=curitem[IT_origins2];

			angles[0]=curitem[IT_angles];
			angles[1]=curitem[IT_angles1];
			angles[2]=curitem[IT_angles2];

			wepid = GetWeaponIDFromItemList(ItemList:itemidx);
			
			//LogMessage("[IT] Spawning an instance of item %s (%d, wepid %d), number %d, at %.02f %.02f %.02f", g_sItemNames[itemidx][IN_officialname], itemidx, wepid, idx, origins[0], origins[1], origins[2]);
			
			itement = CreateEntityByName("weapon_pain_pills_spawn");
			SetEntProp(itement, Prop_Send, "m_weaponID", wepid);
			SetEntityModel(itement, sModelname);
			DispatchKeyValue(itement, "count", "1");
			TeleportEntity(itement, origins, angles, NULL_VECTOR);
			DispatchSpawn(itement);
			SetEntityMoveType(itement,MOVETYPE_NONE);
		}
	}
}

static ItemList:GetItemIndexFromEntity(entity)
{
	static String:classname[128];
	new ItemList:index;
	GetEdictClassname(entity, classname, sizeof(classname));
	
	if(StrEqual(classname, PAIN_PILLS_CLASSNAME))
	{
		return IL_PainPills;
	}
	
	return ItemList:-1;
}

// Produces the lookup trie for weapon spawn entities
//		to translate to our ADT array of spawns
static Handle:CreateItemListTrie()
{
	new Handle:mytrie = CreateTrie();
	SetTrieValue(mytrie, PAIN_PILLS_CLASSNAME, IL_PainPills);
	SetTrieValue(mytrie, "weapon_pain_pills", IL_PainPills);
	return mytrie;
}

stock GetURandomIntRange(min, max)
{
	return (GetURandomInt() % (max-min+1)) + min;
}

static int GetWeaponIDFromItemList(ItemList:id)
{
	switch(id)
	{
		case IL_PainPills:
		{
			return WEAPID_PAINPILLS;
		}
	}
	return -1;
}

bool IsInCabinet(int pill)
{
	//LogMessage("%d - spawnflags: %d", pill, GetEntProp(pill, Prop_Data, "m_spawnflags"));

	if(GetEntProp(pill, Prop_Data, "m_spawnflags") == 32770)
		return true;

	return false;
}

void MI_KV_Close()
{
	if (g_hMIData != null) {
		CloseHandle(g_hMIData);
		g_hMIData = null;
	}
}

void MI_KV_Load()
{
	char sNameBuff[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sNameBuff, 256, "data/%s", "mapinfo.txt");

	g_hMIData = CreateKeyValues("MapInfo");
	if (!FileToKeyValues(g_hMIData, sNameBuff)) {
		LogError("[MI] Couldn't load MapInfo data!");
		MI_KV_Close();
	}
}