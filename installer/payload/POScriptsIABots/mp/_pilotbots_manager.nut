//=========================================================
// Bot slot manager
// Fills the match with script-driven pilot bots up to delta_bot_fill_target
// (humans + bots). Bots join as soon as the first human connects, so the match starts
// with them; a bot leaves whenever a human joins and comes back when one leaves.
//=========================================================

const BOT_RECONCILE_DELAY = 1.0
// Private match bot count (pm_bot_count, see ui/menu_mode_select.nut); kept here rather than in
// _consts.nut so mods that replace _consts.nut don't remove them.
const BOT_PM_COUNT_MAX = 10
const BOT_PM_COUNT_DEFAULT = 10	// private matches without the setting applied

function main()
{
	Globalize( IsManagedBot )
	Globalize( BotManagerEnabledForMode )
	Globalize( GetBotFillTarget )
	Globalize( BotRandomizeLoadouts )

	RegisterSignal( "BotReconcile" )

	level.managedBots <- {}
	// Names of bots inside BotCreate: the engine runs the connect/first-spawn callbacks
	// before BotCreate returns, so this is how IsManagedBot recognises them that early.
	level.pendingBotNames <- {}
	file.reconcileQueued <- false
	file.watchStarted <- false

	if ( !BotManagerEnabledForMode() )
	{
		printt( "BotManager: disabled for game mode", GameRules.GetGameMode() )
		return
	}

	FlagSet( "PilotBot" )	// bots spawn as pilots and call titans themselves

	AddCallback_OnClientConnected( BotManager_OnClientConnected )
	AddCallback_OnClientDisconnected( BotManager_OnClientDisconnected )
	AddCallback_GameStateEnter( eGameState.WaitingForPlayers, BotManager_OnMatchStateEnter )
	AddCallback_GameStateEnter( eGameState.Prematch, BotManager_OnMatchStateEnter )
	AddCallback_GameStateEnter( eGameState.Playing, BotManager_OnMatchStateEnter )
}

function BotManager_OnMatchStateEnter()
{
	if ( !file.watchStarted )
	{
		file.watchStarted = true
		thread BotFillTargetWatchThread()
	}
	QueueBotReconcile()
}

// delta_bot_fill_target can be changed from the console mid-match; nothing else would notice it.
function BotFillTargetWatchThread()
{
	local lastTarget = GetBotFillTarget()
	while ( true )
	{
		wait 1.0
		local target = GetBotFillTarget()
		if ( target == lastTarget )
			continue

		printt( "BotManager: fill target changed to", target )
		lastTarget = target
		QueueBotReconcile()
	}
}

function BotManagerEnabledForMode()
{
	// The bot natives come from tier0.dll (server/ai/bot_control.cpp). Without them (an older
	// tier0.dll) these scripts do nothing and the game behaves like stock.
	if ( !( "BotCreate" in getroottable() ) )
		return false

	// Capture Point is played as an objective mode (see GetObjectivePoint in _pilotbots_ai).
	switch ( GameRules.GetGameMode() )
	{
		case ATTRITION:
		case TEAM_DEATHMATCH:
		case CAPTURE_POINT:
			return true
	}
	return false
}

function IsManagedBot( player )
{
	if ( player in level.managedBots )
		return true
	return player.IsBot() && ( player.GetPlayerName() in level.pendingBotNames )
}

function GetBotFillTarget()
{
	local target = GetConVarInt( "delta_bot_fill_target" )
	if ( target <= 0 )
		return 0

	// Always keep one slot open so a human can connect; the bot leaves right after.
	local maxPlayers = GetCurrentPlaylistVarInt( "max players", 12 )
	return min( target, maxPlayers - 1 )
}

