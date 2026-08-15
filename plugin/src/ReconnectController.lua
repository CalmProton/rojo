local ReconnectController = {}
ReconnectController.__index = ReconnectController

function ReconnectController.new(options)
	assert(type(options) == "table", "options must be a table")
	assert(type(options.connect) == "function", "options.connect must be a function")

	return setmetatable({
		__connect = options.connect,
		__delay = options.delay or task.delay,
		__cancelDelay = options.cancelDelay or task.cancel,
		__clock = options.clock or os.clock,
		__delaySeconds = options.delaySeconds or 5,
		__generation = 0,
		__target = nil,
		__timer = nil,
		__attemptInFlight = false,
		__attemptStartedAt = nil,
	}, ReconnectController)
end

function ReconnectController:__scheduleAfter(target, delaySeconds)
	if self.__timer ~= nil or self.__attemptInFlight then
		return false
	end

	self.__target = target
	local generation = self.__generation
	self.__timer = self.__delay(delaySeconds, function()
		if self.__generation ~= generation or self.__target ~= target then
			return
		end

		self.__timer = nil
		self.__attemptInFlight = true
		self.__attemptStartedAt = self.__clock()
		self.__connect(target)
	end)

	return true, delaySeconds
end

function ReconnectController:schedule(target)
	assert(type(target) == "table" and type(target.key) == "string", "target.key must be a string")

	if self.__target ~= nil and self.__target.key ~= target.key then
		return false
	end

	return self:__scheduleAfter(target, self.__delaySeconds)
end

function ReconnectController:attemptFailed(target)
	if self.__target ~= target or not self.__attemptInFlight then
		return false
	end

	-- Keep attempt starts on the configured cadence. A fast failure waits for the
	-- rest of the interval. An attempt that reaches its deadline retries now.
	local attemptDuration = math.max(0, self.__clock() - self.__attemptStartedAt)
	local delaySeconds = math.max(0, self.__delaySeconds - attemptDuration)
	self.__attemptInFlight = false
	self.__attemptStartedAt = nil
	return self:__scheduleAfter(target, delaySeconds)
end

function ReconnectController:cancel()
	self.__generation += 1
	self.__target = nil
	self.__attemptInFlight = false
	self.__attemptStartedAt = nil

	if self.__timer ~= nil then
		pcall(self.__cancelDelay, self.__timer)
		self.__timer = nil
	end
end

function ReconnectController:isAttemptInFlight()
	return self.__attemptInFlight
end

function ReconnectController:hasPendingWork()
	return self.__timer ~= nil or self.__attemptInFlight
end

return ReconnectController
