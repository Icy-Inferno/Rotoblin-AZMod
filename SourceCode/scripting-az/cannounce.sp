/**
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 */


#pragma semicolon 1

#include <multicolors>
#include <sourcemod>
#include <sdktools>
#include <geoip>
#undef REQUIRE_EXTENSIONS
#include <geoipcity>
#undef REQUIRE_PLUGIN
#include <adminmenu>

#define VERSION "1.7"

/*****************************************************************


			G L O B A L   V A R S


*****************************************************************/
//static g_iSColors[5]             = {1,               3,              4,         6,			5};
//static String:g_sSColors[5][13]  = {"{DEFAULT}",     "{LIGHTGREEN}", "{GREEN}", "{YELLOW}",	"{OLIVE}"};

new bool:g_UseGeoIPCity = false;

new Handle:g_CvarConnectDisplayType = INVALID_HANDLE;

new String:player[50];
new String:player_ip[16];
new String:player_country[45];
new String:STEAMID[32];
new String:player_city[45];
new String:player_region[45];
new String:player_ccode[3];
new String:player_ccode3[4];
/*****************************************************************


			L I B R A R Y   I N C L U D E S


*****************************************************************/
#include "cannounce/countryshow.sp"
#include "cannounce/joinmsg.sp"
#include "cannounce/geolist.sp"
#include "cannounce/suppress.sp"


/*****************************************************************


			P L U G I N   I N F O


*****************************************************************/
public Plugin:myinfo =
{
	name = "Connect Announce",
	author = "Arg!, modify by harry",
	description = "Replacement of default player connection message, allows for custom connection messages",
	version = VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=77306"
};



/*****************************************************************


			F O R W A R D   P U B L I C S


*****************************************************************/
public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("cannounce.phrases");
	LoadTranslations("Roto2-AZ_mod.phrases");
	CreateConVar("sm_cannounce_version", VERSION, "Connect announce replacement", FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_CvarConnectDisplayType = CreateConVar("sm_ca_connectdisplaytype", "1", "[1|0] if 1 then displays connect message after admin check and allows the {PLAYERTYPE} placeholder. If 0 displays connect message on client auth (earlier) and disables the {PLAYERTYPE} placeholder");
	
	//event hooks
	HookEvent("player_disconnect", event_PlayerDisconnect, EventHookMode_Pre);
	
	
	//country show
	SetupCountryShow();
	
	//custom join msg
	SetupJoinMsg();
	
	//geographical player list
	SetupGeoList();
	
	//suppress standard connection message
	SetupSuppress();

	// Check if we have GeoIPCity.ext loaded
	g_UseGeoIPCity = LibraryExists("GeoIPCity");
	
	//create config file if not exists
	AutoExecConfig(true, "cannounce");
}

public OnMapStart()
{
	//precahce and set downloads for sounds files for all players
	LoadSoundFilesAll();
	
	
	OnMapStart_JoinMsg();
}

public OnClientAuthorized(client, const String:auth[])
{
	if( GetConVarInt(g_CvarConnectDisplayType) == 0 )
	{
		if( !IsFakeClient(client) && GetClientCount(true) < MaxClients )
		{
			OnPostAdminCheck_CountryShow(client);
		
			OnPostAdminCheck_JoinMsg();
		}
	}
}

public OnClientPostAdminCheck(client)
{
	decl String:auth[32];
	
	if( GetConVarInt(g_CvarConnectDisplayType) == 1 )
	{
		GetClientAuthId(client, AuthId_Steam2,auth, sizeof(auth));
		if( !IsFakeClient(client) && GetClientCount(true) < MaxClients )
		{
			OnPostAdminCheck_CountryShow(client);
		
			OnPostAdminCheck_JoinMsg();
		}
	}	
}

public OnLibraryRemoved(const String:name[])
{
	// Was the GeoIPCity extension removed?
	if(StrEqual(name, "GeoIPCity"))
		g_UseGeoIPCity = false;
}


public OnLibraryAdded(const String:name[])
{
	// Is the GeoIPCity extension running?
	if(StrEqual(name, "GeoIPCity"))
		g_UseGeoIPCity = true;
}


/****************************************************************


			C A L L B A C K   F U N C T I O N S


****************************************************************/
public Action:event_PlayerDisconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if( client && !IsFakeClient(client) && !dontBroadcast )
	{
		event_PlayerDisc_CountryShow(event, name, dontBroadcast);
		
		if(IsClientInGame(client)) OnClientDisconnect_JoinMsg();
	}
	
	
	return event_PlayerDisconnect_Suppress( event, name, dontBroadcast );
}