// How many bots the match should have with this many humans. The private match settings
// (bot_count, 0-10, see the match settings menu; 10 in a private match until set) ask for that many
// bots, as long as there's room; outside private matches delta_bot_fill_target fills up to a total of
// humans + bots. Either way bots are
// spread over the teams by GetTeamNeedingPlayer, and one slot is always kept open for a human.
function GetDesiredBotCount( humanCount )
{
	// No humans, no bots: an empty server stays empty (and can hibernate).
	if ( humanCount == 0 )
		return 0

	// A private match where the setting was never applied gets the menu's default.
	local count = GetCurrentPlaylistVarInt( "bot_count", -1 )
	if ( count < 0 && IsPrivateMatch() )
		count = BOT_PM_COUNT_DEFAULT
	if ( count < 0 )
		return max( 0, GetBotFillTarget() - humanCount )

	local room = GetCurrentPlaylistVarInt( "max players", 12 ) - 1 - humanCount
	return max( 0, min( min( count, BOT_PM_COUNT_MAX ), room ) )
}

function BotManager_OnClientConnected( player )
{
	if ( !player.IsBot() )
	{
		QueueBotReconcile()
		return
	}

	// The stock connect code gives every bot the same template (SetBotPilotLoadout/SetBotTitanLoadout)
	// right before these callbacks, and bot_randomize_loadout is answered 0 (sv_pilotbots.nut), so
	// this is where a managed bot gets its own loadout. Once: the callbacks can run twice for a bot.
	if ( IsManagedBot( player ) && !( "pilotBotsLoadoutRolled" in player.s ) )
	{
		player.s.pilotBotsLoadoutRolled <- true
		try
		{
			BotRandomizeLoadouts( player )
		}
		catch ( e )
		{
			printt( "BotManager: loadout roll failed for", player.GetPlayerName(), e )
			if ( "PilotBotsLog" in getroottable() )
				PilotBotsLog( "BotManager: loadout roll failed for " + player.GetPlayerName() + ": " + e )
		}
	}
}

function BotManager_OnClientDisconnected( player )
{
	if ( player in level.managedBots )
		delete level.managedBots[ player ]

	if ( !player.IsBot() )
		QueueBotReconcile()
}

function QueueBotReconcile()
{
	if ( file.reconcileQueued )
		return

	file.reconcileQueued = true
	thread BotReconcileThread()
}

function BotReconcileThread()
{
	// Let connects/disconnects settle so counts are not off by the player in transit.
	wait BOT_RECONCILE_DELAY
	file.reconcileQueued = false

	local state = GetGameState()
	// Filling during WaitingForPlayers lets both teams be populated right away, so the
	// match leaves the lobby wait as soon as the first human is in.
	if ( state < eGameState.WaitingForPlayers || state >= eGameState.WinnerDetermined )
		return

	local humans = []
	local bots = []
	foreach ( player in GetPlayerArray() )
	{
		if ( player.IsBot() )
		{
			if ( player in level.managedBots )
				bots.append( player )
		}
		else
		{
			humans.append( player )
		}
	}

	local desiredBots = GetDesiredBotCount( humans.len() )

	// Bots are removed right away, alive or dead: a joining human must never wait for a slot.
	for ( local i = bots.len() - 1; i >= 0; i-- )
	{
		if ( !IsValid( bots[ i ] ) )
			bots.remove( i )
	}

	// The kick goes through the command buffer, so the team counts don't drop until later: keep our
	// own, or two humans joining at once (one per team) would both take a bot off the same team.
	local teamCounts = {}
	teamCounts[ TEAM_IMC ] <- GetTeamPlayerCount( TEAM_IMC )
	teamCounts[ TEAM_MILITIA ] <- GetTeamPlayerCount( TEAM_MILITIA )
	while ( bots.len() > desiredBots )
	{
		local bot = ChooseBotToRemove( bots, teamCounts )
		ArrayRemove( bots, bot )
		local team = bot.GetTeam()
		if ( team in teamCounts )
			teamCounts[ team ]--
		RemoveManagedBot( bot )
	}

	for ( local count = bots.len(); count < desiredBots; count++ )
		AddManagedBot( GetTeamNeedingPlayer() )
}

