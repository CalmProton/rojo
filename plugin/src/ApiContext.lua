local Packages = script.Parent.Parent.Packages
local HttpService = game:GetService("HttpService")
local Http = require(Packages.Http)
local Log = require(Packages.Log)
local Promise = require(Packages.Promise)

local Config = require(script.Parent.Config)
local ConnectionError = require(script.Parent.ConnectionError)
local HttpConnectionError = require(script.Parent.HttpConnectionError)
local Types = require(script.Parent.Types)
local Version = require(script.Parent.Version)

local validateApiInfo = Types.ifEnabled(Types.ApiInfoResponse)
local validateApiRead = Types.ifEnabled(Types.ApiReadResponse)
local validateApiSocketPacket = Types.ifEnabled(Types.ApiSocketPacket)
local validateApiSerialize = Types.ifEnabled(Types.ApiSerializeResponse)
local validateApiRefPatch = Types.ifEnabled(Types.ApiRefPatchResponse)

local function rejectTransportError(err)
	return Promise.reject(HttpConnectionError.classify(err))
end

local function disconnectedError()
	return ConnectionError.nonRetryable(ConnectionError.Kind.Sync, "Connection was stopped.")
end

local function rejectWrongProtocolVersion(infoResponseBody)
	if infoResponseBody.protocolVersion ~= Config.protocolVersion then
		local message = (
			"Found a Rojo dev server, but it's using a different protocol version, and is incompatible."
			.. "\nMake sure you have matching versions of both the Rojo plugin and server!"
			.. "\n\nYour client is version %s, with protocol version %s. It expects server version %s."
			.. "\nYour server is version %s, with protocol version %s."
			.. "\n\nGo to https://github.com/rojo-rbx/rojo for more details."
		):format(
			Version.display(Config.version),
			Config.protocolVersion,
			Config.expectedServerVersionString,
			infoResponseBody.serverVersion,
			infoResponseBody.protocolVersion
		)

		return Promise.reject(ConnectionError.nonRetryable(ConnectionError.Kind.Protocol, message))
	end

	return Promise.resolve(infoResponseBody)
end

local function rejectWrongPlaceId(infoResponseBody)
	if infoResponseBody.expectedPlaceIds ~= nil then
		local foundId = table.find(infoResponseBody.expectedPlaceIds, game.PlaceId)

		if not foundId then
			local idList = {}
			for _, id in ipairs(infoResponseBody.expectedPlaceIds) do
				table.insert(idList, "- " .. tostring(id))
			end

			local message = (
				"Found a Rojo server, but its project is set to only be used with a specific list of places."
				.. "\nYour place ID is %u, but needs to be one of these:"
				.. "\n%s"
				.. "\n\nTo change this list, edit 'servePlaceIds' in your .project.json file."
			):format(game.PlaceId, table.concat(idList, "\n"))

			return Promise.reject(ConnectionError.nonRetryable(ConnectionError.Kind.Place, message))
		end
	end

	if infoResponseBody.unexpectedPlaceIds ~= nil then
		local foundId = table.find(infoResponseBody.unexpectedPlaceIds, game.PlaceId)

		if foundId then
			local idList = {}
			for _, id in ipairs(infoResponseBody.unexpectedPlaceIds) do
				table.insert(idList, "- " .. tostring(id))
			end

			local message = (
				"Found a Rojo server, but its project is set to not be used with a specific list of places."
				.. "\nYour place ID is %u, but needs to not be one of these:"
				.. "\n%s"
				.. "\n\nTo change this list, edit 'blockedPlaceIds' in your .project.json file."
			):format(game.PlaceId, table.concat(idList, "\n"))

			return Promise.reject(ConnectionError.nonRetryable(ConnectionError.Kind.Place, message))
		end
	end

	return Promise.resolve(infoResponseBody)
end

local ApiContext = {}
ApiContext.__index = ApiContext

function ApiContext.new(baseUrl, options)
	assert(type(baseUrl) == "string", "baseUrl must be a string")
	options = options or {}
	assert(type(options) == "table", "options must be a table")
	assert(
		options.connectTimeoutSeconds == nil
			or (
				type(options.connectTimeoutSeconds) == "number"
				and options.connectTimeoutSeconds > 0
				and options.connectTimeoutSeconds % 1 == 0
			),
		"options.connectTimeoutSeconds must be a positive integer"
	)
	assert(
		options.connectRequestLane == nil or type(options.connectRequestLane) == "table",
		"options.connectRequestLane must be a table"
	)

	local self = {
		__baseUrl = baseUrl,
		__connectRequestLane = options.connectRequestLane,
		__connectTimeoutSeconds = options.connectTimeoutSeconds,
		__sessionId = nil,
		__messageCursor = -1,
		__wsClient = nil,
		__connected = true,
		__activeRequests = {},
	}

	return setmetatable(self, ApiContext)
