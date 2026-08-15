return function()
	local ReachabilityProbe = require(script.Parent.ReachabilityProbe)

	local function createSignal()
		local handlers = {}
		local signal = {}

		function signal:Connect(handler)
			local connection = {
				disconnected = false,
			}
			function connection.Disconnect()
				connection.disconnected = true
			end
			table.insert(handlers, {
				connection = connection,
				handler = handler,
			})
			return connection
		end

		function signal:Fire(...)
			for _, entry in handlers do
				if not entry.connection.disconnected then
					entry.handler(...)
				end
			end
		end

		return signal
	end

	local function createHarness()
		local scheduled = {}
		local cancelled = {}
		local clients = {}
		local urls = {}
		local probe = ReachabilityProbe.new({
			timeoutSeconds = 5,
			delay = function(seconds, callback)
				local timer = {
					seconds = seconds,
					callback = callback,
				}
				table.insert(scheduled, timer)
				return timer
			end,
			cancelDelay = function(timer)
				cancelled[timer] = true
			end,
			createClient = function(url)
				table.insert(urls, url)
				local client = {
					Opened = createSignal(),
					Error = createSignal(),
					Closed = createSignal(),
					closed = false,
				}
				function client:Close()
					self.closed = true
				end
				table.insert(clients, client)
				return client
			end,
		})

		return probe, scheduled, cancelled, clients, urls
	end

	it("closes one real client after the five-second deadline", function()
		local probe, scheduled, _, clients, urls = createHarness()
		local failures = 0

		probe:start("ws://localhost:34872/api/socket/0", function() end, function()
			failures += 1
		end)

		expect(urls[1]).to.equal("ws://localhost:34872/api/socket/0")
		expect(scheduled[1].seconds).to.equal(5)
		expect(clients[1].closed).to.equal(false)

		scheduled[1].callback()
		expect(clients[1].closed).to.equal(true)
		expect(failures).to.equal(1)
	end)

	it("closes an opened probe before continuing", function()
		local probe, scheduled, cancelled, clients = createHarness()
		local opened = 0
		local failures = 0

		probe:start("ws://localhost:34872/api/socket/0", function()
			opened += 1
		end, function()
			failures += 1
		end)
		clients[1].Opened:Fire(101, "")
		clients[1].Error:Fire(400, "late")

		expect(clients[1].closed).to.equal(true)
		expect(cancelled[scheduled[1]]).to.equal(true)
		expect(opened).to.equal(1)
		expect(failures).to.equal(0)
	end)

	it("cancels the client and ignores late callbacks", function()
		local probe, scheduled, _, clients = createHarness()
		local opened = 0
		local failures = 0

		local cancel = probe:start("ws://localhost:34872/api/socket/0", function()
			opened += 1
		end, function()
			failures += 1
		end)
		cancel()

		expect(clients[1].closed).to.equal(true)
		clients[1].Opened:Fire(101, "")
		clients[1].Error:Fire(400, "late")
		clients[1].Closed:Fire()
		scheduled[1].callback()

		expect(opened).to.equal(0)
		expect(failures).to.equal(0)
	end)
end
