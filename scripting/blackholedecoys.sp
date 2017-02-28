#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Rachnus"
#define PLUGIN_VERSION "1.00"

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>
#include <emitsoundany>

#pragma newdecls required
#define BLACKHOLE_VOLUME 5.0

EngineVersion g_Game;
int g_PVMid[MAXPLAYERS + 1]; // Predicted ViewModel ID's
int g_iViewModelIndex;
ArrayList g_Blackholes;
float g_BlackholeVolume[MAXPLAYERS * 2] =  { BLACKHOLE_VOLUME, ... };

ConVar g_BlackholeEnable;
ConVar g_ParticleEffect;
ConVar g_MinimumDistance;
ConVar g_BounceVelocity;
ConVar g_ShakePlayer;
ConVar g_ShakeIntensity;
ConVar g_ShakeFrequency;
ConVar g_BlackholeForce;
ConVar g_BlackholeDuration;
ConVar g_BlackholeSetting;
ConVar g_BlackholeDamage;
ConVar g_BlackholeProps;
ConVar g_BlackholeWeapons;
ConVar g_BlackholeGrenades;
ConVar g_BlackholeFlashbangs;
ConVar g_BlackholeSmokes;


public Plugin myinfo = 
{
	name = "Black hole decoys",
	author = PLUGIN_AUTHOR,
	description = "Creates a temporary black hole at decoy landing position",
	version = PLUGIN_VERSION,
	url = "https://github.com/Rachnus"
};

public void OnPluginStart()
{
	g_Game = GetEngineVersion();
	if(g_Game != Engine_CSGO)
	{
		SetFailState("This plugin is for CSGO only.");	
	}
	
	for (int i = 1; i <= MaxClients;i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			SDKHook(i, SDKHook_WeaponSwitchPost, OnClientWeaponSwitchPost);
			g_PVMid[i] = Weapon_GetViewModelIndex(i, -1);
		}
	}
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	g_BlackholeEnable = 	CreateConVar("blackholedecoys_enabled", "1", "Enable/Disable plugin", FCVAR_NOTIFY);
	g_ParticleEffect = 		CreateConVar("blackholedecoys_particle_effect", "blackhole", "Name of the particle effect you want to use", FCVAR_NOTIFY);
	g_MinimumDistance = 	CreateConVar("blackholedecoys_minimum_distance", "250", "Minimum distance to push player towards black hole", FCVAR_NOTIFY);
	g_BounceVelocity = 		CreateConVar("blackholedecoys_bounce_velocity", "300", "Up/Down velocity to push the grenade on bounce", FCVAR_NOTIFY);
	g_ShakePlayer = 		CreateConVar("blackholedecoys_shake_player", "1", "Whether or not to shake the player once entering minimum distance", FCVAR_NOTIFY);
	g_ShakeIntensity =		CreateConVar("blackholedecoys_shake_intensity", "5.0", "Intensity of the shake", FCVAR_NOTIFY);
	g_ShakeFrequency =		CreateConVar("blackholedecoys_shake_frequency", "0.7", "Frequency of the shake", FCVAR_NOTIFY);
	g_BlackholeForce = 		CreateConVar("blackholedecoys_force", "350", "Force to fly at the black hole", FCVAR_NOTIFY); 
	g_BlackholeDuration = 	CreateConVar("blackholedecoys_duration", "10", "Duration in seconds the blackhole to lasts", FCVAR_NOTIFY);
	g_BlackholeSetting = 	CreateConVar("blackholedecoys_setting", "1", "0 = Do nothing on entering blackhole origin, 1 = Do damage on entering the blackhole origin", FCVAR_NOTIFY);
	g_BlackholeDamage = 	CreateConVar("blackholedecoys_damage", "5", "Damage to do once entering blackhole origin", FCVAR_NOTIFY);
	g_BlackholeProps = 		CreateConVar("blackholedecoys_props", "1", "Push props towards black hole (Client side props will not work)", FCVAR_NOTIFY);
	g_BlackholeWeapons = 	CreateConVar("blackholedecoys_weapons", "1", "Push dropped weapons towards black hole", FCVAR_NOTIFY);
	g_BlackholeGrenades = 	CreateConVar("blackholedecoys_hegrenades", "1", "Push active hand grenades towards black hole", FCVAR_NOTIFY);
	g_BlackholeFlashbangs = CreateConVar("blackholedecoys_flashbangs", "1", "Push active flashbangs towards black hole", FCVAR_NOTIFY);
	g_BlackholeSmokes = 	CreateConVar("blackholedecoys_smokes", "1", "Push active smoke grenades towards black hole", FCVAR_NOTIFY);
	
	g_Blackholes = new ArrayList();
	AutoExecConfig(true, "blackholedecoys");
}

