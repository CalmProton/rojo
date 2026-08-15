return function()
	local RequestLane = require(script.Parent.RequestLane)

	it("holds the lane until detached engine work settles", function()
		local lane = RequestLane.new()
		local settleFirst
		local secondStarted = false

		local first = lane:request(function(_, _, settle)
			settleFirst = settle
		end)
		task.wait()
		first:cancel()

		lane:request(function(_, _, settle)
			secondStarted = true
			settle()
		end)
		task.wait()
		expect(secondStarted).to.equal(false)

		settleFirst()
		task.wait()
		expect(secondStarted).to.equal(true)
	end)

	it("does not start a cancelled queued request", function()
		local lane = RequestLane.new()
		local settleFirst
		local queuedStarted = false

		lane:request(function(_, _, settle)
			settleFirst = settle
		end)
		task.wait()
		local queued = lane:request(function()
			queuedStarted = true
		end)
		task.wait()
		queued:cancel()

		settleFirst()
		task.wait()
		expect(queuedStarted).to.equal(false)
	end)
end
