//=========================================================
// Pilot bots private match settings (lobby side)
// ui/menu_mode_select.nut sends "PilotBotsSetting <pm_bot_count|pm_bot_lethality> <value>" and this
// stores it in the playlist (bot_count / bot_lethality), read by mp/_bot_manager.nut and mp/_bot_ai.nut.
// An R1Delta autorun script instead of a change to menu/_lobby.nut, so it keeps working when another
// mod ships its own _lobby.nut. Same checks as the lobby's UpdatePrivateMatchSetting.
//=========================================================

const PILOTBOTS_SETTING_COUNT_MAX = 10

function PilotBots_ClientCommand_Setting( player, ... )
{
	if ( !IsPrivateMatch() || GetLobbyType() != "game" || GetMapName() != "mp_lobby" )
		return true
	if ( GetPartyLeader( player ) != player )
		return true
	if ( vargc < 2 )
		return true

	local name = vargv[0]
	local value = vargv[1].tofloat().tointeger()
	switch ( name )
	{
		case "pm_bot_count":
			SetPlaylistVarOverride( "bot_count", "" + clamp( value, 0, PILOTBOTS_SETTING_COUNT_MAX ) )
			break

		case "pm_bot_lethality":
			// menu index -> bot skill level; must match ui/menu_mode_select.nut
			local skills = [ 1, 0, 2, 3 ]
			if ( value < 0 || value >= skills.len() )
				return true
			SetPlaylistVarOverride( "bot_lethality", "" + skills[value] )
			break

		default:
			return true
	}

	SetPlaylistVarOverride( "private_match", "1" )
	return true
}

try
{
	AddClientCommandCallback( "PilotBotsSetting", PilotBots_ClientCommand_Setting )
	if ( "PilotBotsLog" in getroottable() )
		PilotBotsLog( "settings command registered, map " + GetMapName() )
}
catch ( e )
{
	if ( "PilotBotsLog" in getroottable() )
		PilotBotsLog( "ERROR registering PilotBotsSetting: " + e )
}