public void ShakeScreen(int client, float intensity, float duration, float frequency)
{
    Handle pb;
    if((pb = StartMessageOne("Shake", client)) != null)
    {
        PbSetFloat(pb, "local_amplitude", intensity);
        PbSetFloat(pb, "duration", duration);
        PbSetFloat(pb, "frequency", frequency);
        EndMessage();
    }
}

public void OnGameFrame()
{
	if(!g_BlackholeEnable.BoolValue)
		return;
		
	for (int index = 0; index < g_Blackholes.Length; index++)
	{
		for (int client = 1; client <= MaxClients; client++)
		{
			if(IsClientInGame(client) && IsPlayerAlive(client))
			{
				if(IsValidEntity(g_Blackholes.Get(index)))
				{
					float clientPos[3], blackholePos[3];
					GetClientAbsOrigin(client, clientPos);
					GetEntPropVector(g_Blackholes.Get(index), Prop_Send, "m_vecOrigin", blackholePos);
					
					float distance = GetVectorDistance(clientPos, blackholePos);

					if(distance < 20.0)
					{
						if(g_ShakePlayer.BoolValue)
							ShakeScreen(client, g_ShakeIntensity.FloatValue, 0.1, g_ShakeFrequency.FloatValue);
									
						if(g_BlackholeSetting.IntValue == 1)
							SDKHooks_TakeDamage(client, g_Blackholes.Get(index), g_Blackholes.Get(index), g_BlackholeDamage.FloatValue, DMG_DROWN, -1);
					}
					if(distance < g_MinimumDistance.FloatValue)
					{
						if(g_ShakePlayer.BoolValue)
							ShakeScreen(client, g_ShakeIntensity.FloatValue, 0.1, g_ShakeFrequency.FloatValue);
							
						SetEntPropEnt(client, Prop_Data, "m_hGroundEntity", -1);

						//SetEntityGravity(client, 0.0);
						float direction[3];
						SubtractVectors(blackholePos, clientPos, direction);
						
						float gravityForce = FindConVar("sv_gravity").FloatValue * (((g_BlackholeForce.FloatValue * g_MinimumDistance.FloatValue / 50) * 20.0) / GetVectorLength(direction,true));
						gravityForce = gravityForce / 20.0;
						
						NormalizeVector(direction, direction);
						ScaleVector(direction, gravityForce);
						
						float playerVel[3];
						GetEntPropVector(client, Prop_Data, "m_vecVelocity", playerVel);
						NegateVector(direction);
						ScaleVector(direction, distance / 300);
						SubtractVectors(playerVel, direction, direction);
						TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, direction);
					}
				}
			}
		}
	
		if(g_BlackholeProps.BoolValue)
			PushToBlackHole(index, "prop_physics*");
			
		if(g_BlackholeWeapons.BoolValue)
			PushToBlackHole(index, "weapon_*");
		
		if(g_BlackholeGrenades.BoolValue)
			PushToBlackHole(index, "hegrenade_projectile");

		if(g_BlackholeFlashbangs.BoolValue)
			PushToBlackHole(index, "flashbang_projectile");
	
		if(g_BlackholeSmokes.BoolValue)
			PushToBlackHole(index, "smokegrenade_projectile");
	}
}

