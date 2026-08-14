return function()
	local Packages = script.Parent.Parent.Packages
	local Http = require(Packages.Http)

	local ConnectionError = require(script.Parent.ConnectionError)
	local HttpConnectionError = require(script.Parent.HttpConnectionError)

	it("classifies HTTP responses as non-retryable status errors", function()
		local response = {
			code = 500,
			body = "Server configuration failed",
		}
		local err = HttpConnectionError.classify(Http.Error.fromResponse(response))

		expect(ConnectionError.isRetryable(err)).to.equal(false)
		expect(err.kind).to.equal(ConnectionError.Kind.HttpStatus)
		expect(tostring(err)).to.equal("HTTP 500:\nServer configuration failed")
	end)

	it("preserves response metadata for timeout status responses", function()
		local response = {
			code = 504,
			body = "Gateway timed out",
		}
		local httpError = Http.Error.fromResponse(response)
		local err = HttpConnectionError.classify(httpError)

		expect(httpError.response).to.equal(response)
		expect(ConnectionError.isRetryable(err)).to.equal(false)
		expect(err.kind).to.equal(ConnectionError.Kind.HttpStatus)
	end)

	it("classifies connection, timeout, and unknown transport failures as retryable", function()
		local transportKinds = {
			Http.Error.Kind.ConnectFailed,
			Http.Error.Kind.Timeout,
			Http.Error.Kind.Unknown,
		}

		for _, kind in transportKinds do
			local err = HttpConnectionError.classify(Http.Error.new(kind, "transport failure"))

			expect(ConnectionError.isRetryable(err)).to.equal(true)
			expect(err.kind).to.equal(ConnectionError.Kind.HttpTransport)
		end
	end)

	it("classifies disabled HTTP access as a non-retryable configuration error", function()
		local err = HttpConnectionError.classify(Http.Error.new(Http.Error.Kind.HttpNotEnabled))

		expect(ConnectionError.isRetryable(err)).to.equal(false)
		expect(err.kind).to.equal(ConnectionError.Kind.Configuration)
	end)
end
