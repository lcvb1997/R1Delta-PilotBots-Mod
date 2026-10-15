//=========================================================
// Pilot Bots: server entry point (R1Delta autorun, runs after the map's scripts are loaded)
//
// Loads the bot manager and brain (mp/_pilotbots_manager.nut, mp/_pilotbots_ai.nut) and adapts the
// stock game scripts to managed bots from the outside: wrapping global functions, adding callbacks
// and answering two convars. The mod used to ship changed copies of _mapspawn_mp.nut,
// _base_gametype.nut, class_titan.nut, class_wallrun.nut and _titan_health.nut; other mods that ship
// their own copy of those files (e.g. Frontier Overhaul) replaced ours and broke the bots, or ours
// replaced theirs. Now those files stay whatever the game or the other mod has.
//
// _base_gametype.nut is loaded with IncludeScript into the root table, so its functions are looked
// up by name on every call and a wrapper assigned there takes their place. Functions of files loaded
// with IncludeFile are only reachable through Globalize, so only those are wrapped.
// Everything here lives in the root table (::) because the wrappers run from other scripts' scopes.
//=========================================================

//---------------------------------------------------------
// Older copies of the bot scripts
//---------------------------------------------------------
// Another mod may bundle an older copy of the bot scripts as mp/_bot_manager.nut and mp/_bot_ai.nut
// and include them from its own _mapspawn_mp.nut. Their callbacks have the same names as ours; they
// are removed before ours load so only one bot manager runs.
::PilotBots_CallbackNames <- {
	BotManager_OnClientConnected = true,
	BotManager_OnClientDisconnected = true,
	BotManager_OnMatchStateEnter = true,
	BotAI_OnPlayerRespawned = true,
	BotAI_OnPlayerDamaged = true,
	BotAI_OnTitanEject = true,
	BotAI_OnRodeoStarted = true,
	BotAI_DebugSpawnDeath = true,
}

::PilotBots_RemoveNamedCallbacks <- function( callbacks )
{
	local remove = []
	foreach ( name, _ in callbacks )
	{
		if ( name in PilotBots_CallbackNames )
			remove.append( name )
	}
	foreach ( name in remove )
		delete callbacks[name]
}

::PilotBots_RemoveOlderBotScripts <- function()
{
	local found = "BotManagerEnabledForMode" in getroottable()
	if ( "onClientConnectedCallbacks" in level && "BotManager_OnClientConnected" in level.onClientConnectedCallbacks )
		found = true
	if ( "onPlayerRespawnedCallbacks" in level && "BotAI_OnPlayerRespawned" in level.onPlayerRespawnedCallbacks )
		found = true
	if ( !found )
	{
		PilotBots_Log( "no older copy of the bot scripts loaded" )
		return
	}

	PilotBots_Log( "an older copy of the bot scripts was loaded; replacing it" )
	local named = [ "onClientConnectedCallbacks", "onClientDisconnectingCallbacks", "onPlayerRespawnedCallbacks",
		"onTitanEjectCallbacks", "onRodeoStartedCallbacks", "onPlayerKilledCallbacks" ]
	foreach ( field in named )
	{
		if ( field in level )
			PilotBots_RemoveNamedCallbacks( level[field] )
	}
	if ( "gameStateFunctions" in level )
	{
		foreach ( callbacks in level.gameStateFunctions )
			PilotBots_RemoveNamedCallbacks( callbacks )
	}
	if ( "damageCallbacks" in level && "player" in level.damageCallbacks )
	{
		local callbacks = level.damageCallbacks["player"]
		for ( local i = callbacks.len() - 1; i >= 0; i-- )
		{
			if ( FunctionToString( callbacks[i].func ) in PilotBots_CallbackNames )
				callbacks.remove( i )
		}
	}
	foreach ( name in [ "IsManagedBot", "BotManagerEnabledForMode", "GetBotFillTarget", "BotRandomizeLoadouts" ] )
	{
		if ( name in getroottable() )
			delete getroottable()[name]
	}
}

