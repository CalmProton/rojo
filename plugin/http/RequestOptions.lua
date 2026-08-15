local RequestOptions = {}

function RequestOptions.apply(requestParams, options)
	assert(type(requestParams) == "table", "requestParams must be a table")

	if options == nil then
		return requestParams
	end

	assert(type(options) == "table", "options must be a table")
	if options.timeoutSeconds ~= nil then
		assert(
			type(options.timeoutSeconds) == "number"
				and options.timeoutSeconds > 0
				and options.timeoutSeconds % 1 == 0,
			"options.timeoutSeconds must be a positive integer"
		)
		requestParams.Timeout = options.timeoutSeconds
	end

	return requestParams
end

return RequestOptions
