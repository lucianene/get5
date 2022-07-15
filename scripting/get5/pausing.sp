public bool Pauseable() {
  return g_GameState >= Get5State_KnifeRound && g_PausingEnabledCvar.BoolValue;
}

public Action Command_TechPause(int client, int args) {
  if (!g_AllowTechPauseCvar.BoolValue || !Pauseable() || IsPaused()) {
    return Plugin_Handled;
  }

  if (client == 0) {
    Pause(PauseType_Admin);
    EventLogger_PauseCommand(MatchTeam_TeamNone, PauseType_Admin);
    LogDebug("Calling Get5_OnMatchPaused(team=%d, pauseReason=%d)", MatchTeam_TeamNone,
             PauseType_Admin);
    Call_StartForward(g_OnMatchPaused);
    Call_PushCell(MatchTeam_TeamNone);
    Call_PushCell(PauseType_Admin);
    Call_Finish();
    Get5_MessageToAll("%t", "AdminForceTechPauseInfoMessage");
    return Plugin_Handled;
  }

  MatchTeam team = GetClientMatchTeam(client);
  int maxTechPauses = g_MaxTechPauseCvar.IntValue;  
  int maxTechPauseTime = g_MaxTechPauseTime.IntValue;

  g_TeamReadyForUnpause[MatchTeam_Team1] = false;
  g_TeamReadyForUnpause[MatchTeam_Team2] = false;
  
  // Only set these if we are a non-zero value.
  if (maxTechPauses > 0 || maxTechPauseTime > 0) {
    int timeLeft = maxTechPauseTime - g_TechPausedTimeOverride[team];
    // Don't allow more than one tech pause per time.
    if (g_TeamGivenTechPauseCommand[MatchTeam_Team1] || g_TeamGivenTechPauseCommand[MatchTeam_Team2]) {
      return Plugin_Handled;
    }
    if (maxTechPauses > 0 && g_TeamTechPausesUsed[team] >= maxTechPauses) {
      Get5_MessageToAll("%t", "TechPauseNoTimeRemaining", g_FormattedTeamNames[team]);
      return Plugin_Handled;
    } else if (maxTechPauseTime > 0 && timeLeft <= 0) {
      Get5_MessageToAll("%t", "TechPauseNoTimeRemaining", g_FormattedTeamNames[team]);
      return Plugin_Handled;
    } else {
      g_TeamGivenTechPauseCommand[team] = true;
      // Only create a new timer when the old one expires.
      if (g_TechPausedTimeOverride[team] == 0) {
        CreateTimer(1.0, Timer_TechPauseOverrideCheck, team, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
      }
      // Once we run out of time, subtract a tech pause used and reset the timer.
      g_TeamTechPausesUsed[team]++;
      int pausesLeft = maxTechPauses - g_TeamTechPausesUsed[team];
      Get5_MessageToAll("%t", "TechPausePausesRemaining", g_FormattedTeamNames[team], pausesLeft);
    }
  }
  
  Pause(PauseType_Tech);
  EventLogger_PauseCommand(team, PauseType_Tech);
  LogDebug("Calling Get5_OnMatchPaused(team=%d, pauseReason=%d)", team, PauseType_Tech);
  Call_StartForward(g_OnMatchPaused);
  Call_PushCell(team);
  Call_PushCell(PauseType_Tech);
  Call_Finish();
  Get5_MessageToAll("%t", "MatchTechPausedByTeamMessage", client);

  return Plugin_Handled;
}

public Action Command_Pause(int client, int args) {
  if (!Pauseable() || IsPaused()) {
    return Plugin_Handled;
  }


  if (client == 0) {
    Pause(PauseType_Admin);
    EventLogger_PauseCommand(MatchTeam_TeamNone, PauseType_Admin);
    LogDebug("Calling Get5_OnMatchPaused(team=%d, pauseReason=%d)", MatchTeam_TeamNone,
             PauseType_Admin);
    Call_StartForward(g_OnMatchPaused);
    Call_PushCell(MatchTeam_TeamNone);
    Call_PushCell(PauseType_Admin);
    Call_Finish();
    Get5_MessageToAll("%t", "AdminForcePauseInfoMessage");
    return Plugin_Handled;
  }

  MatchTeam team = GetClientMatchTeam(client);
  int maxPauses = g_MaxPausesCvar.IntValue;
  char pausePeriodString[32];
  if (g_ResetPausesEachHalfCvar.BoolValue) {
    Format(pausePeriodString, sizeof(pausePeriodString), " %t", "PausePeriodSuffix");
  }

  if (maxPauses > 0 && g_TeamPausesUsed[team] >= maxPauses && IsPlayerTeam(team)) {
    Get5_Message(client, "%t", "MaxPausesUsedInfoMessage", maxPauses, pausePeriodString);
    return Plugin_Handled;
  }

  int maxPauseTime = g_MaxPauseTimeCvar.IntValue;
  if (maxPauseTime > 0 && g_TeamPauseTimeUsed[team] >= maxPauseTime && IsPlayerTeam(team)) {
    Get5_Message(client, "%t", "MaxPausesTimeUsedInfoMessage", maxPauseTime, pausePeriodString);
    return Plugin_Handled;
  }

  g_TeamReadyForUnpause[MatchTeam_Team1] = false;
  g_TeamReadyForUnpause[MatchTeam_Team2] = false;

  int pausesLeft = 1;
  if (g_MaxPausesCvar.IntValue > 0 && IsPlayerTeam(team)) {
    // Update the built-in convar to ensure correct max amount is displayed
    ServerCommand("mp_team_timeout_max %d", g_MaxPausesCvar.IntValue);
    pausesLeft = g_MaxPausesCvar.IntValue - g_TeamPausesUsed[team] - 1;
  }

  // If the pause will need explicit resuming, we will create a timer to poll the pause status.
  bool need_resume = Pause(PauseType_Tactical, g_FixedPauseTimeCvar.IntValue, MatchTeamToCSTeam(team), pausesLeft);
  EventLogger_PauseCommand(team, PauseType_Tactical);
  LogDebug("Calling Get5_OnMatchPaused(team=%d, pauseReason=%d)", team, PauseType_Tactical);
  Call_StartForward(g_OnMatchPaused);
  Call_PushCell(team);
  Call_PushCell(PauseType_Tactical);
  Call_Finish();

  if (IsPlayer(client)) {
    Get5_MessageToAll("%t", "MatchPausedByTeamMessage", client);
  }

  if (IsPlayerTeam(team)) {
    if (need_resume) {
      g_PauseTimeUsed = g_PauseTimeUsed + g_FixedPauseTimeCvar.IntValue - 1;
      CreateTimer(1.0, Timer_PauseTimeCheck, team, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
      // This timer is used to only fire off the Unpause event.
      CreateTimer(1.0, Timer_UnpauseEventCheck, team, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }

    g_TeamPausesUsed[team]++;

    pausePeriodString = "";
    if (g_ResetPausesEachHalfCvar.BoolValue) {
      Format(pausePeriodString, sizeof(pausePeriodString), " %t", "PausePeriodSuffix");
    }

    if (g_MaxPausesCvar.IntValue > 0) {
      if (pausesLeft == 1 && g_MaxPausesCvar.IntValue > 0) {
        Get5_MessageToAll("%t", "OnePauseLeftInfoMessage", g_FormattedTeamNames[team], pausesLeft,
                          pausePeriodString);
      } else if (g_MaxPausesCvar.IntValue > 0) {
        Get5_MessageToAll("%t", "PausesLeftInfoMessage", g_FormattedTeamNames[team], pausesLeft,
                          pausePeriodString);
      }
    }
  }

  return Plugin_Handled;
}

public Action Timer_TechPauseOverrideCheck(Handle timer, int data) {
  MatchTeam team = view_as<MatchTeam>(data);
  int maxTechPauseTime = g_MaxTechPauseTime.IntValue;
  if (!Pauseable()) {
    g_TechPausedTimeOverride[team] = 0;
    g_TeamGivenTechPauseCommand[team] = false;
    return Plugin_Stop;
  }

  // Unlimited Tech Pause so no one can unpause unless both teams agree.
  if (maxTechPauseTime <= 0) {
    g_TechPausedTimeOverride[team] = 0;
    return Plugin_Stop;
  }

  // This condition will only be hit when we resume from a pause.
  if (!g_TeamGivenTechPauseCommand[team]) {
    g_TechPausedTimeOverride[team] = 0;
    return Plugin_Stop;
  }

  int timeLeft = maxTechPauseTime - g_TechPausedTimeOverride[team];

  // Only count down if we're still frozen, fit the right pause type
  // and the team who paused has not given the go ahead.
  if (InFreezeTime() && g_TeamGivenTechPauseCommand[team] && g_PauseType == PauseType_Tech && !g_TeamReadyForUnpause[team]) {
    LogDebug("Adding tech time used. Current time = %d", g_TechPausedTimeOverride[team]);
    g_TechPausedTimeOverride[team]++;

    // Every 30 seconds output a message with the time remaining before unpause.
    if (timeLeft != 0) {
      if (timeLeft >= 60 && timeLeft % 60 == 0) {
        timeLeft = timeLeft / 60;
        Get5_MessageToAll("%t", "TechPauseTimeRemainingMinutes", timeLeft);
      } else if (timeLeft <= 30 && (timeLeft % 30 == 0 || timeLeft == 10)) {
       Get5_MessageToAll("%t", "TechPauseTimeRemaining", timeLeft);
      }
    }

    if (timeLeft <= 0) {
      Get5_MessageToAll("%t", "TechPauseRunoutInfoMessage");
      return Plugin_Stop;
    }
  }

  // Someone can call pause during a round and will set this timer.
  // Keep running timer until we are paused.
  return Plugin_Continue;
}

public Action Timer_UnpauseEventCheck(Handle timer, int data) {
  if (!Pauseable()) {
    g_PauseTimeUsed = 0;
    return Plugin_Stop;
  }

  // Unlimited pause time.
  if (g_MaxPauseTimeCvar.IntValue <= 0) {
    // Reset state.
    g_PauseTimeUsed = 0;
    return Plugin_Stop;
  }

  if (!InFreezeTime()) {
    // Someone can call pause during a round and will set this timer.
    // Keep running timer until we are paused.
    return Plugin_Continue;
  } else {
    if (g_PauseTimeUsed <= 0) {
      MatchTeam team = view_as<MatchTeam>(data);
      EventLogger_UnpauseCommand(team);
      LogDebug("Calling Get5_OnMatchUnpaused(team=%d)", team);
      Call_StartForward(g_OnMatchUnpaused);
      Call_PushCell(team);
      Call_Finish();
      // Reset state
      g_PauseTimeUsed = 0;
      return Plugin_Stop;
    }
    g_PauseTimeUsed--;
    LogDebug("Subtracting time used. Current time = %d", g_PauseTimeUsed);
  }

  return Plugin_Continue;
}

public Action Timer_PauseTimeCheck(Handle timer, int data) {
  if (!Pauseable() || !IsPaused() || g_FixedPauseTimeCvar.BoolValue) {
    return Plugin_Stop;
  }
  int maxPauseTime = g_MaxPauseTimeCvar.IntValue;
  // Unlimited pause time.
  if (maxPauseTime <= 0) {
    return Plugin_Stop;
  }

  char pausePeriodString[32];
  if (g_ResetPausesEachHalfCvar.BoolValue) {
    Format(pausePeriodString, sizeof(pausePeriodString), " %t", "PausePeriodSuffix");
  }

  MatchTeam team = view_as<MatchTeam>(data);
  int timeLeft = maxPauseTime - g_TeamPauseTimeUsed[team];
  // Only count against the team's pause time if we're actually in the freezetime
  // pause and they haven't requested an unpause yet.
  if (InFreezeTime() && !g_TeamReadyForUnpause[team]) {
    g_TeamPauseTimeUsed[team]++;

    if (timeLeft == 10) {
      Get5_MessageToAll("%t", "PauseTimeExpiration10SecInfoMessage", g_FormattedTeamNames[team]);
    } else if (timeLeft % 30 == 0) {
      Get5_MessageToAll("%t", "PauseTimeExpirationInfoMessage", g_FormattedTeamNames[team],
                        timeLeft, pausePeriodString);
    }
  }
  if (timeLeft <= 0) {
    Get5_MessageToAll("%t", "PauseRunoutInfoMessage", g_FormattedTeamNames[team]);
    Unpause();
    return Plugin_Stop;
  }

  return Plugin_Continue;
}

public Action Command_Unpause(int client, int args) {
  if (!IsPaused())
    return Plugin_Handled;

  if (g_PauseType == PauseType_Admin && client != 0) {
    Get5_MessageToAll("%t", "UserCannotUnpauseAdmin");
    return Plugin_Handled;
  }

  // Let console force unpause
  if (client == 0) {
    // Remove any techpause conditions if an admin unpauses.
    if (g_PauseType == PauseType_Tech) {
      LOOP_TEAMS(team) {
      if (team != MatchTeam_TeamNone) {
          g_TeamGivenTechPauseCommand[team] = false;
          g_TechPausedTimeOverride[team] = 0;
        }
      }
    }
    
    Unpause();
    EventLogger_UnpauseCommand(MatchTeam_TeamNone);
    LogDebug("Calling Get5_OnMatchUnpaused(team=%d)", MatchTeam_TeamNone);
    Call_StartForward(g_OnMatchUnpaused);
    Call_PushCell(MatchTeam_TeamNone);
    Call_Finish();
    Get5_MessageToAll("%t", "AdminForceUnPauseInfoMessage");
    return Plugin_Handled;
  }

  // Check to see if we have a timeout that is timed. Otherwise, we need to
  // continue for unpausing. New pause type to avoid match restores failing.
  if (g_FixedPauseTimeCvar.BoolValue && g_PauseType == PauseType_Tactical) {
    return Plugin_Handled;
  }

  MatchTeam team = GetClientMatchTeam(client);
  g_TeamReadyForUnpause[team] = true;

  int maxTechPauseTime = g_MaxTechPauseTime.IntValue;

  // Get which team is currently tech paused.
  MatchTeam pausedTeam = MatchTeam_TeamNone;
  if (g_TeamGivenTechPauseCommand[MatchTeam_Team1]) {
    pausedTeam = MatchTeam_Team1;
  } else if (g_TeamGivenTechPauseCommand[MatchTeam_Team2]) {
    pausedTeam = MatchTeam_Team2;
  }
  
  if (g_PauseType == PauseType_Tech && maxTechPauseTime > 0) {
    if (g_TechPausedTimeOverride[pausedTeam] >= maxTechPauseTime) {
      Unpause();
      EventLogger_UnpauseCommand(team);
      LogDebug("Calling Get5_OnMatchUnpaused(team=%d)", team);
      Call_StartForward(g_OnMatchUnpaused);
      Call_PushCell(team);
      Call_Finish();
      if (IsPlayer(client)) {
        Get5_MessageToAll("%t", "MatchUnpauseInfoMessage", client);
      }
      if (pausedTeam != MatchTeam_TeamNone) {
        g_TeamGivenTechPauseCommand[pausedTeam] = false;
        g_TechPausedTimeOverride[pausedTeam] = 0;
      }
      return Plugin_Handled;
    }
  }

  if (g_TeamReadyForUnpause[MatchTeam_Team1] && g_TeamReadyForUnpause[MatchTeam_Team2]) {
    Unpause();
    EventLogger_UnpauseCommand(team);
    LogDebug("Calling Get5_OnMatchUnpaused(team=%d)", team);
    Call_StartForward(g_OnMatchUnpaused);
    Call_PushCell(team);
    Call_Finish();
    if (pausedTeam != MatchTeam_TeamNone) {
        g_TeamGivenTechPauseCommand[pausedTeam] = false;
        g_TechPausedTimeOverride[pausedTeam] = 0;
    }
    if (IsPlayer(client)) {
      Get5_MessageToAll("%t", "MatchUnpauseInfoMessage", client);
    }
  } else if (g_TeamReadyForUnpause[MatchTeam_Team1] && !g_TeamReadyForUnpause[MatchTeam_Team2]) {
    Get5_MessageToAll("%t", "WaitingForUnpauseInfoMessage", g_FormattedTeamNames[MatchTeam_Team1],
                      g_FormattedTeamNames[MatchTeam_Team2]);
  } else if (!g_TeamReadyForUnpause[MatchTeam_Team1] && g_TeamReadyForUnpause[MatchTeam_Team2]) {
    Get5_MessageToAll("%t", "WaitingForUnpauseInfoMessage", g_FormattedTeamNames[MatchTeam_Team2],
                      g_FormattedTeamNames[MatchTeam_Team1]);
  }

  return Plugin_Handled;
}