// The game writes no console log; pilotbots.dll's PilotBotsLog appends to r1delta\bin_delta\pilotbots.log.
// A script error stops this file where it happens, so each step logs when it is done.
::PilotBots_Log <- function( text )
{
	printt( "PilotBots: " + text )
	if ( "PilotBotsLog" in getroottable() )
		PilotBotsLog( text )
}

PilotBots_Log( "autorun start, map " + GetMapName() )
// The lobby never had the bot scripts (its _mapspawn doesn't load the match scripts they rely on).
if ( IsLobby() )
{
	PilotBots_Log( "lobby: bot scripts not loaded" )
	return
}

// Frontier Overhaul's Hologram decoy is an npc_soldier that copies its owner's anti-titan weapon and is set
// up for rockets. When it spots a titan, EnemyChanged_Rocket (mp/_ai_soldiers.nut) tries to hand it that
// weapon, which fails on the decoy: an "Internal Server script error" each time. Decoys are skipped (they
// never shoot anyway). Only applies where that function exists, i.e. with Frontier Overhaul installed.
if ( "EnemyChanged_Rocket" in getroottable() && !( "PilotBots_Orig_EnemyChanged_Rocket" in getroottable() ) )
{
	::PilotBots_Orig_EnemyChanged_Rocket <- EnemyChanged_Rocket
	::EnemyChanged_Rocket <- function( soldier )
	{
		if ( IsValid( soldier ) && "isHologram" in soldier.s )
			return
		return PilotBots_Orig_EnemyChanged_Rocket( soldier )
	}
	PilotBots_Log( "Frontier Overhaul hologram rocket fix installed" )
}

try
{
	PilotBots_RemoveOlderBotScripts()
	IncludeFile( "mp/_pilotbots_manager" )
	IncludeFile( "mp/_pilotbots_ai" )
	PilotBots_Log( "bot scripts loaded; BotManagerEnabledForMode global: " + ( "BotManagerEnabledForMode" in getroottable() ) + ", IsManagedBot global: " + ( "IsManagedBot" in getroottable() ) )
	if ( !BotManagerEnabledForMode() )
	{
		PilotBots_Log( "bot manager disabled for this mode" )
		return
	}
	// A map without _base_gametype.nut has none of the functions wrapped below.
	if ( !( "RespawnTitanPilot" in getroottable() ) )
	{
		PilotBots_Log( "no match scripts on this map; wrappers skipped" )
		return
	}
}
catch ( e )
{
	PilotBots_Log( "ERROR loading the bot scripts: " + e )
	return
}

//---------------------------------------------------------
// Convars the stock scripts check for bots
//---------------------------------------------------------
// bot_kick_on_death (PostDeathThread): managed bots stay in the match and respawn like players.
// bot_randomize_loadout (class_titan/class_wallrun): managed bots roll their loadout once on connect
// (BotRandomizeLoadouts) and keep it. Both are cheat convars, so they are answered here instead of set.
::PilotBots_Orig_GetConVarBool <- GetConVarBool
::PilotBots_Orig_GetConVarInt <- GetConVarInt

::GetConVarBool <- function( name )
{
	if ( name == "bot_kick_on_death" )
		return false
	return PilotBots_Orig_GetConVarBool( name )
}

::GetConVarInt <- function( name )
{
	if ( name == "bot_randomize_loadout" || name == "bot_kick_on_death" )
		return 0
	return PilotBots_Orig_GetConVarInt( name )
}

//---------------------------------------------------------
// Spawning
//---------------------------------------------------------
// Bots skip the spawn point search in RespawnTitanPilot, and without a spawn point RespawnPlayer uses
// the map's default spawn, the same for both teams. Pick the spawn a human would get (a bot's first
// spawn, including bots added mid-match, at its team's base; later ones dynamic) and move the bot
// there as it respawns (PilotBots_OnPlayerRespawned).
::PilotBots_Orig_RespawnTitanPilot <- RespawnTitanPilot

