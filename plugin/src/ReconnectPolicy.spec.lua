return function()
	local ConnectionError = require(script.Parent.ConnectionError)
	local ReconnectPolicy = require(script.Parent.ReconnectPolicy)

	local retryableError = ConnectionError.retryable(ConnectionError.Kind.WebSocketTransport, "Connection closed")
	local target = { key = "localhost:34872" }

	local function shouldRetry(overrides)
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

		return ReconnectPolicy.shouldRetry(options)
	end

	it("retries an unexpected transport failure for the current target", function()
		expect(shouldRetry()).to.equal(true)
	end)

	it("does not retry after a manual disconnect", function()
		expect(shouldRetry({ disconnectRequested = true })).to.equal(false)
	end)

	it("does not retry when Auto Reconnect is disabled", function()
		expect(shouldRetry({ enabled = false })).to.equal(false)
	end)

	it("does not retry while the plugin unloads", function()
		expect(shouldRetry({ unloading = true })).to.equal(false)
	end)

	it("does not retry after the connection target changes", function()
		expect(shouldRetry({ currentTargetKey = "localhost:34873" })).to.equal(false)
	end)

	it("does not retry a non-retryable error", function()
		local err = ConnectionError.nonRetryable(ConnectionError.Kind.Protocol, "Wrong protocol")

		expect(shouldRetry({ error = err })).to.equal(false)
	end)
end