end

function ApiContext:__fmtDebug(output)
	output:writeLine("ApiContext {{")
	output:indent()

	output:writeLine("Connected: {}", self.__connected)
	output:writeLine("Base URL: {}", self.__baseUrl)
	output:writeLine("Session ID: {}", self.__sessionId)
	output:writeLine("Message Cursor: {}", self.__messageCursor)

	output:unindent()
	output:write("}")
end

function ApiContext:disconnect()
	self.__connected = false
	local activeRequests = self.__activeRequests
	self.__activeRequests = {}
	for request in activeRequests do
		Log.trace("Cancelling request {}", request)
		request:cancel()
	end

	if self.__wsClient then
		Log.trace("Closing WebSocket client")
		self.__wsClient:Close()
	end
	self.__wsClient = nil
end

function ApiContext:__trackRequest(request)
	self.__activeRequests[request] = true
	request
		:finally(function()
			self.__activeRequests[request] = nil
		end)
		:catch(function() end)

	return request
end

function ApiContext:__continueIfConnected(value)
	if not self.__connected then
		return Promise.reject(disconnectedError())
	end

	return value
end

function ApiContext:finishConnecting()
	-- Setup requests share one lane with replacement metadata probes. Connected
	-- session traffic does not need this serialization.
	self.__connectRequestLane = nil
end

function ApiContext:setMessageCursor(index)
	self.__messageCursor = index
end

function ApiContext:connect()
	if not self.__connected then
		return Promise.reject(disconnectedError())
	end

	local url = ("%s/api/rojo"):format(self.__baseUrl)

	return self:__trackRequest(Http.get(url, {
		requestLane = self.__connectRequestLane,
		timeoutSeconds = self.__connectTimeoutSeconds,
	})
		:catch(rejectTransportError)
		:andThen(function(response)
			return self:__continueIfConnected(response)
		end)
		:andThen(Http.Response.msgpack)
		:andThen(rejectWrongProtocolVersion)
		:andThen(function(body)
			assert(validateApiInfo(body))

			return body
		end)
		:andThen(rejectWrongPlaceId)
		:andThen(function(body)
			local connectedBody = self:__continueIfConnected(body)
			if Promise.is(connectedBody) then
				return connectedBody
			end

			self.__sessionId = body.sessionId

			return body
		end))
end

function ApiContext:read(ids)
	if not self.__connected then
		return Promise.reject(disconnectedError())
	end

	local url = ("%s/api/read/%s"):format(self.__baseUrl, table.concat(ids, ","))

	return self:__trackRequest(Http.get(url, {
		requestLane = self.__connectRequestLane,
	})
		:catch(rejectTransportError)
		:andThen(Http.Response.msgpack)
		:andThen(function(body)
			local connectedBody = self:__continueIfConnected(body)
			if Promise.is(connectedBody) then
				return connectedBody
			end

			if body.sessionId ~= self.__sessionId then
				return Promise.reject("Server changed ID")
			end

			assert(validateApiRead(body))

			return body
		end))
end

function ApiContext:write(patch)
	if not self.__connected then
		return Promise.reject(disconnectedError())
	end

	local url = ("%s/api/write"):format(self.__baseUrl)

	local updated = {}
	for _, update in ipairs(patch.updated) do
		local fixedUpdate = {
			id = update.id,
			changedName = update.changedName,
		}

		if next(update.changedProperties) ~= nil then
			fixedUpdate.changedProperties = update.changedProperties
		end

		table.insert(updated, fixedUpdate)
	end

	-- Only add the 'added' field if the table is non-empty, or else the msgpack
	-- encode implementation will turn the table into an array instead of a map,
	-- causing API validation to fail.
	local added
	if next(patch.added) ~= nil then
		added = patch.added
	end

	local body = {
		sessionId = self.__sessionId,
		removed = patch.removed,
		updated = updated,
		added = added,
	}

	body = Http.msgpackEncode(body)

	return self:__trackRequest(Http.post(url, body, {
		requestLane = self.__connectRequestLane,
	})
		:catch(rejectTransportError)
		:andThen(Http.Response.msgpack)
		:andThen(function(responseBody)
			local connectedBody = self:__continueIfConnected(responseBody)
			if Promise.is(connectedBody) then
				return connectedBody
			end

			Log.info("Write response: {:?}", responseBody)

			return responseBody
		end))
end

