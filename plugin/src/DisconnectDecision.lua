local ConnectionError = require(script.Parent.ConnectionError)
local ReconnectPolicy = require(script.Parent.ReconnectPolicy)

local DisconnectDecision = {}

DisconnectDecision.Reconnect = "Reconnect"
DisconnectDecision.Error = "Error"
DisconnectDecision.NotConnected = "NotConnected"

function DisconnectDecision.resolve(options)
	local hasReconnectTarget = options.target ~= nil
	local reconnectStopped = options.disconnectRequested
		or options.unloading
		or (hasReconnectTarget and not options.enabled and ConnectionError.isRetryable(options.error))
		or (hasReconnectTarget and options.target.key ~= options.currentTargetKey)

	if reconnectStopped then
		return DisconnectDecision.NotConnected
	end

	if ReconnectPolicy.shouldRetry(options) then
		return DisconnectDecision.Reconnect
	end

	if options.error ~= nil then
		return DisconnectDecision.Error
	end

	return DisconnectDecision.NotConnected
end

return DisconnectDecision
