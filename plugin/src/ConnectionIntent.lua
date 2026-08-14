local ConnectionIntent = {}

ConnectionIntent.Connect = "Connect"
ConnectionIntent.Disconnect = "Disconnect"

function ConnectionIntent.resolve(sessionStatus, hasPendingReconnect)
	if hasPendingReconnect then
		return ConnectionIntent.Disconnect
	end

	if sessionStatus == nil or sessionStatus == "NotStarted" then
		return ConnectionIntent.Connect
	end

	if sessionStatus == "Connecting" or sessionStatus == "Connected" then
		return ConnectionIntent.Disconnect
	end

	return nil
end

return ConnectionIntent
