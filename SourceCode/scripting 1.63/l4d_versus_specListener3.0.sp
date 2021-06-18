#include <sourcemod>
#include <sdktools>
#include <colors>

#define VOICE_NORMAL	0	/**< Allow the client to listen and speak normally. */
#define VOICE_MUTED		1	/**< Mutes the client from speaking to everyone. */
#define VOICE_SPEAKALL	2	/**< Allow the client to speak to everyone. */
#define VOICE_LISTENALL	4	/**< Allow the client to listen to everyone. */
#define VOICE_TEAM		8	/**< Allow the client to always speak to team, even when dead. */
#define VOICE_LISTENTEAM	16	/**< Allow the client to always hear teammates, including dead ones. */

#define TEAM_SPEC 1
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

static bool:bListionActive[MAXPLAYERS + 1];
native Is_Ready_Plugin_On();
#define PLUGIN_VERSION "3.0"
new Handle:hspecListener_enable;
new bool:specListener_enable;

public Plugin:myinfo = 
{
	name = "SpecLister",
	author = "waertf & bear modded by bman, l4d1 versus port by harry",
	description = "Allows spectator listen others team voice for l4d",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=95474"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("IsClientListenMode", Native_IsClientListenMode);
	CreateNative("OpenSpectatorsListenMode", Native_OpenSpectatorsListenMode);
	return APLRes_Success;
}

public Native_IsClientListenMode(Handle:plugin, numParams)
{
   new num1 = GetNativeCell(1);
   return bListionActive[num1];
}


public Native_OpenSpectatorsListenMode(Handle:plugin, numParams) {
  
	if(!specListener_enable) return;
	
	decl String:Info[50];
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientConnected(client) && IsClientInGame(client)&& !IsFakeClient(client) && GetClientTeam(client) == TEAM_SPEC)
		{
			if(bListionActive[client])
			{
				SetClientListeningFlags(client, VOICE_LISTENALL);
			}
			else
			{
				SetClientListeningFlags(client, VOICE_NORMAL);
			}
			Format(Info, sizeof(Info), "%T", (bListionActive[client] ? "Off" : "On"),client);
			CPrintToChat(client,"%T","Listen Mode1",client, Info,"!hear");
		}
	}	
}

 public OnPluginStart()
{
	LoadTranslations("Roto2-AZ_mod.phrases");
	HookEvent("player_team",Event_PlayerChangeTeam);
	HookEvent("player_left_start_area", LeftStartAreaEvent, EventHookMode_PostNoCopy);
	RegConsoleCmd("sm_hear", Command_hear);
	
	hspecListener_enable = CreateConVar("specListener_enable", "1", "Enable Hear Feature? [0-Disable, 1-Enable]", 0, true, 0.0, true, 1.0);
	specListener_enable = GetConVarBool(hspecListener_enable);
	HookConVarChange(hspecListener_enable, ConVarChange_hspecListener_enable);
	
	//Spectators hear Team_Chat
	RegConsoleCmd("say_team", Command_SayTeam);
	
	if(specListener_enable)
		for (new i = 1; i <= MaxClients; i++) 
			bListionActive[i] = true;
	else
		for (new i = 1; i <= MaxClients; i++) 
			bListionActive[i] = false;
}

public ConVarChange_hspecListener_enable(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(oldValue[0] == newValue[0])
	{
		return;
	}
	specListener_enable = GetConVarBool(hspecListener_enable);
	
	if(!specListener_enable)
	{
		for (new client = 1; client <= MaxClients; client++)
		{
			bListionActive[client] = false;
			if(IsClientConnected(client) && IsClientInGame(client)&& !IsFakeClient(client))
				SetClientListeningFlags(client, VOICE_NORMAL);
		}
	}
	else
		for (new i = 1; i <= MaxClients; i++) 
			bListionActive[i] = true;
}

public LeftStartAreaEvent(Handle:event, String:name[], bool:dontBroadcast)
{
	if(!Is_Ready_Plugin_On()&&specListener_enable)
	{
		decl String:Info[50];
		for (new client = 1; client <= MaxClients; client++)
			if (IsClientConnected(client) && IsClientInGame(client)&& !IsFakeClient(client) && GetClientTeam(client) == TEAM_SPEC)
			{
				if(bListionActive[client])
				{
					SetClientListeningFlags(client, VOICE_LISTENALL);
				}
				else
				{
					SetClientListeningFlags(client, VOICE_NORMAL);
				}
				Format(Info, sizeof(Info), "%T", (bListionActive[client] ? "Off" : "On"),client);
				CPrintToChat(client,"%T","Listen Mode1",client, Info,"!hear");
			}
	}
}

