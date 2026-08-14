local ConnectionError = {}
ConnectionError.__index = ConnectionError

ConnectionError.Category = {
	RetryableTransport = "RetryableTransport",
	NonRetryable = "NonRetryable",
}

ConnectionError.Kind = {
	HttpTransport = "HttpTransport",
	WebSocketTransport = "WebSocketTransport",
	HttpStatus = "HttpStatus",
	Configuration = "Configuration",
	Protocol = "Protocol",
	Place = "Place",
	ServerIdentity = "ServerIdentity",
	Sync = "Sync",
}

function ConnectionError.new(category, kind, message)
	assert(ConnectionError.Category[category] ~= nil, "category must be a ConnectionError.Category")
	assert(ConnectionError.Kind[kind] ~= nil, "kind must be a ConnectionError.Kind")

	return setmetatable({
		category = category,
		kind = kind,
		message = tostring(message),
	}, ConnectionError)
end

function ConnectionError.retryable(kind, message)
	return ConnectionError.new(ConnectionError.Category.RetryableTransport, kind, message)
end

function ConnectionError.nonRetryable(kind, message)
	if ConnectionError.is(message) then
		return message
	end

	return ConnectionError.new(ConnectionError.Category.NonRetryable, kind, message)
end

function ConnectionError.is(value)
	return getmetatable(value) == ConnectionError
end

function ConnectionError.isRetryable(value)
	return ConnectionError.is(value) and value.category == ConnectionError.Category.RetryableTransport
end

function ConnectionError:__tostring()
	return self.message
end

return ConnectionError
