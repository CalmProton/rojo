return function()
	local ConnectionError = require(script.Parent.ConnectionError)
	local DisconnectDecision = require(script.Parent.DisconnectDecision)

	local target = { key = "localhost:34872" }
	local retryableError = ConnectionError.retryable(ConnectionError.Kind.WebSocketTransport, "Connection closed")

	local function resolve(overrides)
		local options = {
			error = retryableError,
			enabled = true,
			disconnectRequested = false,
			unloading = false,
			target = target,
			currentTargetKey = target.key,
		}

		for key, value in overrides or {} do
			options[key] = value
		end

		return DisconnectDecision.resolve(options)
	end

	it("suppresses the blocking error state while an established session retries", function()
		expect(resolve()).to.equal(DisconnectDecision.Reconnect)
		expect(resolve()).never.to.equal(DisconnectDecision.Error)
	end)

	it("keeps a non-retryable error in the blocking error state", function()
		local error = ConnectionError.nonRetryable(ConnectionError.Kind.Protocol, "Wrong protocol")

		expect(resolve({ error = error })).to.equal(DisconnectDecision.Error)
	end)

	it("ignores a late transport error after a requested disconnect", function()
		expect(resolve({ disconnectRequested = true })).to.equal(DisconnectDecision.NotConnected)
	end)

	it("ignores a late transport error while unloading", function()
		expect(resolve({ unloading = true })).to.equal(DisconnectDecision.NotConnected)
	end)

	it("ignores a late transport error after Auto Reconnect is disabled", function()
		expect(resolve({ enabled = false })).to.equal(DisconnectDecision.NotConnected)
	end)

	it("shows an established session's non-retryable error when Auto Reconnect is disabled", function()
		local error = ConnectionError.nonRetryable(ConnectionError.Kind.Protocol, "Wrong protocol")

		expect(resolve({ enabled = false, error = error })).to.equal(DisconnectDecision.Error)
	end)

	it("ignores a late transport error after the target changes", function()
		expect(resolve({ currentTargetKey = "localhost:34873" })).to.equal(DisconnectDecision.NotConnected)
	end)
end
