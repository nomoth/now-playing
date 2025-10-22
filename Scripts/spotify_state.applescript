try
	tell application "System Events"
		if not (exists process "Spotify") then
			return "not_running"
		end if
	end tell
	
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
		
		return stateString & "|" & currentArtist & "|" & currentTrack & "|" & currentPosition & "|" & trackDuration & "|" & (currentState as string)
	end tell
on error
	return "error"
end try