/*****************************************************************


			P L U G I N   F U N C T I O N S


*****************************************************************/
//Thanks to Darkthrone (https://forums.alliedmods.net/member.php?u=54636)
bool:IsLanIP( String:src[16] )
{
	decl String:ip4[4][4];
	new ipnum;

	if(ExplodeString(src, ".", ip4, 4, 4) == 4)
	{
		ipnum = StringToInt(ip4[0])*65536 + StringToInt(ip4[1])*256 + StringToInt(ip4[2]);
		
		if((ipnum >= 655360 && ipnum < 655360+65535) || (ipnum >= 11276288 && ipnum < 11276288+4095) || (ipnum >= 12625920 && ipnum < 12625920+255))
		{
			return true;
		}
	}

	return false;
}

PrintFormattedMessageToAll( client, playerjoin )//給全部人看的
{
	if(!IsClientInGame(client)) return;
	
	decl String:message[301];
	
	SetFormattedMessage( client );
	
	Format( message, sizeof(message), "%s", player_country );
	if(!StrEqual(player_region, "an Unknown Region", true))
		Format( message, sizeof(message), "%s, %s",message, player_region);
	if(!StrEqual(player_city, "an IP Address", true)&&!StrEqual(player_city, "Somewhere", true))
		Format( message, sizeof(message), "%s, %s",message, player_city);
		
	if(playerjoin == 1)//玩家進來
	{
		CPrintToChatAll("{default}[{olive}TS{default}] %t ({green}%s{default})","cannounce1",player,message);
	}
	else//玩家離開
	{
		CPrintToChatAll("{default}[{olive}TS{default}] %t ({green}%s{default})","cannounce2",player,dcreason);
	}
	//player 玩家名稱
	//player_country 玩家國家
	//player_ip 玩家IP
	//STEAMID 玩家steam id
	//dcreason 玩家離開原因
	//player_city 玩家的城市
	//player_region 玩家的地區(省,州)
	//player_ccode 玩家的國家短代號
	//player_ccode3 玩家的國家短代號(多一些代號)
}

PrintFormattedMessageToAdmins( client, playerjoin)//專屬給adm看的
{
	decl String:message[301];
	
	SetFormattedMessage( client );
	
	Format( message, sizeof(message), "%s", player_country );
	if(!StrEqual(player_region, "an Unknown Region", true))
		Format( message, sizeof(message), "%s, %s",message, player_region);
	if(!StrEqual(player_city, "an IP Address", true)&&!StrEqual(player_city, "Somewhere", true))
		Format( message, sizeof(message), "%s, %s",message, player_city);

		
	if(IsClientInGame(client))
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if( IsClientInGame(i) && CheckCommandAccess( i, "", ADMFLAG_GENERIC, true ) )
			{
				if(playerjoin == 1)//玩家進來
				{
					CPrintToChat(i, "{default}[{olive}TS{default}] %T ({green}%s{default}) IP: {green}%s{default} {olive}<%s>","cannounce1",i, player, message, player_ip, STEAMID);
				}
				else//玩家離開
				{
					CPrintToChat(i, "{default}[{olive}TS{default}] %T ({green}%s{default}) IP: {green}%s{default} {olive}<%s>","cannounce2",i,player,dcreason,player_ip, STEAMID);
				}
			}
		}
	}
	
	if(playerjoin == 1)//玩家進來
	{
		LogMessage("[TS] Player %s conneted. (%s) IP:%s <%s>", player, message, player_ip, STEAMID);
	}
	else//玩家離開
	{
		LogMessage("[TS] Player %s disconneted. (%s)[%s] IP:%s <%s>",player,dcreason,message,player_ip,STEAMID);
	}
}

PrintFormattedMsgToNonAdmins( client, playerjoin )//給不是adm看的
{
	if(!IsClientInGame(client)) return;

	decl String:message[301];
	
	SetFormattedMessage( client );
	
	Format( message, sizeof(message), "%s", player_country );
	if(!StrEqual(player_region, "an Unknown Region", true))
		Format( message, sizeof(message), "%s, %s",message, player_region);
	if(!StrEqual(player_city, "an IP Address", true)&&!StrEqual(player_city, "Somewhere", true))
		Format( message, sizeof(message), "%s, %s",message, player_city);
		
	for (new i = 1; i <= MaxClients; i++)
	{
		if( IsClientInGame(i) && !CheckCommandAccess( i, "", ADMFLAG_GENERIC, true ) )
		{
			if(playerjoin == 1)//玩家進來
			{
				CPrintToChat(i, "{default}[{olive}TS{default}] %T ({green}%s{default})","cannounce1",i, player, message);
			}
			else//玩家離開
			{
				CPrintToChat(i, "{default}[{olive}TS{default}] %T ({green}%s{default})","cannounce2",i,player,dcreason);
			}
		}
	}
}

