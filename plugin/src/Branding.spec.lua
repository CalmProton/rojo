return function()
	local Branding = require(script.Parent.Branding)

	it("identifies the installed BlokBlok fork", function()
		expect(Branding.displayName).to.equal("Rojo 7.7.0 - BlokBlok Fork")
	end)
end