void PushToBlackHole(int index, const char[] classname)
{
	int iEnt = MaxClients + 1;
	while((iEnt = FindEntityByClassname(iEnt, classname)) != -1)
	{
		float propPos[3], blackholePos[3];
		GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", propPos);
		GetEntPropVector(g_Blackholes.Get(index), Prop_Send, "m_vecOrigin", blackholePos);
		
		float distance = GetVectorDistance(propPos, blackholePos);
		if(distance > 20.0 && distance < g_MinimumDistance.FloatValue)
		{
			float direction[3];
			SubtractVectors(blackholePos, propPos, direction);
			
			float gravityForce = FindConVar("sv_gravity").FloatValue * (((g_BlackholeForce.FloatValue * g_MinimumDistance.FloatValue / 50) * 20.0) / GetVectorLength(direction,true));
			gravityForce = gravityForce / 20.0;
			
			NormalizeVector(direction, direction);
			ScaleVector(direction, gravityForce);
			
			float entityVel[3];
			GetEntPropVector(iEnt, Prop_Data, "m_vecVelocity", entityVel);
			NegateVector(direction);
			ScaleVector(direction, distance / 300);
			SubtractVectors(entityVel, direction, direction);
			TeleportEntity(iEnt, NULL_VECTOR, NULL_VECTOR, direction);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(!g_BlackholeEnable.BoolValue)
		return;
		
	if(StrEqual(classname, "decoy_projectile", false))
	{
		SDKHook(entity, SDKHook_SpawnPost, DecoySpawned);
		SDKHook(entity, SDKHook_TouchPost, DecoyTouchPost);
	}
}

public Action DecoySpawned(int entity)
{
	SetEntityModel(entity, "models/weapons/blackholedecoys/w_eq_decoy.mdl");
}

public Action DecoyTouchPost(int entity, int other)
{
	if(other == 0)
	{
		float vecPos[3], endPoint[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vecPos);
		endPoint = vecPos;
		endPoint[2] = vecPos[2] - 3.0;

		Handle trace = TR_TraceRayFilterEx(vecPos, endPoint, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilterNotSelf, entity);
		
		if(TR_DidHit(trace))
		{
			RequestFrame(FrameCallback, entity);
		}
	}
}

public void FrameCallback(any entity)
{
	float vel[3] =  { 0.0, 0.0, 300.0 };
	vel[2] = g_BounceVelocity.FloatValue;
	TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vel);
	CreateTimer(0.5, Timer_BlackHole, entity);
	SDKUnhook(entity, SDKHook_TouchPost, DecoyTouchPost);
}

public Action Timer_BlackHole(Handle timer, any entity)
{
	float nadeOrigin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", nadeOrigin);
	AcceptEntityInput(entity, "Kill");
	
	char particleEffect[PLATFORM_MAX_PATH];
	g_ParticleEffect.GetString(particleEffect, sizeof(particleEffect));
	int particle = CreateEntityByName("info_particle_system");
	DispatchKeyValue(particle , "start_active", "0");
	DispatchKeyValue(particle , "effect_name", particleEffect);
	DispatchSpawn(particle);
	TeleportEntity(particle, nadeOrigin, NULL_VECTOR,NULL_VECTOR);
	ActivateEntity(particle);
	AcceptEntityInput(particle, "Start");
	g_Blackholes.Push(particle);
	EmitAmbientSoundAny("misc/blackholedecoys/blackhole.mp3", nadeOrigin, particle,_,_,BLACKHOLE_VOLUME);
	
	int volumeIndex = g_Blackholes.FindValue(particle);
	DataPack pack;
	CreateDataTimer(g_BlackholeDuration.FloatValue, Timer_Duration, pack);
	pack.WriteCell(particle);
	pack.WriteCell(nadeOrigin[0]);
	pack.WriteCell(nadeOrigin[1]);
	pack.WriteCell(nadeOrigin[2]);
	pack.WriteCell(volumeIndex);
	
}

public Action Timer_Duration(Handle timer, DataPack pack)
{
	pack.Reset();
	float nadeOrigin[3];
	int particle = pack.ReadCell();
	nadeOrigin[0] = pack.ReadCell();
	nadeOrigin[1] = pack.ReadCell();
	nadeOrigin[2] = pack.ReadCell();
	int volumeIndex = pack.ReadCell();
	
	int index = g_Blackholes.FindValue(particle);
	if(index >= 0)
		g_Blackholes.Erase(index);
	AcceptEntityInput(particle, "Kill");
	
	DataPack packFade;
	CreateDataTimer(0.2, Timer_Fade, packFade, TIMER_REPEAT);
	packFade.WriteCell(particle);
	packFade.WriteCell(nadeOrigin[0]);
	packFade.WriteCell(nadeOrigin[1]);
	packFade.WriteCell(nadeOrigin[2]);
	packFade.WriteCell(volumeIndex);
	
}

public Action Timer_Fade(Handle timer, DataPack pack)
{
	pack.Reset();
	float nadeOrigin[3];
	int particle = pack.ReadCell();
	nadeOrigin[0] = pack.ReadCell();
	nadeOrigin[1] = pack.ReadCell();
	nadeOrigin[2] = pack.ReadCell();
	int volumeIndex = pack.ReadCell();
	g_BlackholeVolume[volumeIndex] -= 0.25;
	EmitAmbientSoundAny("misc/blackholedecoys/blackhole.mp3", nadeOrigin, particle, _, SND_CHANGEVOL, g_BlackholeVolume[volumeIndex]);
	if(g_BlackholeVolume[volumeIndex] < 0.0)
	{
		StopSoundAny(particle, SNDCHAN_STATIC, "misc/blackholedecoys/blackhole.mp3");
		g_BlackholeVolume[volumeIndex] = BLACKHOLE_VOLUME;
		KillTimer(timer);
	}	
}
	
public bool TraceFilterNotSelf(int entityhit, int mask, any entity)
{
	if(entity == 0 && entityhit != entity)
		return true;
	
	return false;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if(!g_BlackholeEnable.BoolValue)
		return Plugin_Continue;
		
	int client = GetClientOfUserId(event.GetInt("userid"));
	g_PVMid[client] = Weapon_GetViewModelIndex(client, -1);
	
	return Plugin_Continue;
}

int Weapon_GetViewModelIndex(int client, int sIndex)
{
    while ((sIndex = FindEntityByClassname2(sIndex, "predicted_viewmodel")) != -1)
    {
        int Owner = GetEntPropEnt(sIndex, Prop_Send, "m_hOwner");
        
        if (Owner != client)
            continue;
        
        return sIndex;
    }
    return -1;
}
// Get entity name
int FindEntityByClassname2(int startEnt, char[] classname)
{
    while (startEnt > -1 && !IsValidEntity(startEnt)) startEnt--;
    return FindEntityByClassname(startEnt, classname);
}  

stock void AddMaterialsFromFolder(char path[PLATFORM_MAX_PATH])
{
	DirectoryListing dir = OpenDirectory(path, true);
	if(dir != INVALID_HANDLE)
	{
		char buffer[PLATFORM_MAX_PATH];
		FileType type;
		
		while(dir.GetNext(buffer, PLATFORM_MAX_PATH, type))
		{
			if(type == FileType_File && ((StrContains(buffer, ".vmt", false) != -1) || (StrContains(buffer, ".vtf", false) != -1) && !(StrContains(buffer, ".ztmp", false) != -1)))
			{
				char fullPath[PLATFORM_MAX_PATH];
				
				Format(fullPath, sizeof(fullPath), "%s%s", path, buffer);
				
				AddFileToDownloadsTable(fullPath);
				PrecacheModel(fullPath);
			}
		}
	}
}

stock void AddModelsFromFolder(char path[PLATFORM_MAX_PATH])
{
	DirectoryListing dir = OpenDirectory(path, true);
	if(dir != INVALID_HANDLE)
	{
		char buffer[PLATFORM_MAX_PATH];
		FileType type;
		
		while(dir.GetNext(buffer, PLATFORM_MAX_PATH, type))
		{
			if(type == FileType_File && (StrContains(buffer, ".mdl", false) != -1 && !StrContains(buffer, ".ztmp", false) != -1))
			{
				char fullPath[PLATFORM_MAX_PATH];
				Format(fullPath, sizeof(fullPath), "%s%s", path, buffer);
				
				AddFileToDownloadsTable(fullPath);
				PrecacheModel(fullPath);
			}
			else if(type == FileType_File && (StrContains(buffer, ".vtx", false) != -1 || StrContains(buffer, ".vvd", false) != -1 || StrContains(buffer, ".phy", false) != -1))
			{
				char fullPath[PLATFORM_MAX_PATH];
				Format(fullPath, sizeof(fullPath), "%s%s", path, buffer);
				AddFileToDownloadsTable(fullPath);
			}
		}
	}
}

public void OnClientWeaponSwitchPost(int client, int weaponid)
{
    char weapon[64];
    GetEntityClassname(weaponid, weapon,sizeof(weapon));
    if(StrEqual(weapon, "weapon_decoy"))
    {
        SetEntProp(weaponid, Prop_Send, "m_nModelIndex", 0);
        SetEntProp(g_PVMid[client], Prop_Send, "m_nModelIndex", g_iViewModelIndex);
    }
}

stock void PrecacheEffect(const char[] sEffectName)
{
	static int table = INVALID_STRING_TABLE;
	
	if (table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("EffectDispatch");
	}
	
	bool save = LockStringTables(false);
	AddToStringTable(table, sEffectName);
	LockStringTables(save);
}

stock void PrecacheParticleEffect(const char[] sEffectName)
{
	static int table = INVALID_STRING_TABLE;
	
	if (table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("ParticleEffectNames");
	}
	
	bool save = LockStringTables(false);
	AddToStringTable(table, sEffectName);
	LockStringTables(save);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponSwitchPost, OnClientWeaponSwitchPost);  
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_WeaponSwitchPost, OnClientWeaponSwitchPost);  
}

