-- Situation engine: tracks which situations are active and applies the graphics profile of the
-- highest-priority one (or restores the user's settings when none is).
--
-- A situation is registered with:
--   ns.Engine:RegisterSituation({
--     key = "taxi", name = "Flight path",
--     events = { "PLAYER_CONTROL_LOST", ... },  -- re-evaluate when these fire
--     poll = 2,                                  -- optional: also re-evaluate at least every N seconds
--                                                --   (all situations share the shortest interval)
--     OnEvent = function(event, ...) end,        -- optional: called for every engine event first
--     Evaluate = function() return isActive end,
--   })
-- Per-situation settings (enabled, profile, priority, enterDelay) live in db.profile.situations.
local _, ns = ...
local L = ns.L

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
local startupUntil = 0      -- situations becoming active before this time skip their enterDelay
local lastError = {}        -- key -> { msg, time }: rate-limit repeated situation errors in debug

local function reportError(key, what, err)
	err = tostring(err)
	local last, now = lastError[key], GetTime()
	if last and last.msg == err and now - last.time < 60 then return end
	lastError[key] = { msg = err, time = now }
	ns.addon:Debug("Situation %s %s errored: %s", key, what, err)
end

-- def.IsAvailable (optional): false on clients without the situation (e.g. delves on Forever). Asked
-- once the Compat layer is ready; such a situation is dropped and never shown.
local pruned = false
local function prune()
	if pruned or not ns.Compat.impl then return end
	pruned = true
	local kept = {}
	for _, key in ipairs(order) do
		local def = situations[key]
		local ok, available = true, true
		if def.IsAvailable then ok, available = pcall(def.IsAvailable) end
		if ok and available then kept[#kept + 1] = key else situations[key] = nil end
	end
	order = kept
end

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

function Engine:Evaluate(trigger, ...)
	if not enabled then return end
	-- Fires for every player nearby (AFK, DND, ...); only our own flags matter to any situation.
	if trigger == "PLAYER_FLAGS_CHANGED" and (...) ~= "player" then return end
	local now = GetTime()
	for _, key in ipairs(order) do
		local def = situations[key]
		if def.OnEvent and trigger then
			local ok, err = pcall(def.OnEvent, trigger, ...)
			if not ok then reportError(key, "OnEvent", err) end
		end
		local ok, isActive = pcall(def.Evaluate)
		if not ok then
			reportError(key, "Evaluate", isActive)
			isActive = false
		end
		if isActive and not activeSince[key] then
			-- Already active at login/reload: treat its enter delay as elapsed.
			activeSince[key] = (now < startupUntil) and (now - 1e6) or now
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
			-- profile false/nil = the user's own settings (e.g. combat, cinematics).
			ns.Applier:Apply(cfg.profile or nil, (situations[winner] and situations[winner].name) or winner)
		else
			ns.Applier:RestoreAll(L["situation ended"])
		end
		if ns.Options then ns.Options:Update() end
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
	prune()
	local list = {}
	for _, key in ipairs(order) do
		if activeSince[key] then list[#list + 1] = key end
	end
	return list
end

function Engine:GetSituation(key)
	prune()
	return situations[key]
end

-- Returns false if `key` can't be forced because the engine is off (it would otherwise be
-- remembered and applied when the engine is next turned on).
function Engine:Force(key)
	if key and not enabled then return false end
	forced = key
	self:Evaluate("force")
	return true
end

function Engine:Enable()
	if enabled then return end
	prune()
	enabled = true
	startupUntil = GetTime() + ns.STARTUP_GRACE
	for _, key in ipairs(order) do
		if situations[key].OnEnable then
			local ok, err = pcall(situations[key].OnEnable)
			if not ok then reportError(key, "OnEnable", err) end
		end
	end
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
		ns.Applier:RestoreAll(L["disabled"])
	end
end

-- Re-resolve after settings changed (e.g. the current situation now uses another profile).
function Engine:Refresh(reason)
	if not enabled then return end
	current = false -- never equals a winner or nil, so Evaluate always applies or restores
	self:Evaluate(reason or "settings")
end

function Engine:GetSituations()
	prune()
	return order, situations
end

function Engine:IsEnabled()
	return enabled
end
