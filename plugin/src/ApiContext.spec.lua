return function()
	local Packages = script.Parent.Parent.Packages
	local Http = require(Packages.Http)
	local Promise = require(Packages.Promise)

	local ApiContext = require(script.Parent.ApiContext)

	local originalGet = Http.get
	local originalPost = Http.post
	afterEach(function()
		Http.get = originalGet
		Http.post = originalPost
	end)

	it("passes the native deadline to a reconnect probe", function()
		local capturedOptions
		local resolveRequest
		local continued = false
		Http.get = function(_, options)
			capturedOptions = options
			return Promise.new(function(resolve)
				resolveRequest = resolve
			end)
		end

		local apiContext = ApiContext.new("http://localhost:34872", {
			connectTimeoutSeconds = 5,
		})
		apiContext:connect():andThen(function()
			continued = true
		end)
		task.wait()
		apiContext:disconnect()
		resolveRequest({})
		task.wait()

		expect(capturedOptions.timeoutSeconds).to.equal(5)
		expect(continued).to.equal(false)
	end)

	it("suppresses a read that finishes after disconnect", function()
		local resolveRequest
		local continued = false
		Http.get = function()
			return Promise.new(function(resolve)
				resolveRequest = resolve
			end)
		end

		local apiContext = ApiContext.new("http://localhost:34872")
		apiContext:read({ "root" }):andThen(function()
			continued = true
		end)
		task.wait()
		apiContext:disconnect()
		resolveRequest({})
		task.wait()

		expect(continued).to.equal(false)
	end)

	it("queues replacement metadata until a cancelled setup read settles", function()
		local lane = Http.RequestLane.new()
		local settleRead
		local settleMetadata
		local metadataStarted = false
		Http.get = function(url, options)
			return options.requestLane:request(function(_, _, settle)
				if string.find(url, "/api/read/") then
					settleRead = settle
				else
					metadataStarted = true
					settleMetadata = settle
				end
			end)
		end

		local initialContext = ApiContext.new("http://localhost:34872", {
			connectRequestLane = lane,
		})
		initialContext:read({ "root" })
		task.wait()
		initialContext:disconnect()

		local replacementContext = ApiContext.new("http://localhost:34872", {
			connectRequestLane = lane,
			connectTimeoutSeconds = 5,
		})
		replacementContext:connect()
		task.wait()
		expect(metadataStarted).to.equal(false)

		settleRead()
		task.wait()
		expect(metadataStarted).to.equal(true)

		replacementContext:disconnect()
		settleMetadata()
	end)

	it("releases ordinary traffic from the setup lane", function()
		local capturedOptions
		Http.post = function(_, _, options)
			capturedOptions = options
			return Promise.new(function() end)
		end

		local apiContext = ApiContext.new("http://localhost:34872", {
			connectRequestLane = Http.RequestLane.new(),
		})
		apiContext:finishConnecting()
		apiContext:open("id")
		task.wait()

		expect(capturedOptions.requestLane).to.equal(nil)
		apiContext:disconnect()
	end)
end