function AnyHumanDead()
{
	foreach ( player in GetPlayerArray() )
	{
		if ( !player.IsBot() && !IsAlive( player ) )
			return true
	}
	return false
}

function GetTeamNeedingPlayer()
{
	return GetTeamPlayerCount( TEAM_IMC ) <= GetTeamPlayerCount( TEAM_MILITIA ) ? TEAM_IMC : TEAM_MILITIA
}

// Remove from the larger team so the human who just joined keeps teams even.
// Within that team prefer a dead bot, then a pilot, and leave titan bots for last.
// teamCounts: players per team, minus the bots already being kicked this pass.
function ChooseBotToRemove( bots, teamCounts )
{
	local imcCount = teamCounts[ TEAM_IMC ]
	local militiaCount = teamCounts[ TEAM_MILITIA ]
	local preferredTeam = imcCount >= militiaCount ? TEAM_IMC : TEAM_MILITIA

	local best = null
	local bestScore = -1
	foreach ( bot in bots )
	{
		local score = 0
		if ( bot.GetTeam() == preferredTeam )
			score += 4
		if ( !IsAlive( bot ) )
			score += 2
		else if ( !bot.IsTitan() )
			score += 1

		if ( score > bestScore )
		{
			best = bot
			bestScore = score
		}
	}
	return best
}

function AddManagedBot( team )
{
	local requestedName = GenerateBotName()
	level.pendingBotNames[ requestedName ] <- true
	local name = BotCreate( team, requestedName )
	delete level.pendingBotNames[ requestedName ]

	if ( name == "" )
	{
		printt( "BotManager: failed to create bot for team", team )
		return
	}

	foreach ( player in GetPlayerArray() )
	{
		if ( player.IsBot() && player.GetPlayerName() == name )
		{
			level.managedBots[ player ] <- true
			return
		}
	}
}

function RemoveManagedBot( bot )
{
	if ( bot in level.managedBots )
		delete level.managedBots[ bot ]

	BotClearInput( bot )
	ServerCommand( "kickid " + bot.GetUserId() )
}

//---------------------------------------------------------
// Names
//---------------------------------------------------------
const BOT_NAME_MAX_LEN = 31

function PickRandom( array )
{
	return array[ RandomInt( array.len() ) ]
}

function GenerateBotName()
{
	local name = GenerateAnyBotName()
	for ( local attempt = 0; attempt < 10 && !BotNameAvailable( name ); attempt++ )
		name = GenerateAnyBotName()

	if ( !BotNameAvailable( name ) )
		name = name + RandomInt( 1000 )

	if ( name.len() > BOT_NAME_MAX_LEN )
		name = name.slice( 0, BOT_NAME_MAX_LEN )
	return name
}

function GenerateAnyBotName()
{
	switch ( RandomInt( 3 ) )
	{
		case 0:
			return GenerateGamertag()
		case 1:
			return GenerateCallsign()
	}
	return GenerateFrontierName()
}

function BotNameAvailable( name )
{
	if ( name in level.pendingBotNames )
		return false

	foreach ( player in GetPlayerArray() )
	{
		if ( player.GetPlayerName() == name )
			return false
	}
	return true
}

