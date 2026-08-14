return function()
	local ReconnectController = require(script.Parent.ReconnectController)

	local function createHarness()
		local scheduled = {}
		local cancelled = {}
		local attempts = {}
		local controller = ReconnectController.new({
			delaySeconds = 5,
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
			connect = function(target)
				table.insert(attempts, target)
			end,
		})

		return controller, scheduled, cancelled, attempts
	end

	it("waits five seconds before one connection attempt", function()
		local controller, scheduled, _, attempts = createHarness()
		local target = { key = "localhost:34872" }

		expect(controller:schedule(target)).to.equal(true)
		expect(controller:schedule(target)).to.equal(false)
		expect(#scheduled).to.equal(1)
		expect(scheduled[1].seconds).to.equal(5)
		expect(#attempts).to.equal(0)

		scheduled[1].callback()
		expect(#attempts).to.equal(1)
		expect(attempts[1]).to.equal(target)
		expect(controller:isAttemptInFlight()).to.equal(true)
	end)

	it("schedules one new attempt after each retryable failure", function()
		local controller, scheduled, _, attempts = createHarness()
		local target = { key = "localhost:34872" }

		controller:schedule(target)
		scheduled[1].callback()
		expect(controller:attemptFailed(target)).to.equal(true)
		expect(#scheduled).to.equal(2)
		expect(controller:attemptFailed(target)).to.equal(false)

		scheduled[2].callback()
		expect(controller:attemptFailed(target)).to.equal(true)
		expect(#scheduled).to.equal(3)
		expect(#attempts).to.equal(2)
	end)

	it("cancels a pending timer", function()
		local controller, scheduled, cancelled, attempts = createHarness()
		local target = { key = "localhost:34872" }

		controller:schedule(target)
		controller:cancel()
		expect(cancelled[scheduled[1]]).to.equal(true)

		scheduled[1].callback()
		expect(#attempts).to.equal(0)
		expect(controller:hasPendingWork()).to.equal(false)
	end)

	it("does not replace an active target", function()
		local controller, scheduled = createHarness()

		expect(controller:schedule({ key = "localhost:34872" })).to.equal(true)
		expect(controller:schedule({ key = "localhost:34873" })).to.equal(false)
		expect(#scheduled).to.equal(1)
	end)

	it("cancels the retry owner after a successful attempt", function()
		local controller, scheduled = createHarness()
		local target = { key = "localhost:34872" }

		controller:schedule(target)
		scheduled[1].callback()
		controller:cancel()

		expect(controller:attemptFailed(target)).to.equal(false)
		expect(controller:hasPendingWork()).to.equal(false)
	end)
end
