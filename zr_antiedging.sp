#include <sourcemod>
#include <sdktools>
#include <zombiereloaded>

#pragma semicolon 1

new StuckCheck[MAXPLAYERS+1] 	= {0, ...};
new bool:isStuck[MAXPLAYERS+1];

new Float:Step = 20.0;
new Float:RadiusSize = 200.0;
new Float:Ground_Velocity[3] = {0.0, 0.0, -300.0};

new Handle:h_stuck;
new bool:g_stuck;

public Plugin:myinfo =
{
	name = "SM Anti Edging",
	author = "Franc1sco franug",
	description = "",
	version = "1.1",
	url = "http://steamcommunity.com/id/franug"
};

public OnPluginStart()
{
	CreateConVar("sm_antiedging_version", "1.0", "Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	h_stuck = CreateConVar("sm_antiedging_unstuck", "1", "Enable/disable auto unstuck");
	
	g_stuck = GetConVarBool(h_stuck);
	HookConVarChange(h_stuck, OnConVarChanged);
	
}

public OnConVarChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_stuck = bool:StringToInt(newValue);
}

public ZR_OnClientInfected(client, attacker, bool:motherInfect, bool:respawnOverride, bool:respawn)
{
	if(!IsValidClient(attacker)) return;
	
	decl Float:ang[3], Float:vec[3];
	GetClientAbsAngles(attacker, ang);
	GetClientAbsOrigin(attacker, vec);
	
	vec[2] += 20.0;
	
	TeleportEntity(client, vec, ang, NULL_VECTOR);
	
	if(g_stuck)
	{
		StuckCheck[client] = 0;
		StartStuckDetection(client);
	}
}


public IsValidClient( client ) 
{ 
    if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) || !IsPlayerAlive(client) ) 
        return false; 
     
    return true; 
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//									More Stuck Detection
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


stock CheckIfPlayerCanMove(iClient, testID, Float:X=0.0, Float:Y=0.0, Float:Z=0.0)	// In few case there are issues with IsPlayerStuck() like clip
{
	decl Float:vecVelo[3];
	decl Float:vecOrigin[3];
	GetClientAbsOrigin(iClient, vecOrigin);
	
	vecVelo[0] = X;
	vecVelo[1] = Y;
	vecVelo[2] = Z;
	
	SetEntPropVector(iClient, Prop_Data, "m_vecBaseVelocity", vecVelo);
	
	new Handle:TimerDataPack;
	CreateDataTimer(0.1, TimerWait, TimerDataPack); 
	WritePackCell(TimerDataPack, iClient);
	WritePackCell(TimerDataPack, testID);
	WritePackFloat(TimerDataPack, vecOrigin[0]);
	WritePackFloat(TimerDataPack, vecOrigin[1]);
	WritePackFloat(TimerDataPack, vecOrigin[2]);
}