::RespawnTitanPilot <- function( player, rematchOrigin = null, retryToken = null, spawnDataIndex = null, request = null )
{
	if ( IsManagedBot( player ) && rematchOrigin == null )
	{
		local spawnPoint = null
		if ( ShouldStartSpawn( player ) || !player.s.respawnCount )
			spawnPoint = FindStartSpawnPoint( player, false )
		if ( !spawnPoint )
			spawnPoint = FindSpawnPoint( player, false )
		player.s.pilotBotsSpawnPoint <- spawnPoint
		player.s.pilotBotsSpawnTime <- Time()
	}
	return PilotBots_Orig_RespawnTitanPilot( player, rematchOrigin, retryToken, spawnDataIndex, request )
}

// The connection callback spawns a connecting bot (DecideRespawnPlayer) and then moves it next to
// the first player, which is meant for debug bots. Managed bots are spawned a frame later instead,
// and not at all before Prematch: GameStartSpawnPlayers spawns everyone together then.
// A campaign intro (CinematicIntro, up to Prematch) never spawns a connecting player through here:
// the first call is the intro's own (SpawnPlayerOnGround on Angel City), which reads the spawn
// position right after, so it must spawn now. A frame late, the bot looked like it had walked away
// and lost its intro at once.
::PilotBots_Orig_DecideRespawnPlayer <- DecideRespawnPlayer

::DecideRespawnPlayer <- function( player, rematchOrigin = null )
{
	if ( IsManagedBot( player ) && !( "pilotBotsConnected" in player.s ) && Flag( "CinematicIntro" ) && GetGameState() <= eGameState.Prematch )
		player.s.pilotBotsConnected <- true
	if ( IsManagedBot( player ) && !( "pilotBotsConnected" in player.s ) )
	{
		player.s.pilotBotsConnected <- true
		thread PilotBots_SpawnAfterConnect( player )
		return false
	}
	return PilotBots_Orig_DecideRespawnPlayer( player, rematchOrigin )
}

::PilotBots_SpawnAfterConnect <- function( player )
{
	player.EndSignal( "OnDestroy" )
	wait 0
	if ( GetGameState() < eGameState.Prematch || IsAlive( player ) )
		return
	PilotBots_Orig_DecideRespawnPlayer( player )
}

// Titan hot drops end by moving bots next to the first player (debug bots again). Put managed bots
// back where they landed.
::PilotBots_Orig_PostDropSpawnData <- PostDropSpawnData

::PostDropSpawnData <- function( player, index )
{
	local result = PilotBots_Orig_PostDropSpawnData( player, index )
	if ( IsValid( player ) && IsManagedBot( player ) && IsAlive( player ) )
		thread PilotBots_KeepHotDropSpot( player, player.GetOrigin(), player.GetAngles() )
	return result
}

::PilotBots_KeepHotDropSpot <- function( player, origin, angles )
{
	player.EndSignal( "OnDestroy" )
	player.EndSignal( "OnDeath" )
	wait 0
	player.SetOrigin( origin )
	player.SetAngles( angles )
}

::PilotBots_OnPlayerRespawned <- function( player )
{
	if ( !player.IsBot() )
		return

	PilotBots_EnsureReplayProxy( player )

	if ( !IsManagedBot( player ) || !( "pilotBotsSpawnTime" in player.s ) || player.s.pilotBotsSpawnTime != Time() )
		return
	local spawnPoint = player.s.pilotBotsSpawnPoint
	if ( !IsValid( spawnPoint ) || player.IsTitan() )
		return
	player.SetOrigin( spawnPoint.GetOrigin() )
	player.SetAngles( spawnPoint.GetAngles() )
}
// Callbacks are keyed by function name (FunctionToString), so they need a named function.
function PilotBots_OnPlayerRespawnedCallback( player )
{
	PilotBots_OnPlayerRespawned( player )
}
AddCallback_OnPlayerRespawned( PilotBots_OnPlayerRespawnedCallback )
PilotBots_Log( "convars and spawn wrappers installed" )

