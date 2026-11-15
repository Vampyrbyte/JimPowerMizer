-- Idle: the player's AFK flag, or no input for `timeout` seconds.
-- Long idle: no input for its own (longer) `timeout`, so a long absence can use another graphics
-- profile. It shares Idle's input tracking (and the mouse option); the AFK flag doesn't shorten it.
--
-- Input = moving your character, casting, changing target, looting, talking to an NPC, combat.
-- Movement comes from PLAYER_STARTED/STOPPED_MOVING, which only fire for your own movement, not
-- when a ship or zeppelin carries you (polled speed and facing do change on a transport).
-- Mouse and camera movement (cursor, facing, mouselook, turning) only count if the idle option
-- `mouseActivity` is on.
-- Loading screens (e.g. a ship or zeppelin crossing zones) aren't input: events and polled changes
-- during one and for LOAD_SETTLE seconds after are ignored, and an AFK flag set before the
-- loading screen still counts if the game drops it on the way.
local _, ns = ...
local L = ns.L

local AFK_GRACE = 5 -- with the AFK flag set, wait this long after the last input
local LOAD_SETTLE = 5 -- seconds after a loading screen during which nothing counts as input
local lastActivity = 0
local lastX, lastY, lastFacing
local inCombat = false
local movingByInput = false -- between PLAYER_STARTED_MOVING and PLAYER_STOPPED_MOVING
local loading = false -- between LOADING_SCREEN_ENABLED and LOADING_SCREEN_DISABLED
local settleUntil = 0 -- end of the post-loading-screen settle window
local afkCarried = false -- AFK when a loading screen started, no input since

-- Event -> activity name (for the debug line).
local ACTIVITY_EVENTS = {
	PLAYER_TARGET_CHANGED = "target", UNIT_SPELLCAST_SENT = "casting", LOOT_OPENED = "looting",
	GOSSIP_SHOW = "NPC", QUEST_DETAIL = "quest",
	-- Combat counts as activity (and combat outranks idle anyway).
	PLAYER_REGEN_DISABLED = "combat", PLAYER_REGEN_ENABLED = "combat",
}
local CAMERA_EVENTS = { PLAYER_STARTED_TURNING = "turning", PLAYER_STARTED_LOOKING = "camera" }

local function settings()
	return ns.addon.db.profile.situations.idle
end

local function events()
	local list = { "PLAYER_FLAGS_CHANGED", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_ENTERING_WORLD",
		"LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED" }
	for e in pairs(ACTIVITY_EVENTS) do list[#list + 1] = e end
	for e in pairs(CAMERA_EVENTS) do list[#list + 1] = e end
	return list
end

-- Record input. Logs (debug) what ended an idle period, or input after a long quiet spell.
local function activity(what, now)
	now = now or GetTime()
	if now - lastActivity >= 10 then
		ns.addon:Debug("Idle: input (%s) after %ds", what, math.floor(now - lastActivity))
	end
	lastActivity = now
	afkCarried = false
end

-- Inside a loading screen or the settle window after one.
local function settling(now)
	return loading or (now or GetTime()) < settleUntil
end

ns.Engine:RegisterSituation({
	key = "idle",
	name = L["Idle"],
	events = events(),
	poll = 1,
	OnEnable = function()
		lastActivity = GetTime()
		lastX, lastY, lastFacing = nil, nil, nil
		movingByInput = false
		loading, settleUntil, afkCarried = false, 0, false
	end,
	OnEvent = function(event)
		if event == "LOADING_SCREEN_ENABLED" then
			loading = true
			movingByInput = false
			if ns.Compat:IsAFK() then afkCarried = true end
		elseif event == "LOADING_SCREEN_DISABLED" or event == "PLAYER_ENTERING_WORLD" then
			loading = false
			movingByInput = false
			settleUntil = GetTime() + LOAD_SETTLE
			lastX, lastY, lastFacing = nil, nil, nil
		elseif event == "PLAYER_STOPPED_MOVING" then
			movingByInput = false
		elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
			activity("combat") -- real even right after a loading screen
		elseif settling() then
			-- Zoning fires target/movement/camera events the player didn't cause.
			if event == "PLAYER_STARTED_MOVING" or ACTIVITY_EVENTS[event] or CAMERA_EVENTS[event] then
				ns.addon:Debug("Idle: ignored %s after a loading screen", event)
			end
		elseif event == "PLAYER_STARTED_MOVING" then
			movingByInput = true
			activity("moving")
		elseif event == "PLAYER_FLAGS_CHANGED" then
			if not ns.Compat:IsAFK() then afkCarried = false end -- /afk toggled off
		elseif ACTIVITY_EVENTS[event] then
			activity(ACTIVITY_EVENTS[event])
		elseif CAMERA_EVENTS[event] and settings().mouseActivity then
			activity(CAMERA_EVENTS[event])
		end
		if event == "PLAYER_REGEN_DISABLED" then inCombat = true
		elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false end
	end,
	Evaluate = function()
		local now = GetTime()
		if inCombat then
			lastActivity = now
			return false
		end
		local moving, casting, x, y, facing = ns.Compat:GetActivitySnapshot()
		-- A missed STOPPED_MOVING mustn't block idle forever: "not moving" from the poll is reliable.
		if movingByInput and not moving then movingByInput = false end
		if settling(now) then
			-- Zoning moves the cursor, facing and cast state: only refresh the baselines.
			x, y, facing = nil, nil, nil
		elseif movingByInput then
			lastActivity = now -- still running: no log line every second
		elseif casting then
			activity("casting", now)
		elseif settings().mouseActivity then
			local cursorMoved = x ~= nil and lastX ~= nil and (math.abs(x - lastX) > 1 or math.abs(y - lastY) > 1)
			local turned = facing ~= nil and lastFacing ~= nil and math.abs(facing - lastFacing) > 0.01
			if cursorMoved then activity("mouse", now) elseif turned then activity("turning", now) end
		end
		lastX, lastY, lastFacing = x, y, facing

		local inactive = now - lastActivity
		if (ns.Compat:IsAFK() or afkCarried) and inactive >= AFK_GRACE then return true end
		return inactive >= (settings().timeout or 180)
	end,
})

ns.Engine:RegisterSituation({
	key = "longIdle",
	name = L["Long idle"],
	-- Idle (registered first) updates the shared input state on the same events and poll.
	events = { "PLAYER_ENTERING_WORLD" },
	poll = 1,
	Evaluate = function()
		if inCombat then return false end
		return GetTime() - lastActivity >= (ns.addon.db.profile.situations.longIdle.timeout or 900)
	end,
})

-- For /jpm status.
function ns.IdleSeconds()
	return GetTime() - lastActivity
end