public Action:Command_hear(client,args)
{
	if (client == 0)
	{
		PrintToServer("[TS] %t","command cannot be used by server.");
		return Plugin_Handled;
	}
	
	if(GetClientTeam(client)!=TEAM_SPEC || !specListener_enable)
		return Plugin_Handled;
	
	bListionActive[client] = !bListionActive[client];
	decl String:Info[50];
	Format(Info, sizeof(Info), "%T", (bListionActive[client] ? "On" : "Off"),client);
	CPrintToChat(client,"%T","Listen Mode2",client, Info);	
	
	if(bListionActive[client])
	{
		SetClientListeningFlags(client, VOICE_LISTENALL);
		CPrintToChat(client,"%T","Listen Mode3",client );
	}
	else
	{
		SetClientListeningFlags(client, VOICE_NORMAL);
	}
 
	return Plugin_Continue;

}

public Action:Command_SayTeam(client, args)
{
	if (client == 0 || !IsClientInGame(client))
		return Plugin_Continue;
		
	new String:buffermsg[256];
	new String:text[192];
	GetCmdArgString(text, sizeof(text));
	new senderteam = GetClientTeam(client);
	
	if(FindCharInString(text, '@') == 0)	//Check for admin messages
		return Plugin_Continue;
	
	new startidx = trim_quotes(text);  //Not sure why this function is needed.(bman)
	
	new String:name[32];
	GetClientName(client,name,31);
	
	new String:senderTeamName[10];
	switch (senderteam)
	{
		case 3:
			senderTeamName = "INFECTED"
		case 2:
			senderTeamName = "SURVIVORS"
		case 1:
			senderTeamName = "SPEC"
	}
	
	//Is not console, Sender is not on Spectators, and there are players on the spectator team
	if (client > 0 && senderteam != TEAM_SPEC && GetTeamClientCount(TEAM_SPEC) > 0)
	{
		for (new i = 1; i <= GetMaxClients(); i++)
		{
			if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SPEC)
			{
				switch (senderteam)	//Format the color different depending on team
				{
					case 3:
						Format(buffermsg, 256, "\x01(%s) \x04%s\x05: %s", senderTeamName, name, text[startidx]);
					case 2:
						Format(buffermsg, 256, "\x01(%s) \x03%s\x05: %s", senderTeamName, name, text[startidx]);
				}
				SayText2(i, client, buffermsg);	//Send the message to spectators
			}
		}
	}
	return Plugin_Continue;
}

stock SayText2(client_index, author_index, const String:message[] ) 
{
    new Handle:buffer = StartMessageOne("SayText2", client_index)
    if (buffer != INVALID_HANDLE) 
	{
        BfWriteByte(buffer, author_index)
        BfWriteByte(buffer, true)
        BfWriteString(buffer, message)
        EndMessage()
    }
} 

public trim_quotes(String:text[])
{
	new startidx = 0
	if (text[0] == '"')
	{
		startidx = 1
		/* Strip the ending quote, if there is one */
		new len = strlen(text);
		if (text[len-1] == '"')
		{
			text[len-1] = '\0'
		}
	}
	
	return startidx
}

public Event_PlayerChangeTeam(Handle:event, const String:name[], bool:dontBroadcast)
{
	new userID = GetClientOfUserId(GetEventInt(event, "userid"));
	if(userID==0 || !specListener_enable)
		return ;

	if(!IsFakeClient(userID)&&IsClientConnected(userID)&&IsClientInGame(userID))
		CreateTimer(1.0,PlayerChangeTeamCheck,userID);
}
public Action:PlayerChangeTeamCheck(Handle:timer,any:client)
{
	if(IsClientConnected(client) && IsClientInGame(client)&& !IsFakeClient(client))
		if(GetClientTeam(client)==TEAM_SPEC)
		{
			if(bListionActive[client])
			{
				SetClientListeningFlags(client, VOICE_LISTENALL);
			}
			else
			{
				SetClientListeningFlags(client, VOICE_NORMAL);
			}
		}
		else
		{
			SetClientListeningFlags(client, VOICE_NORMAL);
		}
}

public IsValidClient (client)
{
    if (client == 0)
        return false;
    
    if (!IsClientConnected(client))
        return false;
    
    if (IsFakeClient(client))
        return false;
    
    if (!IsClientInGame(client))
        return false;	
		
    return true;
}  