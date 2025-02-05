#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <dhooks>

#define PLUGIN_VERSION "3.3"

public Plugin myinfo =
{
	name = "[L4D & 2] Tongue Bend Fix",
	author = "Forgetest",
	description = "Fix unexpected tongue breaks for \"bending too many times\".",
	version = PLUGIN_VERSION,
	url = "https://github.com/Target5150/MoYu_Server_Stupid_Plugins"
}

#define GAMEDATA_FILE "l4d_tongue_bend_fix"
#define KEY_UPDATEBEND "CTongue::UpdateBend"

enum
{
	Exception_Door,
	Exception_Carryable
}

ConVar g_cvExceptions;
StringMap g_smExceptions;

public void OnPluginStart()
{
	Handle conf = LoadGameConfigFile(GAMEDATA_FILE);
	if (!conf) SetFailState("Missing gamedata \""...GAMEDATA_FILE..."\"");
	
	DynamicDetour hDetour = DynamicDetour.FromConf(conf, KEY_UPDATEBEND);
	if (!hDetour) SetFailState("Missing signature \""...KEY_UPDATEBEND..."\"");
	if (!hDetour.Enable(Hook_Post, DTR_OnUpdateBend_Post)) SetFailState("Failed to post-detour \""...KEY_UPDATEBEND..."\"");
	delete hDetour;

	delete conf;
	
	g_cvExceptions = CreateConVar("tongue_bend_exception_flag",
									"1",
									"Flag to allow bending on certain types of entities.\n" \
								...	"1 = Doors, 2 = Carryable, 3 = All, 0 = Disable",
									FCVAR_NOTIFY|FCVAR_SPONLY,
									true, 0.0, true, 3.0);
	
	g_smExceptions = new StringMap();
	g_smExceptions.SetValue("prop_door_rotating", Exception_Door);
	g_smExceptions.SetValue("weapon_gascan", Exception_Carryable);
	g_smExceptions.SetValue("weapon_propanetank", Exception_Carryable);
	g_smExceptions.SetValue("weapon_cola_bottles", Exception_Carryable);
	g_smExceptions.SetValue("weapon_fireworkcrate", Exception_Carryable);
	g_smExceptions.SetValue("weapon_gnome", Exception_Carryable);
	g_smExceptions.SetValue("weapon_oxygentank", Exception_Carryable);
}

MRESReturn DTR_OnUpdateBend_Post(int pThis, DHookReturn hReturn)
{
	if (GetEntProp(pThis, Prop_Send, "m_bendPointCount") > 9)
	{
		int owner = GetEntPropEnt(pThis, Prop_Send, "m_owner");
		
		float vTonguePos[3], vVictimPos[3];
		GetClientEyePosition(owner, vTonguePos);
		
		int victim = GetEntPropEnt(owner, Prop_Send, "m_tongueVictim");
		GetAbsOrigin(victim, vVictimPos, true);
		
		float vFirstBendPos[3], vLastBendPos[3];
		static int iOffs_m_BendPositions = -1;
		if (iOffs_m_BendPositions == -1)
		{
			iOffs_m_BendPositions = FindSendPropInfo("CTongue", "m_bendPositions");
		}
		GetEntDataVector(pThis, iOffs_m_BendPositions, vFirstBendPos);
		GetEntDataVector(pThis, iOffs_m_BendPositions + 9 * 12, vLastBendPos);
		
		if (TestBendOnException(vTonguePos, vFirstBendPos)
			|| TestBendOnException(vLastBendPos, vVictimPos)
			|| TestBendOnException(vTonguePos, vVictimPos))
		{
			hReturn.Value = 1;
			return MRES_Supercede;
		}
		
		// should be bugged, ignore now.
		hReturn.Value = 0;
		return MRES_Supercede;
	}
	
	return MRES_Ignored;
}

bool TestBendOnException(const float vStart[3], const float vEnd[3])
{
	Handle tr = TR_TraceRayFilterEx(vStart, vEnd, MASK_VISIBLE_AND_NPCS|CONTENTS_WINDOW, RayType_EndPoint, TraceFilter_NoNPCsOrPlayer);
	if (TR_DidHit(tr))
	{
		int i = TR_GetEntityIndex(tr);
		
		char classname[64];
		GetEntityClassname(i, classname, sizeof(classname));
		if (g_smExceptions.GetValue(classname, i) && (g_cvExceptions.IntValue & i))
		{
			delete tr;
			return true;
		}
	}
	delete tr;
	return false;
}

bool TraceFilter_NoNPCsOrPlayer(int entity, int contentsMask)
{
	return entity > MaxClients;
}

// Credit to LuxLuma, from [left4dhooks_lux_library.inc]
/**
 * Get an entity's world space origin.
 * Note: Not all entities may support "CollisionProperty" for getting the center.
 * (https://github.com/LuxLuma/l4d2_structs/blob/master/collision_property.h)
 *
 * @param iEntity 		Entity index to get origin of.
 * @param vecOrigin		Vector to store origin in.
 * @param bCenter		True to get world space center, false otherwise.
 *
 * @error			Invalid entity index.
 **/
stock void GetAbsOrigin(int iEntity, float vecOrigin[3], bool bCenter=false)
{
	GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", vecOrigin);

	if(bCenter)
	{
		float vecMins[3];
		float vecMaxs[3];
		GetEntPropVector(iEntity, Prop_Send, "m_vecMins", vecMins);
		GetEntPropVector(iEntity, Prop_Send, "m_vecMaxs", vecMaxs);

		vecOrigin[0] += (vecMins[0] + vecMaxs[0]) * 0.5;
		vecOrigin[1] += (vecMins[1] + vecMaxs[1]) * 0.5;
		vecOrigin[2] += (vecMins[2] + vecMaxs[2]) * 0.5;
	}
}