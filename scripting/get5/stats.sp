public void Stats_PluginStart() {
    HookEvent("player_death", Stats_PlayerDeathEvent);
    HookEvent("player_hurt", Stats_DamageDealtEvent, EventHookMode_Pre);
    HookEvent("bomb_planted", Stats_BombPlantedEvent);
    HookEvent("bomb_defused", Stats_BombDefusedEvent);
}

public void Stats_InitSeries() {
    if (g_StatsKv != null) {
        delete g_StatsKv;
    }
    g_StatsKv = new KeyValues("Stats");

    char seriesType[32];
    Format(seriesType, sizeof(seriesType), "bo%d", MaxMapsToPlay(g_MapsToWin));
    g_StatsKv.SetString(STAT_SERIESTYPE, seriesType);
}

public void Stats_UpdateTeamScores() {
    GoToMap();
    char mapName[PLATFORM_MAX_PATH];
    GetCleanMapName(mapName, sizeof(mapName));
    g_StatsKv.SetString(STAT_MAPNAME, mapName);
    GoBackFromMap();

    GoToTeam(MatchTeam_Team1);
    g_StatsKv.SetNum(STAT_TEAMSCORE, CS_GetTeamScore(MatchTeamToCSTeam(MatchTeam_Team1)));
    g_StatsKv.SetString(STAT_TEAMNAME, g_TeamNames[MatchTeam_Team1]);
    GoBackFromTeam();

    GoToTeam(MatchTeam_Team2);
    g_StatsKv.SetNum(STAT_TEAMSCORE, CS_GetTeamScore(MatchTeamToCSTeam(MatchTeam_Team2)));
    g_StatsKv.SetString(STAT_TEAMNAME, g_TeamNames[MatchTeam_Team2]);
    GoBackFromTeam();
}

public void Stats_UpdatePlayerRounds() {
    for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i)) {
            MatchTeam team = GetClientMatchTeam(i);
            if (team == MatchTeam_Team1 || team == MatchTeam_Team2) {
                IncrementPlayerStat(i, STAT_ROUNDSPLAYED);

                if (g_RoundKills[i] == 2) {
                    IncrementPlayerStat(i, STAT_2K);
                } else if (g_RoundKills[i] == 3) {
                    IncrementPlayerStat(i, STAT_3K);
                } else if (g_RoundKills[i] == 4) {
                    IncrementPlayerStat(i, STAT_4K);
                } else if (g_RoundKills[i] == 5) {
                    IncrementPlayerStat(i, STAT_5K);
                }

                GoToPlayer(i);
                char name[MAX_NAME_LENGTH];
                GetClientName(i, name, sizeof(name));
                g_StatsKv.SetString(STAT_NAME, name);
                GoBackFromPlayer();
            }
        }
    }
}

public void Stats_UpdateMapScore(MatchTeam winner) {
    GoToMap();

    char winnerString[16];
    GetTeamString(winner, winnerString, sizeof(winnerString));

    g_StatsKv.SetString(STAT_MAPWINNER, winnerString);
    g_StatsKv.SetString(STAT_DEMOFILENAME, g_DemoFileName);

    GoBackFromMap();
}

public void Stats_SeriesEnd(MatchTeam winner) {
    char winnerString[16];
    GetTeamString(winner, winnerString, sizeof(winnerString));
    g_StatsKv.SetString(STAT_SERIESWINNER, winnerString);
}

public Action Stats_PlayerDeathEvent(Event event, const char[] name, bool dontBroadcast) {
    if (g_GameState == GameState_Live) {
        int victim = GetClientOfUserId(event.GetInt("userid"));
        int attacker = GetClientOfUserId(event.GetInt("attacker"));
        int assister = GetClientOfUserId(event.GetInt("assister"));
        bool headshot = event.GetBool("headshot");

        bool validAttacker = IsValidClient(attacker);
        bool validVictim = IsValidClient(victim);

        if (validVictim) {
            IncrementPlayerStat(victim, STAT_DEATHS);
        }

        if (validAttacker) {
            if (HelpfulAttack(attacker, victim)) {
                g_RoundKills[attacker]++;
                IncrementPlayerStat(attacker, STAT_KILLS);
                if (headshot)
                    IncrementPlayerStat(attacker, STAT_HEADSHOT_KILLS);
                if (IsValidClient(assister))
                    IncrementPlayerStat(assister, STAT_ASSISTS);
            } else {
                IncrementPlayerStat(attacker, STAT_TEAMKILLS);
            }
        }
    }
}

public Action Stats_DamageDealtEvent(Event event, const char[] name, bool dontBroadcast) {
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    bool validAttacker = IsValidClient(attacker);
    bool validVictim = IsValidClient(victim);

    if (validAttacker && validVictim) {
        int preDamageHealth = GetClientHealth(victim);
        int damage = event.GetInt("dmg_health");
        int postDamageHealth = event.GetInt("health");

        // this maxes the damage variables at 100,
        // so doing 50 damage when the player had 2 health
        // only counts as 2 damage.
        if (postDamageHealth == 0) {
            damage += preDamageHealth;
        }

        AddToPlayerStat(attacker, STAT_DAMAGE, damage);
    }
}

public Action Stats_BombPlantedEvent(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client)) {
        IncrementPlayerStat(client, STAT_BOMBPLANTS);
    }
}

public Action Stats_BombDefusedEvent(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client)) {
        IncrementPlayerStat(client, STAT_BOMBDEFUSES);
    }
}

static int GetPlayerStat(int client, const char[] field) {
    GoToPlayer(client);
    int value = g_StatsKv.GetNum(field);
    GoBackFromPlayer();
    return value;
}

static void SetPlayerStat(int client, const char[] field, int newValue) {
    GoToPlayer(client);
    g_StatsKv.SetNum(field, newValue);
    GoBackFromPlayer();
}

static void AddToPlayerStat(int client, const char[] field, int delta) {
    int value = GetPlayerStat(client, field);
    SetPlayerStat(client, field, value + delta);
}

static void IncrementPlayerStat(int client, const char[] field) {
    AddToPlayerStat(client, field, 1);
}

static void GoToMap() {
    char mapNumberString[32];
    Format(mapNumberString, sizeof(mapNumberString), "map%d", GetMapStatsNumber());
    g_StatsKv.JumpToKey(mapNumberString, true);
}

static void GoBackFromMap() {
    g_StatsKv.GoBack();
}

static void GoToTeam(MatchTeam team) {
    GoToMap();

    if (team == MatchTeam_Team1)
        g_StatsKv.JumpToKey("team1", true);
    else
        g_StatsKv.JumpToKey("team2", true);
}

static void GoBackFromTeam() {
    GoBackFromMap();
    g_StatsKv.GoBack();
}

static void GoToPlayer(int client) {
    MatchTeam team = GetClientMatchTeam(client);
    GoToTeam(team);

    char auth[AUTH_LENGTH];
    GetClientAuthId(client, AuthId_SteamID64, auth, sizeof(auth));
    g_StatsKv.JumpToKey(auth, true);
}

static void GoBackFromPlayer() {
    GoBackFromTeam();
    g_StatsKv.GoBack();
}

public int GetMapStatsNumber() {
    int x = GetMapNumber();
    if (g_MapChangePending) {
        return x;
    } else {
        return x + 1;
    }
}
