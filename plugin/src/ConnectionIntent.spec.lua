return function()
	local ConnectionIntent = require(script.Parent.ConnectionIntent)

	it("uses Disconnect while a reconnect timer is pending without a session", function()
		expect(ConnectionIntent.resolve(nil, true)).to.equal(ConnectionIntent.Disconnect)
	end)

	it("uses Disconnect while a connection attempt is active", function()
		expect(ConnectionIntent.resolve("Connecting", true)).to.equal(ConnectionIntent.Disconnect)
	end)

	it("uses Connect when no session or reconnect is active", function()
		expect(ConnectionIntent.resolve(nil, false)).to.equal(ConnectionIntent.Connect)
		expect(ConnectionIntent.resolve("NotStarted", false)).to.equal(ConnectionIntent.Connect)
	end)

	it("uses Disconnect for an active session", function()
		expect(ConnectionIntent.resolve("Connecting", false)).to.equal(ConnectionIntent.Disconnect)
		expect(ConnectionIntent.resolve("Connected", false)).to.equal(ConnectionIntent.Disconnect)
	end)
end