//---------------------------------------------------------
// Kill replays
//---------------------------------------------------------
// Seen through a bot's eyes the replay has no muzzle flash or tracers (first-person weapon effects
// are predicted by the shooter's client, and a bot has none). The engine only uses the third-person
// replay camera (as for grunts, spectres and auto-titans) when the view entity is not a player, so a
// bot's kill replays through an invisible non-player proxy riding along with it. Without one, the
// replay falls back to the victim's eyes.
::PilotBots_Orig_PlayerWatchesKillReplay <- PlayerWatchesKillReplay

::PlayerWatchesKillReplay <- function( player, attacker, attackerViewIndex, timeSinceAttackerSpawned, timeOfDeath, beforeTime, replayTracker, checkMinTime )
{
	if ( IsValid( attacker ) && attacker.IsPlayer() && attacker.IsBot() )
	{
		local proxy = PilotBots_GetReplayProxy( attacker )
		attackerViewIndex = proxy ? proxy.GetIndexForEntity() : player.GetIndexForEntity()
	}
	return PilotBots_Orig_PlayerWatchesKillReplay( player, attacker, attackerViewIndex, timeSinceAttackerSpawned, timeOfDeath, beforeTime, replayTracker, checkMinTime )
}

// Kept for the bot's whole connection so the replay history always has it.
::PilotBots_EnsureReplayProxy <- function( bot )
{
	if ( PilotBots_GetReplayProxy( bot ) )
		return

	// Offset to the bot's right so the replay camera frames the bot on the left of the screen, and
	// forward because the camera trails the proxy at a fixed distance, which brings it closer to the bot.
	local yaw = bot.GetAngles().y * PI / 180.0
	local right = Vector( sin( yaw ), -cos( yaw ), 0 )
	local forward = Vector( cos( yaw ), sin( yaw ), 0 )
	local offset = right * 60 + forward * 25 + Vector( 0, 0, 48 )
	local proxy = CreateScriptMover( null, bot.GetOrigin() + offset, Vector( 0, bot.GetAngles().y, 0 ) )
	proxy.Hide()
	proxy.SetParent( bot )
	bot.s.replayProxy <- proxy

	thread PilotBots_DestroyReplayProxyOnDisconnect( bot, proxy )
}

::PilotBots_GetReplayProxy <- function( bot )
{
	if ( !( "replayProxy" in bot.s ) || !IsValid( bot.s.replayProxy ) )
		return null
	return bot.s.replayProxy
}

::PilotBots_DestroyReplayProxyOnDisconnect <- function( bot, proxy )
{
	proxy.EndSignal( "OnDestroy" )
	bot.EndSignal( "OnDestroy" )

	OnThreadEnd(
		function () : ( proxy )
		{
			if ( IsValid( proxy ) )
				proxy.Destroy()
		}
	)

	bot.WaitSignal( "Disconnected" )
}
PilotBots_Log( "kill replay wrapper installed" )

//---------------------------------------------------------
// Team auto-balance
//---------------------------------------------------------
// With bots on the team, a bot takes the switch instead when it respawns. The bot manager adds and
// kicks bots a moment after a human joins or leaves, so the counts are briefly uneven every time,
// and humans who respawned in that window were thrown back and forth.
::PilotBots_Orig_ShouldAutoBalancePlayer <- ShouldAutoBalancePlayer

::ShouldAutoBalancePlayer <- function( player, manualSwitch, forceSwitch = false )
{
	local result = PilotBots_Orig_ShouldAutoBalancePlayer( player, manualSwitch, forceSwitch )
	if ( result && !manualSwitch && !forceSwitch && !player.IsBot() && PilotBots_TeamHasBot( player.GetTeam() ) )
		return false
	return result
}

::PilotBots_TeamHasBot <- function( team )
{
	foreach ( player in GetPlayerArrayOfTeam( team ) )
	{
		if ( player.IsBot() )
			return true
	}
	return false
}
PilotBots_Log( "auto-balance wrapper installed" )

