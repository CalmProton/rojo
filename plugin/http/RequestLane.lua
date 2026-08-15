local Promise = require(script.Parent.Parent.Promise)

local RequestLane = {}
RequestLane.__index = RequestLane

function RequestLane.new()
	return setmetatable({
		__active = nil,
		__queue = {},
	}, RequestLane)
end

function RequestLane:__pump()
	if self.__active ~= nil then
		return
	end

	local entry
	repeat
		entry = table.remove(self.__queue, 1)
	until entry == nil or not entry.cancelled

	if entry == nil then
		return
	end

	self.__active = entry
	local settled = false
	local function settle()
		if settled then
			return
		end
		settled = true

		if self.__active == entry then
			self.__active = nil
			self:__pump()
		end
	end

	local success, err = pcall(entry.start, entry.resolve, entry.reject, settle)
	if not success then
		settle()
		entry.reject(err)
	end
end

function RequestLane:request(start)
	assert(type(start) == "function", "start must be a function")

	return Promise.new(function(resolve, reject, onCancel)
		local entry = {
			start = start,
			resolve = resolve,
			reject = reject,
			cancelled = false,
		}

		if onCancel(function()
			entry.cancelled = true
			self:__pump()
		end) then
			return
		end

		table.insert(self.__queue, entry)
		self:__pump()
	end)
end

return RequestLane
