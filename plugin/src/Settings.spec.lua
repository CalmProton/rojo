return function()
	local Settings = require(script.Parent.Settings)

	it("enables Auto Reconnect by default and preserves an explicit disable", function()
		expect(Settings:get("autoReconnect")).to.equal(true)

		Settings:set("autoReconnect", false)
		expect(Settings:get("autoReconnect")).to.equal(false)

		Settings:set("autoReconnect", true)
	end)
end