//---------------------------------------------------------
// Rodeo
//---------------------------------------------------------
// Bot pilots riding a titan hurt it like spectres do: they can't aim at the exact hatch hitbox the way
// a person looks down into it, and every other hit is soaked by the shield / armor. The stock check
// (HitRodeoBrain, internal to _titan_health.nut) compares the hit box with soul.rodeoHitBoxNumber,
// so while the rider bot's own shot is processed that number is set to the shot's hit box.
::PilotBots_RiderBotSoul <- function( titan, damageInfo )
{
	local soul = IsValid( titan ) ? titan.GetTitanSoul() : null
	local attacker = damageInfo.GetAttacker()
	if ( !IsValid( soul ) || !IsValid( attacker ) || !attacker.IsPlayer() || !attacker.IsBot() || soul.GetRiderEnt() != attacker )
		return null
	return soul
}

::PilotBots_Orig_Titan_NPCTookDamage <- Titan_NPCTookDamage
::PilotBots_Orig_Titan_PlayerTookDamage <- Titan_PlayerTookDamage

::Titan_NPCTookDamage <- function( titan, damageInfo )
{
	local soul = PilotBots_RiderBotSoul( titan, damageInfo )
	if ( !soul )
		return PilotBots_Orig_Titan_NPCTookDamage( titan, damageInfo )

	local saved = soul.rodeoHitBoxNumber
	soul.rodeoHitBoxNumber = damageInfo.GetHitBox()
	local result
	try
	{
		result = PilotBots_Orig_Titan_NPCTookDamage( titan, damageInfo )
	}
	catch ( e )
	{
		soul.rodeoHitBoxNumber = saved
		throw e
	}
	soul.rodeoHitBoxNumber = saved
	return result
}

::Titan_PlayerTookDamage <- function( player, damageInfo, attacker, critHit )
{
	local soul = PilotBots_RiderBotSoul( player, damageInfo )
	if ( !soul )
		return PilotBots_Orig_Titan_PlayerTookDamage( player, damageInfo, attacker, critHit )

	local saved = soul.rodeoHitBoxNumber
	soul.rodeoHitBoxNumber = damageInfo.GetHitBox()
	local result
	try
	{
		result = PilotBots_Orig_Titan_PlayerTookDamage( player, damageInfo, attacker, critHit )
	}
	catch ( e )
	{
		soul.rodeoHitBoxNumber = saved
		throw e
	}
	soul.rodeoHitBoxNumber = saved
	return result
}

PilotBots_Log( "rodeo wrappers installed" )

//---------------------------------------------------------
// Capture Point
//---------------------------------------------------------
// The engine never puts a bot (fake client) in a trigger's touch list, so the hardpoint triggers'
// OnStartTouch / OnEndTouch never fire for bots and their counts leave them out: a bot standing on a
// point didn't capture it. (Export's submerged trigger_hurt was the same, see mp_switchback.nut.)
// Bots are checked against each trigger's box here and go through _hardpoints.nut's own enter / leave,
// and its count adds the bots it listed. Those functions are internal to _hardpoints.nut (IncludeFile),
// reached through its file scope.
::PilotBots_HardpointScope <- null

::PilotBots_FindHardpointScope <- function()
{
	if ( !( "__fileScopes" in getroottable() ) )
		return null
	foreach ( name, scope in __fileScopes )
	{
		if ( scope.rawin( "HardpointOnStartTouch" ) && scope.rawin( "HardpointOnEndTouch" ) && scope.rawin( "UpdateHardpointCount" ) )
			return scope
	}
	return null
}

