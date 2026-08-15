return function()
	local ReconnectController = require(script.Parent.ReconnectController)

	local function createHarness()
		local scheduled = {}
		local cancelled = {}
		local attempts = {}
		local probes = {}
		local now = 0
		local controller = ReconnectController.new({
			delaySeconds = 5,
			clock = function()
				return now
			end,
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
			probe = function(target, onOpened, onFailed)
				local probe = {
					target = target,
					onOpened = onOpened,
					onFailed = onFailed,
					cancelled = false,
				}
				table.insert(probes, probe)
				return function()
					probe.cancelled = true
				end
			end,
			connect = function(target)
				table.insert(attempts, target)
			end,
		})

		return controller, scheduled, cancelled, probes, attempts, function(value)
			now = value
		end
	end

	it("waits five seconds and opens a probe before HTTP setup", function()
		local controller, scheduled, _, probes, attempts = createHarness()
		local target = { key = "localhost:34872" }

		expect(controller:schedule(target)).to.equal(true)
		expect(controller:schedule(target)).to.equal(false)
		expect(#scheduled).to.equal(1)
		expect(scheduled[1].seconds).to.equal(5)

		scheduled[1].callback()
		expect(#probes).to.equal(1)
		expect(#attempts).to.equal(0)

		probes[1].onOpened()
		expect(#attempts).to.equal(1)
		expect(attempts[1]).to.equal(target)
		expect(controller:isAttemptInFlight()).to.equal(true)
	end)

	it("starts a new probe on each five-second deadline", function()
		local controller, scheduled, _, probes, attempts, setNow = createHarness()
		local target = { key = "localhost:34872" }

		controller:schedule(target)
		setNow(5)
		scheduled[1].callback()
		setNow(10)
		probes[1].onFailed("deadline")

		expect(#scheduled).to.equal(2)
		expect(scheduled[2].seconds).to.equal(0)
		scheduled[2].callback()
		expect(#probes).to.equal(2)
		expect(#attempts).to.equal(0)
	end)

	it("schedules one new probe after each retryable HTTP failure", function()
		local controller, scheduled, _, probes, attempts = createHarness()
		local target = { key = "localhost:34872" }

		controller:schedule(target)
		scheduled[1].callback()
		probes[1].onOpened()
		expect(controller:attemptFailed(target)).to.equal(true)
		expect(#scheduled).to.equal(2)
		expect(controller:attemptFailed(target)).to.equal(false)

		scheduled[2].callback()
		probes[2].onOpened()
		expect(controller:attemptFailed(target)).to.equal(true)
		expect(#scheduled).to.equal(3)
		expect(#attempts).to.equal(2)
	end)

	it("keeps attempt starts on a five-second cadence", function()
		local controller, scheduled, _, probes, _, setNow = createHarness()
		local target = { key = "localhost:34872" }

		controller:schedule(target)
		setNow(5)
		scheduled[1].callback()
		probes[1].onOpened()
		setNow(7)
		local scheduledRetry, delaySeconds = controller:attemptFailed(target)

		expect(scheduledRetry).to.equal(true)
		expect(delaySeconds).to.equal(3)
		expect(scheduled[2].seconds).to.equal(3)
	end)

	it("cancels a pending timer", function()
		local controller, scheduled, cancelled, _, attempts = createHarness()
		local target = { key = "localhost:34872" }

		controller:schedule(target)
		controller:cancel()
		expect(cancelled[scheduled[1]]).to.equal(true)

		scheduled[1].callback()
		expect(#attempts).to.equal(0)
		expect(controller:hasPendingWork()).to.equal(false)
	end)

	it("closes an active probe and ignores its late callbacks", function()
		local controller, scheduled, _, probes, attempts = createHarness()
		local target = { key = "localhost:34872" }

		controller:schedule(target)
		scheduled[1].callback()
		controller:cancel()

		expect(probes[1].cancelled).to.equal(true)
		probes[1].onOpened()
		probes[1].onFailed("late")
		expect(#attempts).to.equal(0)
		expect(controller:hasPendingWork()).to.equal(false)
	end)

	it("does not replace an active target", function()
		local controller, scheduled = createHarness()

		expect(controller:schedule({ key = "localhost:34872" })).to.equal(true)
		expect(controller:schedule({ key = "localhost:34873" })).to.equal(false)
		expect(#scheduled).to.equal(1)
	end)

	it("cancels the retry owner after a successful HTTP setup", function()
		local controller, scheduled, _, probes = createHarness()
		local target = { key = "localhost:34872" }

		controller:schedule(target)
		scheduled[1].callback()
		probes[1].onOpened()
		controller:cancel()

		expect(controller:attemptFailed(target)).to.equal(false)
		expect(controller:hasPendingWork()).to.equal(false)
	end)
end
