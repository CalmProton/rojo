return function()
	local RequestOptions = require(script.Parent.RequestOptions)

	it("leaves the engine timeout unchanged by default", function()
		local requestParams = RequestOptions.apply({
			Url = "http://localhost:34872/api/rojo",
			Method = "GET",
		})

		expect(requestParams.Timeout).to.equal(nil)
	end)

	it("sets a native request timeout", function()
		local requestParams = RequestOptions.apply({
			Url = "http://localhost:34872/api/rojo",
			Method = "GET",
		}, {
			timeoutSeconds = 5,
		})

		expect(requestParams.Timeout).to.equal(5)
	end)

	it("rejects timeout values that HttpService does not accept", function()
		local success = pcall(RequestOptions.apply, {}, {
			timeoutSeconds = 0.5,
		})

		expect(success).to.equal(false)
	end)
end