::PilotBots_UpdateHardpointCount <- function( point )
{
	local scope = PilotBots_HardpointScope
	PilotBots_Orig_UpdateHardpointCount.call( scope, point )
	if ( !IsValid( point ) || !( "teamPlayersTouching" in point.s ) )
		return

	local touchingEnts = point.s.trigger.GetTouchingEntities()
	foreach ( team in [ TEAM_IMC, TEAM_MILITIA ] )
	{
		local players = point.GetHardpointPlayerCount( team )
		local titans = point.GetHardpointPlayerTitanCount( team )
		foreach ( player, time in point.s.teamPlayersTouching[ team ] )
		{
			if ( !IsValid( player ) || !IsAlive( player ) || !player.IsBot() || ArrayContains( touchingEnts, player ) )
				continue
			players++
			if ( player.IsTitan() )
				titans++
		}
		point.SetHardpointPlayerCount( team, players )
		point.SetHardpointPlayerTitanCount( team, titans )
	}
}

::PilotBots_IsInsideHardpointTrigger <- function( trigger, player )
{
	local triggerOrg = trigger.GetOrigin()
	local mins = triggerOrg + trigger.GetBoundingMins()
	local maxs = triggerOrg + trigger.GetBoundingMaxs()
	local org = player.GetOrigin() + Vector( 0, 0, 16 )
	return org.x >= mins.x && org.x <= maxs.x && org.y >= mins.y && org.y <= maxs.y && org.z >= mins.z && org.z <= maxs.z
}

::PilotBots_HardpointBotTouchThink <- function()
{
	local scope = PilotBots_HardpointScope
	for ( ;; )
	{
		wait 0.2

		if ( !( "hardpoints" in level ) )
			continue
		foreach ( hardpoint in level.hardpoints )
		{
			if ( !IsValid( hardpoint ) || !( "trigger" in hardpoint.s ) || !IsValid( hardpoint.s.trigger ) || !( "teamPlayersTouching" in hardpoint.s ) )
				continue
			local trigger = hardpoint.s.trigger

			// A bot that left the server never gets its leave.
			local gone = false
			foreach ( team in [ TEAM_IMC, TEAM_MILITIA ] )
			{
				local touching = hardpoint.s.teamPlayersTouching[ team ]
				foreach ( player in TableKeysToArray( touching ) )
				{
					if ( !IsValid( player ) )
					{
						delete touching[ player ]
						gone = true
					}
				}
			}
			if ( gone )
				PilotBots_UpdateHardpointCount.call( scope, hardpoint )

			foreach ( player in GetPlayerArray() )
			{
				if ( !player.IsBot() )
					continue
				local team = player.GetTeam()
				if ( team != TEAM_IMC && team != TEAM_MILITIA )
					continue

				local inside = IsAlive( player ) && PilotBots_IsInsideHardpointTrigger( trigger, player )
				local listed = player in hardpoint.s.teamPlayersTouching[ team ]
				try
				{
					if ( inside && !listed )
						scope.HardpointOnStartTouch( trigger, player, null, null )
					else if ( !inside && listed )
						scope.HardpointOnEndTouch( trigger, player, null, null )
				}
				catch ( e )
				{
					PilotBots_Log( "ERROR hardpoint touch for " + player.GetPlayerName() + ": " + e )
				}
			}
		}
	}
}

PilotBots_HardpointScope = PilotBots_FindHardpointScope()
if ( PilotBots_HardpointScope == null )
{
	PilotBots_Log( "capture point: _hardpoints.nut scope not found; bots can't capture" )
}
else
{
	::PilotBots_Orig_UpdateHardpointCount <- PilotBots_HardpointScope.UpdateHardpointCount
	PilotBots_HardpointScope.UpdateHardpointCount = PilotBots_UpdateHardpointCount
	if ( "UpdateHardpointCount" in getroottable() )
		::UpdateHardpointCount <- function( point ) { PilotBots_UpdateHardpointCount.call( PilotBots_HardpointScope, point ) }
	thread PilotBots_HardpointBotTouchThink()
	PilotBots_Log( "capture point: bot touch installed" )
}