function ApiContext:connectWebSocket(packetHandlers)
	local url = ("%s/api/socket/%s"):format(self.__baseUrl, self.__messageCursor)
	-- Convert HTTP/HTTPS URL to WS/WSS
	url = url:gsub("^http://", "ws://"):gsub("^https://", "wss://")

	if not self.__connected then
		return Promise.reject(disconnectedError())
	end

	return self:__trackRequest(Promise.new(function(resolve, reject)
		if not self.__connected then
			reject(disconnectedError())
			return
		end

		local success, wsClient =
			pcall(HttpService.CreateWebStreamClient, HttpService, Enum.WebStreamClientType.WebSocket, {
				Url = url,
			})
		if not success then
			reject(
				ConnectionError.retryable(
					ConnectionError.Kind.WebSocketTransport,
					"Failed to create WebSocket client: " .. tostring(wsClient)
				)
			)
			return
		end
		self.__wsClient = wsClient

		local closed, errored, received

		received = self.__wsClient.MessageReceived:Connect(function(msg)
			if not self.__connected then
				return
			end

			local data = Http.msgpackDecode(msg)
			if data.sessionId ~= self.__sessionId then
				Log.warn("Received message with wrong session ID; ignoring")
				return
			end

			assert(validateApiSocketPacket(data))

			Log.trace("Received websocket packet: {:#?}", data)

			local handler = packetHandlers[data.packetType]
			if handler then
				local ok, err = pcall(handler, data.body)
				if not ok then
					Log.error("Error in WebSocket packet handler for type '%s': %s", data.packetType, err)
				end
			else
				Log.warn("No handler for WebSocket packet type '%s'", data.packetType)
			end
		end)

		closed = self.__wsClient.Closed:Connect(function()
			closed:Disconnect()
			errored:Disconnect()
			received:Disconnect()

			if self.__connected then
				reject(
					ConnectionError.retryable(
						ConnectionError.Kind.WebSocketTransport,
						"WebSocket connection closed unexpectedly"
					)
				)
			else
				resolve()
			end
		end)

		errored = self.__wsClient.Error:Connect(function(code, msg)
			closed:Disconnect()
			errored:Disconnect()
			received:Disconnect()

			if self.__connected then
				reject(
					ConnectionError.retryable(
						ConnectionError.Kind.WebSocketTransport,
						"WebSocket error: " .. code .. " - " .. msg
					)
				)
			else
				resolve()
			end
		end)
	end))
end

function ApiContext:open(id)
	if not self.__connected then
		return Promise.reject(disconnectedError())
	end

	local url = ("%s/api/open/%s"):format(self.__baseUrl, id)

	return self:__trackRequest(Http.post(url, "", {
		requestLane = self.__connectRequestLane,
	})
		:catch(rejectTransportError)
		:andThen(Http.Response.msgpack)
		:andThen(function(body)
			local connectedBody = self:__continueIfConnected(body)
			if Promise.is(connectedBody) then
				return connectedBody
			end

			if body.sessionId ~= self.__sessionId then
				return Promise.reject("Server changed ID")
			end

			return nil
		end))
end

function ApiContext:serialize(ids: { string })
	if not self.__connected then
		return Promise.reject(disconnectedError())
	end

	local url = ("%s/api/serialize"):format(self.__baseUrl)
	local request_body = Http.msgpackEncode({ sessionId = self.__sessionId, ids = ids })

	return self:__trackRequest(Http.post(url, request_body, {
		requestLane = self.__connectRequestLane,
	})
		:catch(rejectTransportError)
		:andThen(Http.Response.msgpack)
		:andThen(function(response_body)
			local connectedBody = self:__continueIfConnected(response_body)
			if Promise.is(connectedBody) then
				return connectedBody
			end

			if response_body.sessionId ~= self.__sessionId then
				return Promise.reject("Server changed ID")
			end

			assert(validateApiSerialize(response_body))

			return response_body
		end))
end

function ApiContext:refPatch(ids: { string })
	if not self.__connected then
		return Promise.reject(disconnectedError())
	end

	local url = ("%s/api/ref-patch"):format(self.__baseUrl)
	local request_body = Http.msgpackEncode({ sessionId = self.__sessionId, ids = ids })

	return self:__trackRequest(Http.post(url, request_body, {
		requestLane = self.__connectRequestLane,
	})
		:catch(rejectTransportError)
		:andThen(Http.Response.msgpack)
		:andThen(function(response_body)
			local connectedBody = self:__continueIfConnected(response_body)
			if Promise.is(connectedBody) then
				return connectedBody
			end

			if response_body.sessionId ~= self.__sessionId then
				return Promise.reject("Server changed ID")
			end

			assert(validateApiRefPatch(response_body))

			return response_body
		end))
end

return ApiContext
