local Packages = script.Parent.Parent.Packages
local Http = require(Packages.Http)

local ConnectionError = require(script.Parent.ConnectionError)

local HttpConnectionError = {}

function HttpConnectionError.classify(err)
	if Http.Error.is(err) then
		if err.response ~= nil then
			local message = string.format(
				"HTTP %s:\n%s",
				tostring(err.response.code),
				tostring(err.response.body)
			)
			return ConnectionError.nonRetryable(ConnectionError.Kind.HttpStatus, message)
		end

		if err.type == Http.Error.Kind.HttpNotEnabled then
			return ConnectionError.nonRetryable(ConnectionError.Kind.Configuration, err)
		end
	end

	return ConnectionError.retryable(ConnectionError.Kind.HttpTransport, err)
end

return HttpConnectionError