//---------------------------------------------------------
// Death pits
//---------------------------------------------------------
// The pits' trigger_hurt never touches a bot (see Capture Point above), and its damage per hit
// barely scratches a titan, so bots and titans that fell in (Outpost 207's shaft) lived on down
// there. Titans touching a lethal trigger, and bots inside one's box for a moment while below the
// lowest node of the AI graph, die the way a pilot would. (The box alone isn't enough: on Outpost
// 207 it takes in the ground around the shaft, and bots died all over the map. The graph has no
// nodes down a pit, the same rule IsVoidAt in _pilotbots_ai.nut goes by.) (War Games has the same for titans in mp_wargames.nut; the dead are skipped, so
// nothing is killed twice.)
::PilotBots_PitLethalDamage <- 100		// a trigger_hurt doing at least this per hit (or a fall / splat one) is a death pit
::PilotBots_PitCheckInterval <- 0.25
::PilotBots_PitBotDelay <- 0.5			// a bot is killed after this long in the box (not for cutting through a corner of it)...
::PilotBots_PitBelowGraph <- 128.0		// ...and only this far below the lowest graph node (BOT_VOID_MARGIN)

::PilotBots_PitDamageSource <- function( source )
{
	switch ( source )
	{
		case "splat":
			return eDamageSourceId.splat
		case "burn":
			return eDamageSourceId.burn
		case "submerged":
			return eDamageSourceId.submerged
	}
	return eDamageSourceId.fall
}

::PilotBots_PitThink <- function()
{
	wait 1.0	// every entity of the map has spawned

	local pits = []
	foreach ( trigger in GetEntArrayByClass_Expensive( "trigger_hurt" ) )
	{
		local damage = 0.0
		local source = ""
		try
		{
			if ( trigger.HasKey( "damage" ) )
				damage = trigger.GetValueForKey( "damage" ).tofloat()
			if ( trigger.HasKey( "damageSourceName" ) )
				source = trigger.GetValueForKey( "damageSourceName" )
		}
		catch ( e ) {}
		if ( damage >= PilotBots_PitLethalDamage || source == "fall" || source == "splat" )
		{
			pits.append( { trigger = trigger, damageSourceId = PilotBots_PitDamageSource( source ) } )
			local org = trigger.GetOrigin()
			local mins = org + trigger.GetBoundingMins()
			local maxs = org + trigger.GetBoundingMaxs()
			PilotBots_Log( "death pit: trigger_hurt damage " + damage + " source " + source
				+ format( ", box %.0f %.0f %.0f to %.0f %.0f %.0f", mins.x, mins.y, mins.z, maxs.x, maxs.y, maxs.z ) )
		}
	}
	if ( pits.len() == 0 )
		return

	// Lowest node of the AI graph; no graph, no bot check (titans still are).
	local floorZ = null
	if ( "NavGetNodeCount" in getroottable() )
	{
		local count = NavGetNodeCount()
		for ( local i = 0; i < count; i++ )
		{
			local z = NavGetNodePosition( i )[2]
			if ( floorZ == null || z < floorZ )
				floorZ = z
		}
	}
	local botMaxZ = floorZ != null ? floorZ - PilotBots_PitBelowGraph : null
	PilotBots_Log( "death pit: bots die below z " + ( botMaxZ != null ? format( "%.0f", botMaxZ ) : "(no graph, bots not checked)" ) )

	local botInsideSince = {}
	for ( ;; )
	{
		wait PilotBots_PitCheckInterval

		local victims = []
		foreach ( team in [ TEAM_IMC, TEAM_MILITIA ] )
			victims.extend( GetNPCArrayEx( "npc_titan", team, Vector( 0, 0, 0 ), -1 ) )
		foreach ( player in GetPlayerArray() )
		{
			if ( player.IsBot() || player.IsTitan() )
				victims.append( player )
		}

		local now = Time()
		foreach ( ent in victims )
		{
			local hit = null
			local isBot = ent.IsPlayer() && ent.IsBot()
			if ( isBot && ( botMaxZ == null || ent.GetOrigin().z > botMaxZ ) )
			{
				if ( ent in botInsideSince )
					delete botInsideSince[ ent ]
				continue
			}
			if ( IsAlive( ent ) )
			{
				foreach ( pit in pits )
				{
					if ( !IsValid( pit.trigger ) )
						continue
					if ( isBot ? PilotBots_IsInsideHardpointTrigger( pit.trigger, ent ) : pit.trigger.IsTouching( ent ) )
					{
						hit = pit
						break
					}
				}
			}
			if ( hit == null )
			{
				if ( ent in botInsideSince )
					delete botInsideSince[ ent ]
				continue
			}
			if ( isBot )
			{
				if ( !( ent in botInsideSince ) )
					botInsideSince[ ent ] <- now
				if ( now - botInsideSince[ ent ] < PilotBots_PitBotDelay )
					continue
				delete botInsideSince[ ent ]
			}
			local org = ent.GetOrigin()
			PilotBots_Log( "death pit: " + ( ent.IsPlayer() ? ent.GetPlayerName() : ent.GetClassname() )
				+ ( ent.IsTitan() ? " (titan)" : "" ) + " fell in at " + format( "%.0f %.0f %.0f", org.x, org.y, org.z ) )
			ent.TakeDamage( ent.GetMaxHealth() + 10000, hit.trigger, hit.trigger, { forceKill = true, damageSourceId = hit.damageSourceId } )
		}

		foreach ( ent in TableKeysToArray( botInsideSince ) )
		{
			if ( !IsValid( ent ) )
				delete botInsideSince[ ent ]
		}
	}
}
thread PilotBots_PitThink()
PilotBots_Log( "death pit watch installed" )