// Online-player style: xNightHawk, Viper_77, darkghost99, TheRaptorTV
function GenerateGamertag()
{
	local prefixes = [ "x", "The", "Dark", "Lil", "Mr", "Big", "Its", "Real", "Pro", "Sir", "Hyper", "Toxic" ]
	local words = [ "Viper", "NightHawk", "Ghost", "Raptor", "Shadow", "Blaze", "Phantom", "Reaper", "Falcon", "Havoc",
		"Venom", "Nova", "Striker", "Wolf", "Cobra", "Titan", "Pulse", "Rogue", "Frost", "Onyx", "Specter", "Bandit",
		"Jackal", "Nomad", "Hunter", "Sniper", "Rocket", "Ninja", "Panda", "Tornado", "Kraken", "Vortex", "Glitch",
		"Pixel", "Blitz", "Comet", "Fury", "Banshee", "Cyclone", "Wraith" ]
	local seconds = [ "Runner", "Slayer", "King", "Hawk", "Fox", "Storm", "Shot", "Byte", "Strike", "Rider", "Main", "Gamer" ]
	local suffixes = [ "77", "99", "01", "13", "420", "1337", "007", "TV", "YT", "BR", "Pro", "X", "2k", "_GG" ]

	local name = PickRandom( words )
	if ( RandomInt( 3 ) == 0 )
		name = name + PickRandom( seconds )
	if ( RandomInt( 3 ) == 0 )
		name = PickRandom( prefixes ) + name

	local roll = RandomInt( 4 )
	if ( roll == 0 )
		name = name + "_" + PickRandom( suffixes )
	else if ( roll == 1 )
		name = name + PickRandom( suffixes )
	else if ( roll == 2 )
		name = name + RandomInt( 100 )

	if ( RandomInt( 5 ) == 0 )
		name = name.tolower()
	return name
}

// Titanfall style: Sgt. Blackwood, Raptor-6, Lt. Kane, Echo Mercer
function GenerateCallsign()
{
	local ranks = [ "Pvt.", "Cpl.", "Sgt.", "SSgt.", "Lt.", "Capt.", "Maj.", "Col.", "Cmdr." ]
	local codenames = [ "Raptor", "Echo", "Bravo", "Hammer", "Anvil", "Talon", "Saber", "Vulture", "Jester", "Warden",
		"Halo", "Zulu", "Sierra", "Kilo", "Mako", "Bolt", "Ranger", "Outlaw", "Hydra", "Lancer" ]

	switch ( RandomInt( 3 ) )
	{
		case 0:
			return PickRandom( ranks ) + " " + PickRandom( GetBotSurnames() )
		case 1:
			return PickRandom( codenames ) + "-" + ( RandomInt( 9 ) + 1 )
	}
	return PickRandom( codenames ) + " " + PickRandom( GetBotSurnames() )
}

// Frontier style: Elena Castro, Pilot Hudson, Marauder 2-1, Santiago [MCOR], Yuma Actual
function GenerateFrontierName()
{
	local firstNames = [ "Elena", "Marco", "Rafael", "Isabel", "Tomas", "Nadia", "Victor", "Mara", "Owen", "Rhea",
		"Dmitri", "Ana", "Hector", "Jun", "Felix", "Iris", "Mateo", "Leon", "Sofia", "Ezra", "Yara", "Andre",
		"Lucas", "Daniel", "Kai", "Teresa", "Samuel", "Ines", "Gabriel", "Lena" ]
	// IMC and Militia units, ships and Frontier worlds
	local units = [ "Marauder", "Frontier", "Typhon", "Demeter", "Harmony", "Hammond", "Odyssey", "Redeye",
		"Bastion", "Yuma", "Boneyard", "Outpost", "Nexus", "Relic", "Colony", "Fracture", "Freeport", "Sentinel" ]
	local tags = [ "[IMC]", "[MCOR]", "[6-4]", "[APEX]", "[MRC]", "[SRS]" ]
	local pilotRanks = [ "Pilot", "Pilot", "Ace", "Rifleman", "Vanguard" ]

	switch ( RandomInt( 5 ) )
	{
		case 0:		// Elena Castro
			return PickRandom( firstNames ) + " " + PickRandom( GetBotSurnames() )
		case 1:		// Pilot Hudson
			return PickRandom( pilotRanks ) + " " + PickRandom( GetBotSurnames() )
		case 2:		// Marauder 2-1, Typhon-4
			return PickRandom( units ) + ( RandomInt( 2 ) == 0 ? " " + ( RandomInt( 6 ) + 1 ) + "-" + ( RandomInt( 9 ) + 1 ) : "-" + ( RandomInt( 9 ) + 1 ) )
		case 3:		// Santiago [MCOR]
			return PickRandom( GetBotSurnames() ) + " " + PickRandom( tags )
	}
	return PickRandom( units ) + " " + PickRandom( [ "Actual", "Lead", "Two", "Three", "Six" ] )
}

