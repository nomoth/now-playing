-- Checked here rather than through System Events, which needs an Automation permission of its own.
-- A command sent to a Spotify that quit since this check would relaunch it: keep the check right before them.
if not (application "Spotify" is running) then return "not_running"

-- ASCII unit separator: unlike "|", it does not appear in artist or track names.
-- Must match SpotifyMonitor.fieldSeparator.
set fieldSeparator to character id 31

try
	-- Each command to Spotify must answer within this delay, otherwise the script returns "timeout"
	with timeout of 3 seconds
		tell application "Spotify"
			set currentState to player state
			set currentArtist to artist of current track as string
			set currentTrack to name of current track as string
			set currentPosition to player position as integer
			set trackDuration to duration of current track as integer

			-- Convert player state constants to readable strings
			if currentState is playing then
				set stateString to "playing"
			else if currentState is paused then
				set stateString to "paused"
			else if currentState is stopped then
				set stateString to "stopped"
			else
				set stateString to "unknown"
			end if
		end tell
	end timeout

	return stateString & fieldSeparator & currentArtist & fieldSeparator & currentTrack & fieldSeparator & currentPosition & fieldSeparator & trackDuration
on error number errorNumber
	-- errAETimeout: Spotify is busy, which says nothing about what it plays
	if errorNumber is -1712 then return "timeout"
	return "error"
end try