//---------------------------------------------------------
// Campaign intro deaths
//---------------------------------------------------------
// Bots died in Demeter's intro drop pods; the cause is logged so it can be found.
::PilotBots_LogIntroDeath <- function( player, damageInfo )
{
	if ( !player.IsBot() || !GetCinematicMode() )
		return
	local flagged = ( player.GetCinematicEventFlags() & CE_FLAG_INTRO ) != 0
	local slot = "cinematicSlot" in player.s && player.s.cinematicSlot != null
	local early = GetGameState() <= eGameState.Prematch || ( level.nv.gameStartTime != null && Time() - level.nv.gameStartTime < 60.0 )
	if ( !flagged && !slot && !early )
		return
	local attacker = damageInfo.GetAttacker()
	local inflictor = damageInfo.GetInflictor()
	local org = player.GetOrigin()
	PilotBots_Log( "intro death: " + player.GetPlayerName() + " state " + GetGameState()
		+ " source " + damageInfo.GetDamageSourceIdentifier()
		+ " attacker " + ( IsValid( attacker ) ? attacker.GetClassname() : "none" )
		+ " inflictor " + ( IsValid( inflictor ) ? inflictor.GetClassname() : "none" )
		+ " flag " + flagged + " slot " + slot + " parent " + IsValid( player.GetParent() )
		+ " at " + format( "%.0f %.0f %.0f", org.x, org.y, org.z ) )
}
function PilotBots_IntroDeathCallback( player, damageInfo )
{
	PilotBots_LogIntroDeath( player, damageInfo )
}
AddCallback_OnPlayerKilled( PilotBots_IntroDeathCallback )

PilotBots_Log( "campaign intro death log installed" )

//---------------------------------------------------------
// Frontier Overhaul: titan executions outside Attrition
//---------------------------------------------------------
// FO's _score.nut (AwardPilotTermination) calls Attrition_AwardPilotTermination in every mode, but
// only Attrition loads mp/attrition.nut, which defines it: a script error on each piloted titan
// executed. Outside Attrition there are no attrition points to give, so an empty stand-in.
if ( !( "Attrition_AwardPilotTermination" in getroottable() ) )
{
	::Attrition_AwardPilotTermination <- function( attacker, titan, isCaptain = false ) {}
	PilotBots_Log( "attrition award stand-in installed" )
}

PilotBots_Log( "all done" )