public void OnMapStart()
{
	g_iViewModelIndex = PrecacheModel("models/weapons/blackholedecoys/v_eq_decoy.mdl");
	PrecacheModel("models/weapons/blackholedecoys/w_eq_decoy_thrown.mdl");
	PrecacheModel("models/weapons/blackholedecoys/w_eq_decoy.mdl");
	//VIEWMODEL
	AddFileToDownloadsTable("models/weapons/blackholedecoys/v_eq_decoy.dx90.vtx");
	AddFileToDownloadsTable("models/weapons/blackholedecoys/v_eq_decoy.dx80.vtx");
	AddFileToDownloadsTable("models/weapons/blackholedecoys/v_eq_decoy.mdl");
	AddFileToDownloadsTable("models/weapons/blackholedecoys/v_eq_decoy.vvd");
	AddFileToDownloadsTable("models/weapons/blackholedecoys/v_eq_decoy.sw.vtx");
	
	//GRENADE MODEL
	AddFileToDownloadsTable("models/weapons/blackholedecoys/w_eq_decoy.dx90.vtx");
	AddFileToDownloadsTable("models/weapons/blackholedecoys/w_eq_decoy.dx80.vtx");
	AddFileToDownloadsTable("models/weapons/blackholedecoys/w_eq_decoy.mdl");
	AddFileToDownloadsTable("models/weapons/blackholedecoys/w_eq_decoy.phy");
	AddFileToDownloadsTable("models/weapons/blackholedecoys/w_eq_decoy.vvd");
	AddFileToDownloadsTable("models/weapons/blackholedecoys/w_eq_decoy.sw.vtx");
	
	//MATERIALS
	AddFileToDownloadsTable("materials/blackholedecoys/effects/electric1.vmt");
	AddFileToDownloadsTable("materials/blackholedecoys/effects/electric1.vtf");
	
	AddFileToDownloadsTable("materials/blackholedecoys/particle/particle_decals/snow_crater_1.vmt");
	AddFileToDownloadsTable("materials/blackholedecoys/particle/particle_decals/snow_crater_1.vtf");
	
	AddMaterialsFromFolder("materials/models/weapons/v_models/blackholedecoys/hydragrenade/");
	
	//PARTICLES
	AddFileToDownloadsTable("particles/blackholedecoys/blackhole.pcf");
	
	//SOUND
	AddFileToDownloadsTable("sound/misc/blackholedecoys/blackhole.mp3");
	
	//Precaching
	PrecacheGeneric("particles/blackholedecoys/blackhole.pcf",true);
	
	PrecacheModel("materials/blackholedecoys/effects/electric1.vmt");
	PrecacheModel("materials/blackholedecoys/effects/electric1.vtf");
	
	PrecacheModel("materials/blackholedecoys/particle/particle_decals/snow_crater_1.vmt");
	PrecacheModel("materials/blackholedecoys/particle/particle_decals/snow_crater_1.vtf");
	
	PrecacheEffect("ParticleEffect");
	PrecacheParticleEffect("blackhole");
	PrecacheSoundAny("misc/blackholedecoys/blackhole.mp3", true);
}
