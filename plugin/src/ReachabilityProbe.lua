local HttpService = game:GetService("HttpService")

local ReachabilityProbe = {}
ReachabilityProbe.__index = ReachabilityProbe

local function createClient(url)
	return HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
		Url = url,
	})
end

local function disconnect(connection)
	pcall(connection.Disconnect, connection)
end

function ReachabilityProbe.new(options)
	options = options or {}

	return setmetatable({
		__createClient = options.createClient or createClient,
		__delay = options.delay or task.delay,
		__cancelDelay = options.cancelDelay or task.cancel,
		__timeoutSeconds = options.timeoutSeconds or 5,
		__generation = 0,
		__client = nil,
		__timer = nil,
		__connections = {},
	}, ReachabilityProbe)
end

function ReachabilityProbe:__close()
	if self.__timer ~= nil then
		pcall(self.__cancelDelay, self.__timer)
		self.__timer = nil
	end

	for _, connection in self.__connections do
		disconnect(connection)
	end
	table.clear(self.__connections)

	if self.__client ~= nil then
		local client = self.__client
		self.__client = nil
		pcall(client.Close, client)
	end
end

function ReachabilityProbe:start(url, onOpened, onFailed)
	assert(type(url) == "string", "url must be a string")
	assert(type(onOpened) == "function", "onOpened must be a function")
	assert(type(onFailed) == "function", "onFailed must be a function")

	self:cancel()
	local generation = self.__generation
	local finished = false

	local function finish(opened, err)
		if finished or self.__generation ~= generation then
			return
		end

		finished = true
		self.__generation += 1
		self:__close()

		if opened then
			onOpened()
		else
			onFailed(err)
		end
	end

	local success, client = pcall(self.__createClient, url)
	if not success then
		finish(false, client)
		return function() end
	end

	self.__client = client
	table.insert(self.__connections, client.Opened:Connect(function()
		finish(true)
	end))
	table.insert(self.__connections, client.Error:Connect(function(code, message)
		finish(false, string.format("WebSocket error: %s - %s", tostring(code), tostring(message)))
	end))
	table.insert(self.__connections, client.Closed:Connect(function()
		finish(false, "WebSocket probe closed before opening")
	end))

	self.__timer = self.__delay(self.__timeoutSeconds, function()
		if self.__generation == generation then
			self.__timer = nil
		end
		finish(false, "WebSocket probe timed out")
	end)

	return function()
		if self.__generation == generation then
			self:cancel()
		end
	end
end

function ReachabilityProbe:cancel()
	self.__generation += 1
	self:__close()
end

return ReachabilityProbe
