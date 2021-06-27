#include <sourcemod>
#include <steamworks>

char szURLAddress[1024];
//char g_sLogFile[256];
bool g_bNoPrime[MAXPLAYERS+1];

char g_ApiToken[256];
char g_PlayHours[64];


public Plugin myinfo =
{
	name        =   "Block NoPrime",
	description =   "Ограничивает доступ к серверу NoPrime по часам.",
	version     =   "1.0.0",
    author      =   "Junkes & Wend4r",
	url         =   "https://hlmod.ru/"
};

public void OnPluginStart()
{
	//BuildPath(Path_SM, g_sLogFile, sizeof(g_sLogFile), "logs/BlockNoPrime.log");
	RegAdminCmd("sm_blockpr_reload", CommandReload, ADMFLAG_ROOT);

	for(int i = MaxClients + 1; --i;)
	{
		if(IsClientAuthorized(i))
		{
			OnClientAuthorized(i, NULL_STRING);
		}
	}

	GetConfig();
}

public void GetConfig()
{
	char sPath[128];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/blocknoprime.ini");
	KeyValues kv = new KeyValues("NoPrime");
	
	if (kv.ImportFromFile(sPath))
	{
		kv.GetString("SteamApi", g_ApiToken, sizeof(g_ApiToken));
		kv.GetString("PlayHours", g_PlayHours, sizeof(g_PlayHours));
		kv.Rewind();
	}
	else SetFailState("[BlockNoPrime] KeyValues Error!");

	delete kv;
}

public Action CommandReload(int iClient, int Args){
	GetConfig();
	PrintToServer("[BlockNoPrime] Конфиг перезагружен.");
	return Plugin_Handled;
}

public void OnClientAuthorized(int iClient, const char[] sAuth)
{
	if((g_bNoPrime[iClient] = (SteamWorks_HasLicenseForApp(iClient, 624820) != k_EUserHasLicenseResultHasLicense)))
	{
		if(!IsFakeClient(iClient))
		{
			char sSteamID[32];

			GetClientAuthId(iClient, AuthId_SteamID64, sSteamID, sizeof(sSteamID));

			FormatEx(szURLAddress, sizeof(szURLAddress), "http://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/?key=%s&steamid=%s&appids_filter[0]=730", g_ApiToken, sSteamID);

			Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, szURLAddress);

			SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(iClient));
			SteamWorks_SetHTTPCallbacks(hRequest, OnRequestCompleteSW);
			SteamWorks_SetHTTPRequestHeaderValue(hRequest, "User-Agent", "CS:GO");
			SteamWorks_SendHTTPRequest(hRequest);
		}
	}
}

int OnRequestCompleteSW(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int iUserID)
{
	SteamWorks_GetHTTPResponseBodyCallback(hRequest, OnHTTPBodyCallback, iUserID);

	hRequest.Close();
}

void OnHTTPBodyCallback(const char[] sJSON, int iUserID)
{
	int iClient = GetClientOfUserId(iUserID);

	if(iClient)
	{
		char sPlayTime[12];

		JSON_GetValue(sJSON, "playtime_forever", sPlayTime, sizeof(sPlayTime));
		//LogToFile(g_sLogFile, "Общее время = %s", sPlayTime);

		if(sPlayTime[0])
		{
			float flPlayTimeHources = StringToFloat(sPlayTime) / 60.0;
			float flPlayHours = StringToFloat(g_PlayHours);

			//LogToFile(g_sLogFile, "%N наиграл %.2f часов", iClient, flPlayTimeHources);

			if(flPlayTimeHources < flPlayHours)
			{
				KickClient(iClient, "У вас наигранно меньше %s часов. Всего %.2f / %s", g_PlayHours, flPlayTimeHources, g_PlayHours);
			}
		}
		else
		{
			KickClient(iClient, "У вас закрыт профиль в стиме. Откройте для игры на сервере");
		}
	}
}


int JSON_GetValue(const char[] sJSON, const char[] sParamName, char[] sValue = NULL_STRING, int iValueSize = 0)
{
	int iIndex = StrContains(sJSON, sParamName);

	if(iIndex != -1)
	{
		if(sJSON[(iIndex += strlen(sParamName) + 2)] == ' ')
		{
			iIndex++;
		}

		int i = 0;

		char iSumbol;

		if(sJSON[iIndex] == '{')
		{
			strcopy(sValue, iValueSize, "object");

			return iIndex;
		}
		else if(sJSON[iIndex] == '[')
		{
			strcopy(sValue, iValueSize, "array");
			
			return iIndex;
		}
		else if(sJSON[iIndex] == '"')        // Is string.
		{
			iIndex++;

			while(i != iValueSize)
			{
				if((iSumbol = sJSON[iIndex + i]) == '"')
				{
					if(i)
					{
						if(sJSON[iIndex + i - 1] == '\\')
						{
							iSumbol = '"';

							iIndex++;
							i--;
						}
						else
						{
							break;
						}
					}
					else
					{
						break;
					}
				}

				sValue[i++] = iSumbol;
			}

			sValue[i - view_as<int>(i == iValueSize)] = '\0';

			ReplaceString(sValue, i - view_as<int>(i == iValueSize), "\\n", "\n");
		}
		else
		{
			while(i != iValueSize && (iSumbol = sJSON[iIndex + i]) != ',' && iSumbol != ']' && iSumbol != '}')
			{
				sValue[i++] = iSumbol;
			}

			sValue[i - view_as<int>(i == iValueSize)] = '\0';
		}

		return i;
	}

	return 0;
}