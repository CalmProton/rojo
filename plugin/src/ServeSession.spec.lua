return function()
	local Packages = script.Parent.Parent.Packages
	local Promise = require(Packages.Promise)

	local ConnectionError = require(script.Parent.ConnectionError)
	local PatchSet = require(script.Parent.PatchSet)
	local ServeSession = require(script.Parent.ServeSession)

	it("rejects a changed server identity before initial sync", function()
		local disconnectedError
		local apiContext = {
			connect = function()
				return Promise.resolve({
					projectName = "different-project",
				})
			end,
			disconnect = function() end,
		}
		local session = ServeSession.new({
			apiContext = apiContext,
			twoWaySync = false,
			expectedProjectName = "expected-project",
		})
		session:onStatusChanged(function(status, details)
			if status == ServeSession.Status.Disconnected then
				disconnectedError = details
			end
		end)

		session:start()
		task.wait()

		expect(disconnectedError).to.be.ok()
		expect(ConnectionError.isRetryable(disconnectedError)).to.equal(false)
		expect(disconnectedError.kind).to.equal(ConnectionError.Kind.ServerIdentity)
	end)

	it("ignores metadata that resolves after teardown", function()
		local resolveConnect
		local initialSyncStarted = false
		local webSocketStarted = false
		local connected = false
		local apiContext = {
			connect = function()
				return Promise.new(function(resolve)
					resolveConnect = resolve
				end)
			end,
			disconnect = function() end,
			connectWebSocket = function()
				webSocketStarted = true
				return Promise.resolve()
			end,
		}
		local session = ServeSession.new({
			apiContext = apiContext,
			twoWaySync = false,
		})
		session.__initialSync = function()
			initialSyncStarted = true
			return Promise.resolve()
		end
		session:onStatusChanged(function(status)
			if status == ServeSession.Status.Connected then
				connected = true
			end
		end)

		session:start()
		task.wait()
		session:stop()
		resolveConnect({
			projectName = "project",
			rootInstanceId = "root",
		})
		task.wait()

		expect(initialSyncStarted).to.equal(false)
		expect(webSocketStarted).to.equal(false)
		expect(connected).to.equal(false)
	end)

	it("does not connect after initial sync finishes late", function()
		local resolveInitialSync
		local webSocketStarted = false
		local idsApplied = false
		local connected = false
		local apiContext = {
			connect = function()
				return Promise.resolve({
					projectName = "project",
					rootInstanceId = "root",
				})
			end,
			disconnect = function() end,
			connectWebSocket = function()
				webSocketStarted = true
				return Promise.resolve()
			end,
		}
		local session = ServeSession.new({
			apiContext = apiContext,
			twoWaySync = false,
		})
		session.__initialSync = function()
			return Promise.new(function(resolve)
				resolveInitialSync = resolve
			end)
		end
		session.__applyGameAndPlaceId = function()
			idsApplied = true
		end
		session:onStatusChanged(function(status)
			if status == ServeSession.Status.Connected then
				connected = true
			end
		end)

		session:start()
		task.wait()
		session:stop()
		resolveInitialSync()
		task.wait()

		expect(webSocketStarted).to.equal(false)
		expect(idsApplied).to.equal(false)
		expect(connected).to.equal(false)
	end)

	it("does not apply after teardown during confirmation", function()
		local patchApplied = false
		local webSocketStarted = false
		local apiContext = {
			connect = function()
				return Promise.resolve({
					projectName = "project",
					rootInstanceId = "root",
				})
			end,
			read = function()
				return Promise.resolve({
					messageCursor = 0,
					instances = {},
				})
			end,
			setMessageCursor = function() end,
			disconnect = function() end,
			connectWebSocket = function()
				webSocketStarted = true
				return Promise.resolve()
			end,
		}
		local session = ServeSession.new({
			apiContext = apiContext,
			twoWaySync = false,
		})
		session.__reconciler = {
			hydrate = function() end,
			diff = function()
				return true, PatchSet.newEmpty()
			end,
		}
		session.__applyPatch = function()
			patchApplied = true
		end
		session:setConfirmCallback(function()
			session:stop()
			return "Accept"
		end)

		session:start()
		task.wait()

		expect(patchApplied).to.equal(false)
		expect(webSocketStarted).to.equal(false)
		expect(session:getStatus()).to.equal(ServeSession.Status.Disconnected)
	end)

	it("does not apply after a precommit callback tears down the session", function()
		local patchApplied = false
		local webSocketStarted = false
		local apiContext = {
			connect = function()
				return Promise.resolve({
					projectName = "project",
					rootInstanceId = "root",
				})
			end,
			read = function()
				return Promise.resolve({
					messageCursor = 0,
					instances = {},
				})
			end,
			setMessageCursor = function() end,
			disconnect = function() end,
			connectWebSocket = function()
				webSocketStarted = true
				return Promise.resolve()
			end,
		}
		local session = ServeSession.new({
			apiContext = apiContext,
			twoWaySync = false,
		})
		session.__reconciler = {
			hydrate = function() end,
			diff = function()
				return true, PatchSet.newEmpty()
			end,
			applyPatch = function()
				patchApplied = true
				return PatchSet.newEmpty()
			end,
		}
		session:hookPrecommit(function()
			session:stop()
		end)

		session:start()
		task.wait()

		expect(patchApplied).to.equal(false)
		expect(webSocketStarted).to.equal(false)
		expect(session:getStatus()).to.equal(ServeSession.Status.Disconnected)
	end)

	it("does not mutate after a Connected callback tears down the session", function()
		local idsApplied = false
		local webSocketStarted = false
		local setupFinished = false
		local apiContext = {
			connect = function()
				return Promise.resolve({
					projectName = "project",
					rootInstanceId = "root",
				})
			end,
			finishConnecting = function()
				setupFinished = true
			end,
			disconnect = function() end,
			connectWebSocket = function()
				webSocketStarted = true
				return Promise.resolve()
			end,
		}
		local session = ServeSession.new({
			apiContext = apiContext,
			twoWaySync = false,
		})
		session.__initialSync = function()
			return Promise.resolve()
		end
		session.__applyGameAndPlaceId = function()
			idsApplied = true
		end
		session:onStatusChanged(function(status)
			if status == ServeSession.Status.Connected then
				session:stop()
			end
		end)

		session:start()
		task.wait()

		expect(setupFinished).to.equal(true)
		expect(idsApplied).to.equal(false)
		expect(webSocketStarted).to.equal(false)
		expect(session:getStatus()).to.equal(ServeSession.Status.Disconnected)
	end)
end
