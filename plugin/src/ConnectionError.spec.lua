return function()
	local ConnectionError = require(script.Parent.ConnectionError)

	it("classifies retryable transport errors", function()
		local err = ConnectionError.retryable(ConnectionError.Kind.WebSocketTransport, "Connection closed")

		expect(ConnectionError.is(err)).to.equal(true)
		expect(ConnectionError.isRetryable(err)).to.equal(true)
		expect(err.kind).to.equal(ConnectionError.Kind.WebSocketTransport)
		expect(tostring(err)).to.equal("Connection closed")
	end)

	it("classifies protocol and sync errors as non-retryable", function()
		local protocolError = ConnectionError.nonRetryable(ConnectionError.Kind.Protocol, "Wrong protocol")
		local syncError = ConnectionError.nonRetryable(ConnectionError.Kind.Sync, "Patch failed")

		expect(ConnectionError.isRetryable(protocolError)).to.equal(false)
		expect(ConnectionError.isRetryable(syncError)).to.equal(false)
	end)

	it("preserves an existing structured error", function()
		local original = ConnectionError.retryable(ConnectionError.Kind.HttpTransport, "Server unavailable")

		expect(ConnectionError.nonRetryable(ConnectionError.Kind.Sync, original)).to.equal(original)
	end)
end
