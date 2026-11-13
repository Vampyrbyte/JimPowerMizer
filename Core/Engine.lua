-- Situation engine: tracks which situations are active and applies the graphics profile of the
-- highest-priority one (or restores the user's settings when none is).
--
-- A situation is registered with:
--   ns.Engine:RegisterSituation({
--     key = "taxi", name = "Flight path",
--     events = { "PLAYER_CONTROL_LOST", ... },  -- re-evaluate when these fire
--     poll = 2,                                  -- optional: also re-evaluate every N seconds
--     Evaluate = function() return isActive end,
--   })
-- Per-situation settings (enabled, profile, priority, enterDelay) live in db.profile.situations.
local _, ns = ...

local Engine = {}
ns.Engine = Engine
LibStub("AceEvent-3.0"):Embed(Engine) -- own registrations, separate from other modules

local situations = {}       -- key -> definition
local order = {}            -- registration order
local activeSince = {}      -- key -> GetTime() when it became active, nil when inactive
local forced                -- key forced active by /jpm force, or nil
local enabled = false
local evalTimer, pollTimer
local current               -- key of the situation currently applied, or nil

function Engine:RegisterSituation(def)
	assert(def.key and def.Evaluate, "situation needs key and Evaluate")
	situations[def.key] = def
	order[#order + 1] = def.key
end

local function settings(key)
	return ns.addon.db.profile.situations[key]
end

-- Pick the winning situation among those active for at least their enterDelay.
-- Returns key, secondsUntilNextCandidate (for re-check scheduling).
local function resolve(now)
	if forced then return forced end
	local best, bestPriority, nextCheck
	for _, key in ipairs(order) do
		local cfg = settings(key)
		local since = activeSince[key]
		if cfg and cfg.enabled and since then
			local remaining = (cfg.enterDelay or 0) - (now - since)
			if remaining <= 0 then
				local p = cfg.priority or 0
				if not bestPriority or p > bestPriority then
					best, bestPriority = key, p
				end
			else
				nextCheck = math.min(nextCheck or remaining, remaining)
			end
		end
	end
	return best, nextCheck
end

function Engine:Evaluate(trigger)
	if not enabled then return end
	local now = GetTime()
	for _, key in ipairs(order) do
		local ok, isActive = pcall(situations[key].Evaluate)
		if not ok then
			ns.addon:Debug("Situation %s errored: %s", key, tostring(isActive))
			isActive = false
		end
		if isActive and not activeSince[key] then
			activeSince[key] = now
			ns.addon:Debug("Situation %s active (%s)", key, tostring(trigger))
		elseif not isActive and activeSince[key] then
			activeSince[key] = nil
			ns.addon:Debug("Situation %s ended (%s)", key, tostring(trigger))
		end
	end

	local winner, nextCheck = resolve(now)
	if winner ~= current then
		current = winner
		if winner then
			local cfg = settings(winner) or {}
			ns.Applier:Apply(cfg.profile, (situations[winner] and situations[winner].name) or winner)
		else
			ns.Applier:RestoreAll("situation ended")
		end
	end

	-- A situation is active but still inside its enterDelay: check again when it expires.
	if evalTimer then ns.addon:CancelTimer(evalTimer); evalTimer = nil end
	if nextCheck then
		evalTimer = ns.addon:ScheduleTimer(function()
			evalTimer = nil
			Engine:Evaluate("delay")
		end, nextCheck + 0.05)
	end
end

function Engine:GetCurrent()
	return current, situations[current or ""]
end

function Engine:GetActiveSituations()
	local list = {}
	for _, key in ipairs(order) do
		if activeSince[key] then list[#list + 1] = key end
	end
	return list
end

function Engine:GetSituation(key)
	return situations[key]
end

function Engine:Force(key)
	forced = key
	self:Evaluate("force")
end

function Engine:Enable()
	if enabled then return end
	enabled = true
	local addon = ns.addon
	local registered = {}
	local minPoll
	for _, key in ipairs(order) do
		local def = situations[key]
		for _, event in ipairs(def.events or {}) do
			if not registered[event] then
				registered[event] = true
				self:RegisterEvent(event, "Evaluate")
			end
		end
		if def.poll then minPoll = math.min(minPoll or def.poll, def.poll) end
	end
	if not registered.PLAYER_ENTERING_WORLD then
		self:RegisterEvent("PLAYER_ENTERING_WORLD", "Evaluate")
	end
	if minPoll then
		pollTimer = addon:ScheduleRepeatingTimer(function() Engine:Evaluate("poll") end, minPoll)
	end
	self:Evaluate("enable")
end

function Engine:Disable()
	if not enabled then return end
	local addon = ns.addon
	if pollTimer then addon:CancelTimer(pollTimer); pollTimer = nil end
	if evalTimer then addon:CancelTimer(evalTimer); evalTimer = nil end
	self:UnregisterAllEvents()
	wipe(activeSince)
	forced = nil
	enabled = false
	if current then
		current = nil
		ns.Applier:RestoreAll("disabled")
	end
end

function Engine:IsEnabled()
	return enabled
end