function GetBotSurnames()
{
	return [ "Blackwood", "Kane", "Mercer", "Reyes", "Voss", "Hale", "Bishop", "Cross", "Steele",
		"Ward", "Drake", "Rourke", "Navarro", "Okafor", "Sato", "Ivanov", "Novak", "Silva", "Holt", "Briggs", "Vance",
		"Kowalski", "Mbeki", "Larsen", "Ortega", "Costa", "Fischer", "Tanaka", "Ramos",
		"Castro", "Hudson", "Marques", "Santiago", "Alphonse", "Moreau", "Delgado", "Rocha", "Abara", "Kessler",
		"Lindqvist", "Okoro", "Petrov", "Quintero", "Soto", "Varga", "Whitlock", "Yilmaz", "Zhou", "Ferreira" ]
}

//---------------------------------------------------------
// Loadouts: rolled once when the bot connects and kept for the whole match
//---------------------------------------------------------
function BotRandomizeLoadouts( player )
{
	local pilotTable = player.playerClassData[ level.pilotClass ]
	BotRollLoadout( pilotTable, false )
	pilotTable.passive1 <- PassiveBitfieldFromEnum( PickRandomItemRef( itemType.PILOT_PASSIVE1 ) )
	pilotTable.passive2 <- PassiveBitfieldFromEnum( PickRandomItemRef( itemType.PILOT_PASSIVE2 ) )
	OverrideBotLoadout( pilotTable, false )

	local titanTable = player.playerClassData[ "titan" ]
	BotRollLoadout( titanTable, true )
	titanTable.passive1 <- PassiveBitfieldFromEnum( PickRandomItemRef( itemType.TITAN_PASSIVE1 ) )
	titanTable.passive2 <- PassiveBitfieldFromEnum( PickRandomItemRef( itemType.TITAN_PASSIVE2 ) )
	OverrideBotLoadout( titanTable, true )

	printt( "BotManager:", player.GetPlayerName(), "pilot", pilotTable.primaryWeapon, pilotTable.secondaryWeapon,
		pilotTable.sidearmWeapon, pilotTable.offhandWeapons[0].weapon, pilotTable.offhandWeapons[1].weapon,
		"| titan", titanTable.playerSetFile, titanTable.primaryWeapon, titanTable.offhandWeapons[0].weapon,
		titanTable.offhandWeapons[1].weapon )
}

// Same picks as the stock RandomizeBotLoadout (_utility.nut), but with RandomInt: that one uses
// Squirrel's rand(), which is never seeded, so every match would roll the same loadouts.
function BotRollLoadout( table, isTitan )
{
	table.primaryWeapon = PickRandomItemRef( isTitan ? itemType.TITAN_PRIMARY : itemType.PILOT_PRIMARY )
	table.primaryWeaponMods = []
	if ( !isTitan )
	{
		table.secondaryWeapon = PickRandomItemRef( itemType.PILOT_SECONDARY )
		table.sidearmWeapon = PickRandomItemRef( itemType.PILOT_SIDEARM )
	}
	table.offhandWeapons[0].weapon = PickRandomItemRef( isTitan ? itemType.TITAN_ORDNANCE : itemType.PILOT_ORDNANCE )
	table.offhandWeapons[0].mods = []
	table.offhandWeapons[1].weapon = PickRandomItemRef( isTitan ? itemType.TITAN_SPECIAL : itemType.PILOT_SPECIAL )
	table.offhandWeapons[1].mods = []
	table.playerSetFile = PickRandomItemRef( isTitan ? itemType.TITAN_SETFILE : itemType.PILOT_SETFILE )
}

function PickRandomItemRef( type )
{
	return PickRandom( GetAllItemsOfType( type ) ).ref
}
