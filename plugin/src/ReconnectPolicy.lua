local ConnectionError = require(script.Parent.ConnectionError)

local ReconnectPolicy = {}

function ReconnectPolicy.shouldRetry(options)
	return options.error ~= nil
		and ConnectionError.isRetryable(options.error)
		and options.enabled
		and not options.disconnectRequested
		and not options.unloading
		and options.target ~= nil
		and options.target.key == options.currentTargetKey
end

return ReconnectPolicy