SetFormattedMessage(client)
{
	//decl String:sColor[4];
	//decl String:sPlayerAdmin[32];
	//decl String:sPlayerPublic[32];
	decl bool:bIsLanIp;
	//decl AdminId:aid;
	
	if( client > -1 )
	{
		GetClientIP(client, player_ip, sizeof(player_ip)); 
		
		//detect LAN IP
		bIsLanIp = IsLanIP( player_ip );
		
		// Using GeoIPCity extension...
		if ( g_UseGeoIPCity )
		{
			if( !GeoipGetRecord( player_ip, player_city, player_region, player_country, player_ccode, player_ccode3 ) )
			{
				if( bIsLanIp )
				{
					Format( player_city, sizeof(player_city), "%T", "LAN City Desc", LANG_SERVER );
					Format( player_region, sizeof(player_region), "%T", "LAN Region Desc", LANG_SERVER );
					Format( player_country, sizeof(player_country), "%T", "LAN Country Desc", LANG_SERVER );
					Format( player_ccode, sizeof(player_ccode), "%T", "LAN Country Short", LANG_SERVER );
					Format( player_ccode3, sizeof(player_ccode3), "%T", "LAN Country Short 3", LANG_SERVER );
				}
				else
				{
					Format( player_city, sizeof(player_city), "%T", "Unknown City Desc", LANG_SERVER );
					Format( player_region, sizeof(player_region), "%T", "Unknown Region Desc", LANG_SERVER );
					Format( player_country, sizeof(player_country), "%T", "Unknown Country Desc", LANG_SERVER );
					Format( player_ccode, sizeof(player_ccode), "%T", "Unknown Country Short", LANG_SERVER );
					Format( player_ccode3, sizeof(player_ccode3), "%T", "Unknown Country Short 3", LANG_SERVER );
				}
			}
		}
		else // Using GeoIP default extension...
		{
			if( !GeoipCode2(player_ip, player_ccode) )
			{
				if( bIsLanIp )
				{
					Format( player_ccode, sizeof(player_ccode), "%T", "LAN Country Short", LANG_SERVER );
				}
				else
				{
					Format( player_ccode, sizeof(player_ccode), "%T", "Unknown Country Short", LANG_SERVER );
				}
			}
			
			if( !GeoipCountry(player_ip, player_country, sizeof(player_country)) )
			{
				if( bIsLanIp )
				{
					Format( player_country, sizeof(player_country), "%T", "LAN Country Desc", LANG_SERVER );
				}
				else
				{
					Format( player_country, sizeof(player_country), "%T", "Unknown Country Desc", LANG_SERVER );
				}
			}
			
			// Since the GeoIPCity extension isn't loaded, we don't know the city or region.
			if( bIsLanIp )
			{
				Format( player_city, sizeof(player_city), "%T", "LAN City Desc", LANG_SERVER );
				Format( player_region, sizeof(player_region), "%T", "LAN Region Desc", LANG_SERVER );
				Format( player_ccode3, sizeof(player_ccode3), "%T", "LAN Country Short 3", LANG_SERVER );
			}
			else
			{
				Format( player_city, sizeof(player_city), "%T", "Unknown City Desc", LANG_SERVER );
				Format( player_region, sizeof(player_region), "%T", "Unknown Region Desc", LANG_SERVER );
				Format( player_ccode3, sizeof(player_ccode3), "%T", "Unknown Country Short 3", LANG_SERVER );
			}
		}
		
		// Fallback for unknown/empty location strings
		if( StrEqual( player_city, "" ) )
		{
			Format( player_city, sizeof(player_city), "%T", "Unknown City Desc", LANG_SERVER );
		}
		
		if( StrEqual( player_region, "" ) )
		{
			Format( player_region, sizeof(player_region), "%T", "Unknown Region Desc", LANG_SERVER );
		}
		
		if( StrEqual( player_country, "" ) )
		{
			Format( player_country, sizeof(player_country), "%T", "Unknown Country Desc", LANG_SERVER );
		}
		
		if( StrEqual( player_ccode, "" ) )
		{
			Format( player_ccode, sizeof(player_ccode), "%T", "Unknown Country Short", LANG_SERVER );
		}
		
		if( StrEqual( player_ccode3, "" ) )
		{
			Format( player_ccode3, sizeof(player_ccode3), "%T", "Unknown Country Short 3", LANG_SERVER );
		}
		
		// Add "The" in front of certain countries
		if( StrContains( player_country, "United", false ) != -1 || 
			StrContains( player_country, "Republic", false ) != -1 || 
			StrContains( player_country, "Federation", false ) != -1 || 
			StrContains( player_country, "Island", false ) != -1 || 
			StrContains( player_country, "Netherlands", false ) != -1 || 
			StrContains( player_country, "Isle", false ) != -1 || 
			StrContains( player_country, "Bahamas", false ) != -1 || 
			StrContains( player_country, "Maldives", false ) != -1 || 
			StrContains( player_country, "Philippines", false ) != -1 || 
			StrContains( player_country, "Vatican", false ) != -1 )
		{
			Format( player_country, sizeof(player_country), "The %s", player_country );
		}

		GetClientName(client, player, sizeof(player));
		GetClientAuthId(client, AuthId_Steam2,STEAMID, sizeof(STEAMID));
	}
}