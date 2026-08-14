return function()
	local Packages = script.Parent.Parent.Packages
	local Promise = require(Packages.Promise)

	local ConnectionError = require(script.Parent.ConnectionError)
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
end
