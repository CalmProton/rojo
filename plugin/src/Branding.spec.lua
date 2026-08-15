return function()
	local Branding = require(script.Parent.Branding)

	it("identifies the installed Blokblok fork", function()
		expect(Branding.displayName).to.equal("Rojo 7.7.0 — Blokblok Auto-Reconnect")
	end)
end