public Action:TimerWait(Handle:timer, Handle:data)
{	
	decl Float:vecOrigin[3];
	decl Float:vecOriginAfter[3];
	
	ResetPack(data, false);
	new iClient 		= ReadPackCell(data);
	new testID 			= ReadPackCell(data);
	vecOrigin[0]		= ReadPackFloat(data);
	vecOrigin[1]		= ReadPackFloat(data);
	vecOrigin[2]		= ReadPackFloat(data);
	
	
	GetClientAbsOrigin(iClient, vecOriginAfter);
	
	if(GetVectorDistance(vecOrigin, vecOriginAfter, false) < 10.0) // Can't move
	{
		if(testID == 0)
			CheckIfPlayerCanMove(iClient, 1, 0.0, 0.0, -500.0);	// Jump
		else if(testID == 1)
			CheckIfPlayerCanMove(iClient, 2, -500.0, 0.0, 0.0);
		else if(testID == 2)
			CheckIfPlayerCanMove(iClient, 3, 0.0, 500.0, 0.0);
		else if(testID == 3)
			CheckIfPlayerCanMove(iClient, 4, 0.0, -500.0, 0.0);
		else if(testID == 4)
			CheckIfPlayerCanMove(iClient, 5, 0.0, 0.0, 300.0);
		else
			FixPlayerPosition(iClient);
	}
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//									Fix Position
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


FixPlayerPosition(iClient)
{
	if(isStuck[iClient]) // UnStuck player stuck in prop
	{
		new Float:pos_Z = 0.1;
		
		while(pos_Z <= RadiusSize && !TryFixPosition(iClient, 10.0, pos_Z))
		{	
			pos_Z = -pos_Z;
			if(pos_Z > 0.0)
				pos_Z += Step;
		}
		
		if(!CheckIfPlayerIsStuck(iClient) && StuckCheck[iClient] < 7) // If client was stuck => new check
			StartStuckDetection(iClient);
	
	}
	else // UnStuck player stuck in clip (invisible wall)
	{
		// if it is a clip on the sky, it will try to find the ground !
		new Handle:trace = INVALID_HANDLE;
		decl Float:vecOrigin[3];
		decl Float:vecAngle[3];
		
		GetClientAbsOrigin(iClient, vecOrigin);
		vecAngle[0] = 90.0;
		trace = TR_TraceRayFilterEx(vecOrigin, vecAngle, MASK_SOLID, RayType_Infinite, TraceEntityFilterSolid);		
		if(!TR_DidHit(trace)) 
		{
			CloseHandle(trace);
			return;
		}
		
		TR_GetEndPosition(vecOrigin, trace);
		CloseHandle(trace);
		vecOrigin[2] += 10.0;
		TeleportEntity(iClient, vecOrigin, NULL_VECTOR, Ground_Velocity);
		
		if(StuckCheck[iClient] < 7) // If client was stuck in invisible wall => new check
			StartStuckDetection(iClient);
	}
}

bool:TryFixPosition(iClient, Float:Radius, Float:pos_Z)
{
	decl Float:DegreeAngle;
	decl Float:vecPosition[3];
	decl Float:vecOrigin[3];
	decl Float:vecAngle[3];
	
	GetClientAbsOrigin(iClient, vecOrigin);
	GetClientEyeAngles(iClient, vecAngle);
	vecPosition[2] = vecOrigin[2] + pos_Z;

	DegreeAngle = -180.0;
	while(DegreeAngle < 180.0)
	{
		vecPosition[0] = vecOrigin[0] + Radius * Cosine(DegreeAngle * FLOAT_PI / 180); // convert angle in radian
		vecPosition[1] = vecOrigin[1] + Radius * Sine(DegreeAngle * FLOAT_PI / 180);
		
		TeleportEntity(iClient, vecPosition, vecAngle, Ground_Velocity);
		if(!CheckIfPlayerIsStuck(iClient))
			return true;
		
		DegreeAngle += 10.0; // + 10°
	}
	
	TeleportEntity(iClient, vecOrigin, vecAngle, Ground_Velocity);
	if(Radius <= RadiusSize)
		return TryFixPosition(iClient, Radius + Step, pos_Z);
	
	return false;
}


StartStuckDetection(iClient)
{
	StuckCheck[iClient]++;
	isStuck[iClient] = false;
	isStuck[iClient] = CheckIfPlayerIsStuck(iClient); // Check if player stuck in prop
	CheckIfPlayerCanMove(iClient, 0, 500.0, 0.0, 0.0);
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//									Stuck Detection
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


stock bool:CheckIfPlayerIsStuck(iClient)
{
	decl Float:vecMin[3], Float:vecMax[3], Float:vecOrigin[3];
	
	GetClientMins(iClient, vecMin);
	GetClientMaxs(iClient, vecMax);
	GetClientAbsOrigin(iClient, vecOrigin);
	
	TR_TraceHullFilter(vecOrigin, vecOrigin, vecMin, vecMax, MASK_SOLID, TraceEntityFilterSolid);
	return TR_DidHit();	// head in wall ?
}


public bool:TraceEntityFilterSolid(entity, contentsMask) 
{
	return entity > 1;
}